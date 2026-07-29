defmodule Redis.Sentinel do
  @moduledoc """
  Sentinel-aware Redis connection.

  Queries sentinels to discover the current primary or replica, then
  maintains a connection. On disconnection, re-queries sentinels to
  find the (possibly new) primary.

  With `:read_preference`, the client maintains primary and replica
  connections, routes eligible reads to replicas, and keeps writes and
  transactions on the primary:

      {:ok, conn} = Redis.Sentinel.start_link(
        sentinels: [{"sentinel1", 26379}, {"sentinel2", 26379}],
        group: "mymaster",
        read_preference: :prefer_replica
      )

  ## Usage

      {:ok, conn} = Redis.Sentinel.start_link(
        sentinels: [{"sentinel1", 26379}, {"sentinel2", 26379}],
        group: "mymaster",
        role: :primary,
        password: "secret"
      )

      # Use like a normal connection — failover is transparent
      {:ok, "OK"} = Redis.Sentinel.command(conn, ["SET", "key", "value"])

  ## Options

    * `:sentinels` - list of sentinel addresses as `{host, port}` tuples or `"host:port"` strings (required)
    * `:group` - sentinel group name (required)
    * `:role` - `:primary` or `:replica` (default: `:primary`)
    * `:read_preference` - `:master` (default), `:replica`, or
      `:prefer_replica`. Cannot be combined with `role: :replica`.
    * `:read_only_commands` - extra command names that are safe to run on replicas
    * `:password` - password for the Redis server (not the sentinel)
    * `:sentinel_password` - password for sentinel connections
    * `:sentinel_username` - username for sentinel connections
    * `:username` - username for the Redis server
    * `:database` - database number
    * `:timeout` - connection timeout ms (default: 5_000)
    * `:sentinel_timeout` - sentinel query timeout ms (default: 500)
    * `:topology_refresh_interval` - Sentinel topology refresh interval in
      milliseconds for replica routing (default: 30_000; `nil` disables it)
    * `:name` - GenServer name registration
    * `:protocol` - `:resp3` or `:resp2` (default: `:resp3`)

  Command, pipeline, and transaction calls accept `response: :typed`; see
  `Redis.Response`.
  """

  use GenServer

  alias Redis.Connection
  alias Redis.Protocol.RESP2
  alias Redis.ReplicaSet
  alias Redis.ReplicaSet.Topology
  alias Redis.Response
  alias Redis.Sentinel.Monitor

  require Logger

  defstruct [
    :sentinels,
    :group,
    :role,
    :password,
    :sentinel_password,
    :sentinel_username,
    :username,
    :database,
    :timeout,
    :sentinel_timeout,
    :protocol,
    :conn,
    :current_addr,
    :read_preference,
    :read_only_commands,
    :replica_set,
    :topology_refresh_interval,
    replica_addrs: [],
    backoff_initial: 500,
    backoff_max: 30_000,
    backoff_current: 500,
    monitor: nil
  ]

  # -------------------------------------------------------------------
  # Public API
  # -------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc "Sends a command through the sentinel-managed connection."
  @spec command(GenServer.server(), [String.t()], keyword()) ::
          {:ok, term()} | {:error, term()}
  def command(sentinel, args, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5_000)

    sentinel
    |> GenServer.call({:command, args}, timeout)
    |> Response.decode(args, opts)
  end

  @spec pipeline(GenServer.server(), [[String.t()]], keyword()) ::
          {:ok, [term()]} | {:error, term()}
  def pipeline(sentinel, commands, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5_000)

    sentinel
    |> GenServer.call({:pipeline, commands}, timeout)
    |> Response.decode_many(commands, opts)
  end

  @spec transaction(GenServer.server(), [[String.t()]], keyword()) ::
          {:ok, [term()]} | {:error, term()}
  def transaction(sentinel, commands, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5_000)

    sentinel
    |> GenServer.call({:transaction, commands}, timeout)
    |> Response.decode_many(commands, opts)
  end

  @doc "Returns info about the current connection."
  @spec info(GenServer.server()) :: map()
  def info(sentinel), do: GenServer.call(sentinel, :info)

  @doc "Refreshes primary and replica topology from Sentinel."
  @spec refresh(GenServer.server()) :: :ok | {:error, term()}
  def refresh(sentinel), do: GenServer.call(sentinel, :refresh, 30_000)

  @spec stop(GenServer.server()) :: :ok
  def stop(sentinel), do: GenServer.stop(sentinel, :normal)

  # -------------------------------------------------------------------
  # GenServer callbacks
  # -------------------------------------------------------------------

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    sentinels = parse_sentinels(Keyword.fetch!(opts, :sentinels))
    group = Keyword.fetch!(opts, :group)

    state = %__MODULE__{
      sentinels: sentinels,
      group: group,
      role: Keyword.get(opts, :role, :primary),
      read_preference: Keyword.get(opts, :read_preference, :master),
      read_only_commands: Keyword.get(opts, :read_only_commands, []),
      password: Keyword.get(opts, :password),
      sentinel_password: Keyword.get(opts, :sentinel_password),
      sentinel_username: Keyword.get(opts, :sentinel_username),
      username: Keyword.get(opts, :username),
      database: Keyword.get(opts, :database),
      timeout: Keyword.get(opts, :timeout, 5_000),
      sentinel_timeout: Keyword.get(opts, :sentinel_timeout, 500),
      topology_refresh_interval: Keyword.get(opts, :topology_refresh_interval, 30_000),
      protocol: Keyword.get(opts, :protocol, :resp3),
      backoff_initial: Keyword.get(opts, :backoff_initial, 500),
      backoff_max: Keyword.get(opts, :backoff_max, 30_000),
      backoff_current: Keyword.get(opts, :backoff_initial, 500)
    }

    case validate_routing_options(state) do
      :ok -> initialize_connection(state)
      {:error, reason} -> {:stop, reason}
    end
  end

  defp initialize_connection(state) do
    connect_result =
      if replica_routing?(state) do
        resolve_and_start_replica_set(state)
      else
        resolve_and_connect(state)
      end

    case connect_result do
      {:ok, state} ->
        # Start failover monitor on the first reachable sentinel
        state = state |> start_monitor() |> schedule_topology_refresh()
        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  defp start_monitor(state) do
    # Try each sentinel until we can start a monitor
    monitor_pid =
      Enum.find_value(state.sentinels, fn {host, port} ->
        case Monitor.start_link(
               sentinel_host: host,
               sentinel_port: port,
               sentinel_password: state.sentinel_password,
               sentinel_username: state.sentinel_username,
               group: state.group,
               notify: self()
             ) do
          {:ok, pid} -> pid
          {:error, _} -> nil
        end
      end)

    %{state | monitor: monitor_pid}
  end

  @impl true
  def handle_call({:command, args}, _from, %{replica_set: replica_set} = state)
      when replica_set != nil do
    {:reply, ReplicaSet.command(replica_set, args, timeout: state.timeout), state}
  end

  def handle_call({:command, args}, _from, %{conn: conn} = state) when conn != nil do
    case Connection.command(conn, args) do
      {:error, %Redis.ConnectionError{}} = error ->
        # Connection died — try to reconnect
        state = reconnect(state)

        if state.conn do
          {:reply, Connection.command(state.conn, args), state}
        else
          {:reply, error, state}
        end

      result ->
        {:reply, result, state}
    end
  end

  def handle_call({:pipeline, commands}, _from, %{replica_set: replica_set} = state)
      when replica_set != nil do
    {:reply, ReplicaSet.pipeline(replica_set, commands, timeout: state.timeout), state}
  end

  def handle_call({:pipeline, commands}, _from, %{conn: conn} = state) when conn != nil do
    {:reply, Connection.pipeline(conn, commands), state}
  end

  def handle_call({:transaction, commands}, _from, %{replica_set: replica_set} = state)
      when replica_set != nil do
    {:reply, ReplicaSet.transaction(replica_set, commands, timeout: state.timeout), state}
  end

  def handle_call({:transaction, commands}, _from, %{conn: conn} = state) when conn != nil do
    {:reply, Connection.transaction(conn, commands), state}
  end

  def handle_call(:info, _from, state) do
    replica_info = replica_set_info(state.replica_set)

    info = %{
      group: state.group,
      role: state.role,
      read_preference: state.read_preference,
      current_addr: state.current_addr,
      replica_addrs: Map.get(replica_info, :replicas, state.replica_addrs),
      connected_replicas: Map.get(replica_info, :connected_replicas, []),
      sentinels: state.sentinels,
      connected: state.conn != nil or state.replica_set != nil
    }

    {:reply, info, state}
  end

  def handle_call(:refresh, _from, state) do
    if replica_routing?(state) do
      case resolve_or_refresh_replica_set(state) do
        {:ok, state} -> {:reply, :ok, state}
        {:error, reason} -> {:reply, {:error, reason}, state}
      end
    else
      {:reply, :ok, state}
    end
  end

  def handle_call(_msg, _from, %{conn: nil} = state) do
    {:reply, {:error, %Redis.ConnectionError{reason: :not_connected}}, state}
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, %{replica_set: pid} = state) when reason != :normal do
    Logger.warning("Redis.Sentinel: replica-set router exited, re-resolving via sentinels")
    state = %{state | replica_set: nil, current_addr: nil, replica_addrs: []}

    case resolve_and_start_replica_set(state) do
      {:ok, state} -> {:noreply, state}
      {:error, _reason} -> {:noreply, schedule_reconnect(state)}
    end
  end

  def handle_info({:EXIT, pid, reason}, %{conn: pid} = state) when reason != :normal do
    Logger.warning("Redis.Sentinel: connection lost, re-resolving via sentinels")
    state = %{state | conn: nil, current_addr: nil}

    case resolve_and_connect(state) do
      {:ok, state} -> {:noreply, state}
      {:error, _} -> {:noreply, schedule_reconnect(state)}
    end
  end

  def handle_info({:EXIT, _pid, _reason}, state), do: {:noreply, state}

  def handle_info(:reconnect, state) do
    result =
      if replica_routing?(state) do
        resolve_or_refresh_replica_set(state)
      else
        resolve_and_connect(state)
      end

    case result do
      {:ok, state} -> {:noreply, state}
      {:error, _} -> {:noreply, schedule_reconnect(state)}
    end
  end

  def handle_info(
        {:failover, group, _new_host, _new_port},
        %{
          group: group,
          replica_set: replica_set
        } = state
      )
      when replica_set != nil do
    send(self(), :refresh_sentinel_topology)
    {:noreply, state}
  end

  def handle_info(:refresh_sentinel_topology, state) do
    case resolve_or_refresh_replica_set(state) do
      {:ok, state} ->
        {:noreply, state}

      {:error, reason} ->
        Logger.warning("Redis.Sentinel: topology refresh failed: #{inspect(reason)}")
        Process.send_after(self(), :refresh_sentinel_topology, state.backoff_current)
        {:noreply, increase_backoff(state)}
    end
  end

  def handle_info(:refresh_replica_topology, state) do
    state =
      case resolve_or_refresh_replica_set(state) do
        {:ok, state} ->
          state

        {:error, reason} ->
          Logger.warning("Redis.Sentinel: periodic topology refresh failed: #{inspect(reason)}")
          state
      end

    {:noreply, schedule_topology_refresh(state)}
  end

  def handle_info(
        {:failover, group, _new_host, _new_port},
        %{group: group, role: :replica} = state
      ) do
    state = reconnect(state)

    if state.conn do
      {:noreply, state}
    else
      {:noreply, schedule_reconnect(state)}
    end
  end

  def handle_info({:failover, group, new_host, new_port}, %{group: group} = state) do
    Logger.info("Redis.Sentinel: proactive failover to #{new_host}:#{new_port}")

    # Stop old connection and connect to the new master
    if state.conn do
      try do
        Connection.stop(state.conn)
      catch
        :exit, _ -> :ok
      end
    end

    conn_opts =
      [host: new_host, port: new_port, protocol: state.protocol, timeout: state.timeout]
      |> maybe_put(:password, state.password)
      |> maybe_put(:username, state.username)
      |> maybe_put(:database, state.database)

    case Connection.start_link(conn_opts) do
      {:ok, conn} ->
        Logger.debug("Redis.Sentinel: connected to new master #{new_host}:#{new_port}")
        {:noreply, %{state | conn: conn, current_addr: {new_host, new_port}}}

      {:error, reason} ->
        Logger.warning("Redis.Sentinel: failed to connect to new master: #{inspect(reason)}")
        {:noreply, %{state | conn: nil, current_addr: nil}}
    end
  end

  def handle_info({:failover, _other_group, _host, _port}, state) do
    # Ignore failovers for other groups
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    if state.monitor do
      try do
        Monitor.stop(state.monitor)
      catch
        :exit, _ -> :ok
      end
    end

    if state.conn do
      try do
        Connection.stop(state.conn)
      catch
        :exit, _ -> :ok
      end
    end

    if state.replica_set do
      try do
        ReplicaSet.stop(state.replica_set)
      catch
        :exit, _ -> :ok
      end
    end
  end

  # -------------------------------------------------------------------
  # Sentinel resolution
  # -------------------------------------------------------------------

  defp resolve_and_start_replica_set(state) do
    with {:ok, primary, replicas} <- resolve_topology(state),
         {:ok, replica_set} <- ReplicaSet.start_link(replica_set_opts(state, primary, replicas)) do
      Logger.debug(
        "Redis.Sentinel: connected to primary #{format_address(primary)} " <>
          "with #{length(replicas)} replica(s)"
      )

      {:ok,
       %{
         state
         | replica_set: replica_set,
           current_addr: primary,
           replica_addrs: replicas,
           backoff_current: state.backoff_initial
       }}
    end
  end

  defp resolve_or_refresh_replica_set(%{replica_set: nil} = state),
    do: resolve_and_start_replica_set(state)

  defp resolve_or_refresh_replica_set(state) do
    with {:ok, primary, replicas} <- resolve_topology(state),
         :ok <- ReplicaSet.update_topology(state.replica_set, primary, replicas) do
      {:ok,
       %{
         state
         | current_addr: primary,
           replica_addrs: replicas,
           backoff_current: state.backoff_initial
       }}
    end
  end

  defp resolve_topology(state) do
    Enum.find_value(state.sentinels, {:error, :no_reachable_sentinel}, fn {host, port} ->
      case query_sentinel_topology(host, port, state) do
        {:ok, _primary, _replicas} = topology -> topology
        {:error, _reason} -> nil
      end
    end)
  end

  defp query_sentinel_topology(host, port, state) do
    opts =
      [
        host: host,
        port: port,
        protocol: :resp2,
        timeout: state.sentinel_timeout,
        exit_on_disconnection: true
      ]
      |> maybe_put(:password, state.sentinel_password)
      |> maybe_put(:username, state.sentinel_username)

    case Connection.start_link(opts) do
      {:ok, sentinel} ->
        result = fetch_sentinel_topology(sentinel, state)
        stop_connection(sentinel)
        result

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_sentinel_topology(sentinel, state) do
    with {:ok, [primary_host, primary_port]} <-
           Connection.command(
             sentinel,
             ["SENTINEL", "GET-MASTER-ADDR-BY-NAME", state.group],
             timeout: state.sentinel_timeout
           ),
         {:ok, primary_port} <- parse_port(primary_port),
         {:ok, replicas} <-
           Connection.command(
             sentinel,
             ["SENTINEL", "REPLICAS", state.group],
             timeout: state.sentinel_timeout
           ) do
      {:ok, {primary_host, primary_port}, Topology.parse_sentinel_replicas(replicas)}
    else
      {:ok, nil} -> {:error, {:unknown_group, state.group}}
      {:error, reason} -> {:error, reason}
      _unexpected -> {:error, :sentinel_query_failed}
    end
  end

  defp replica_set_opts(state, primary, replicas) do
    [
      primary: primary,
      replicas: replicas,
      read_preference: state.read_preference,
      read_only_commands: state.read_only_commands,
      topology_refresh_interval: nil,
      protocol: state.protocol,
      timeout: state.timeout
    ]
    |> maybe_put(:password, state.password)
    |> maybe_put(:username, state.username)
    |> maybe_put(:database, state.database)
  end

  defp resolve_and_connect(state) do
    with {:ok, host, port} <- resolve_address(state),
         conn_opts = build_conn_opts(state, host, port),
         {:ok, conn} <- Connection.start_link(conn_opts) do
      verify_and_finalize(state, conn, host, port)
    end
  end

  defp verify_and_finalize(state, conn, host, port) do
    case verify_role(conn, state.role) do
      :ok ->
        Logger.debug("Redis.Sentinel: connected to #{state.role} at #{host}:#{port}")

        {:ok,
         %{
           state
           | conn: conn,
             current_addr: {host, port},
             backoff_current: state.backoff_initial
         }}

      {:error, :wrong_role} ->
        Connection.stop(conn)
        {:error, :wrong_role}
    end
  end

  defp build_conn_opts(state, host, port) do
    [host: host, port: port, protocol: state.protocol, timeout: state.timeout]
    |> maybe_put(:password, state.password)
    |> maybe_put(:username, state.username)
    |> maybe_put(:database, state.database)
  end

  defp resolve_address(state) do
    Enum.find_value(state.sentinels, {:error, :no_reachable_sentinel}, fn {host, port} ->
      case query_sentinel(host, port, state) do
        {:ok, addr} -> {:ok, elem(addr, 0), elem(addr, 1)}
        {:error, _} -> nil
      end
    end)
  end

  defp query_sentinel(host, port, state) do
    # Connect to sentinel directly with RESP2 (sentinels don't support RESP3 HELLO)
    host_charlist = String.to_charlist(host)
    tcp_opts = [:binary, active: false, packet: :raw, nodelay: true]

    with {:ok, socket} <- :gen_tcp.connect(host_charlist, port, tcp_opts, state.sentinel_timeout),
         :ok <- maybe_auth_sentinel(socket, state),
         {:ok, result} <- query_sentinel_addr(socket, state) do
      :gen_tcp.close(socket)
      result
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_auth_sentinel(_socket, %{sentinel_password: nil}), do: :ok

  defp maybe_auth_sentinel(socket, state) do
    arguments =
      case state.sentinel_username do
        nil -> ["AUTH", state.sentinel_password]
        username -> ["AUTH", username, state.sentinel_password]
      end

    :gen_tcp.send(socket, RESP2.encode(arguments))

    case :gen_tcp.recv(socket, 0, state.sentinel_timeout) do
      {:ok, data} ->
        case RESP2.decode(data) do
          {:ok, "OK", _} -> :ok
          {:ok, %Redis.Error{message: msg}, _} -> {:error, {:sentinel_auth_failed, msg}}
          _ -> {:error, :sentinel_auth_failed}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp query_sentinel_addr(socket, %{role: :primary} = state) do
    cmd = RESP2.encode(["SENTINEL", "GET-MASTER-ADDR-BY-NAME", state.group])
    :gen_tcp.send(socket, cmd)

    case :gen_tcp.recv(socket, 0, state.sentinel_timeout) do
      {:ok, data} ->
        case RESP2.decode(data) do
          {:ok, [host, port_str], _} ->
            {:ok, {:ok, {host, String.to_integer(port_str)}}}

          {:ok, nil, _} ->
            {:error, {:unknown_group, state.group}}

          _ ->
            {:error, :sentinel_query_failed}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp query_sentinel_addr(socket, %{role: :replica} = state) do
    cmd = RESP2.encode(["SENTINEL", "REPLICAS", state.group])
    :gen_tcp.send(socket, cmd)

    case :gen_tcp.recv(socket, 0, state.sentinel_timeout) do
      {:ok, data} ->
        case RESP2.decode(data) do
          {:ok, [_ | _] = replicas, _} ->
            # Pick a random replica; each replica is a flat list of key-value pairs
            replica = Enum.random(replicas)
            replica_map = flat_list_to_map(replica)
            host = Map.get(replica_map, "ip")
            port = String.to_integer(Map.get(replica_map, "port", "6379"))
            {:ok, {:ok, {host, port}}}

          {:ok, [], _} ->
            {:error, :no_replicas}

          _ ->
            {:error, :sentinel_query_failed}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp verify_role(conn, expected_role) do
    case Connection.command(conn, ["ROLE"]) do
      {:ok, [role_str | _]} ->
        actual =
          case role_str do
            "master" -> :primary
            "slave" -> :replica
            "replica" -> :replica
            _other -> :unknown
          end

        if actual == expected_role, do: :ok, else: {:error, :wrong_role}

      _ ->
        # Can't verify — assume ok
        :ok
    end
  end

  # -------------------------------------------------------------------
  # Reconnection
  # -------------------------------------------------------------------

  defp reconnect(state) do
    if state.conn do
      try do
        Connection.stop(state.conn)
      catch
        :exit, _ -> :ok
      end
    end

    case resolve_and_connect(%{state | conn: nil}) do
      {:ok, new_state} -> new_state
      {:error, _} -> %{state | conn: nil, current_addr: nil}
    end
  end

  defp schedule_reconnect(state) do
    Process.send_after(self(), :reconnect, state.backoff_current)
    increase_backoff(state)
  end

  # -------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------

  defp validate_routing_options(%{role: role}) when role not in [:primary, :replica],
    do: {:error, {:invalid_role, role}}

  defp validate_routing_options(%{read_preference: preference})
       when preference not in [:master, :replica, :prefer_replica],
       do: {:error, {:invalid_read_preference, preference}}

  defp validate_routing_options(%{role: :replica, read_preference: preference})
       when preference != :master,
       do: {:error, :replica_role_conflicts_with_read_preference}

  defp validate_routing_options(_state), do: :ok

  defp replica_routing?(state),
    do: state.read_preference in [:replica, :prefer_replica]

  defp replica_set_info(nil), do: %{}

  defp replica_set_info(replica_set) do
    ReplicaSet.info(replica_set)
  catch
    :exit, _reason -> %{}
  end

  defp increase_backoff(state) do
    %{state | backoff_current: min(state.backoff_current * 2, state.backoff_max)}
  end

  defp schedule_topology_refresh(state) do
    if replica_routing?(state) and is_integer(state.topology_refresh_interval) and
         state.topology_refresh_interval > 0 do
      Process.send_after(self(), :refresh_replica_topology, state.topology_refresh_interval)
    end

    state
  end

  defp parse_port(port) when is_integer(port) and port in 1..65_535, do: {:ok, port}

  defp parse_port(port) when is_binary(port) do
    case Integer.parse(port) do
      {port, ""} when port in 1..65_535 -> {:ok, port}
      _ -> {:error, :invalid_port}
    end
  end

  defp parse_port(_port), do: {:error, :invalid_port}

  defp format_address({host, port}), do: "#{host}:#{port}"

  defp stop_connection(connection) do
    Connection.stop(connection)
  catch
    :exit, _reason -> :ok
  end

  defp parse_sentinels(sentinels) do
    Enum.map(sentinels, fn
      {host, port} ->
        {host, port}

      str when is_binary(str) ->
        case String.split(str, ":") do
          [host, port_str] -> {host, String.to_integer(port_str)}
          [host] -> {host, 26_379}
        end
    end)
  end

  defp flat_list_to_map(list) do
    list
    |> Enum.chunk_every(2)
    |> Map.new(fn
      [k, v] -> {k, v}
      [k] -> {k, nil}
    end)
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end

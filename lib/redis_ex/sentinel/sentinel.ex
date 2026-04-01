defmodule RedisEx.Sentinel do
  @moduledoc """
  Sentinel-aware Redis connection.

  Queries sentinels to discover the current primary or replica, then
  maintains a connection. On disconnection, re-queries sentinels to
  find the (possibly new) primary.

  ## Usage

      {:ok, conn} = RedisEx.Sentinel.start_link(
        sentinels: [{"sentinel1", 26379}, {"sentinel2", 26379}],
        group: "mymaster",
        role: :primary,
        password: "secret"
      )

      # Use like a normal connection — failover is transparent
      {:ok, "OK"} = RedisEx.Sentinel.command(conn, ["SET", "key", "value"])

  ## Options

    * `:sentinels` - list of sentinel addresses as `{host, port}` tuples or `"host:port"` strings (required)
    * `:group` - sentinel group name (required)
    * `:role` - `:primary` or `:replica` (default: `:primary`)
    * `:password` - password for the Redis server (not the sentinel)
    * `:sentinel_password` - password for sentinel connections
    * `:username` - username for the Redis server
    * `:database` - database number
    * `:timeout` - connection timeout ms (default: 5_000)
    * `:sentinel_timeout` - sentinel query timeout ms (default: 500)
    * `:name` - GenServer name registration
    * `:protocol` - `:resp3` or `:resp2` (default: `:resp3`)
  """

  use GenServer

  alias RedisEx.Connection
  alias RedisEx.Protocol.RESP2

  require Logger

  defstruct [
    :sentinels,
    :group,
    :role,
    :password,
    :sentinel_password,
    :username,
    :database,
    :timeout,
    :sentinel_timeout,
    :protocol,
    :conn,
    :current_addr,
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
    GenServer.call(sentinel, {:command, args}, timeout)
  end

  @spec pipeline(GenServer.server(), [[String.t()]], keyword()) ::
          {:ok, [term()]} | {:error, term()}
  def pipeline(sentinel, commands, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5_000)
    GenServer.call(sentinel, {:pipeline, commands}, timeout)
  end

  @spec transaction(GenServer.server(), [[String.t()]], keyword()) ::
          {:ok, [term()]} | {:error, term()}
  def transaction(sentinel, commands, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5_000)
    GenServer.call(sentinel, {:transaction, commands}, timeout)
  end

  @doc "Returns info about the current connection."
  @spec info(GenServer.server()) :: map()
  def info(sentinel), do: GenServer.call(sentinel, :info)

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
      password: Keyword.get(opts, :password),
      sentinel_password: Keyword.get(opts, :sentinel_password),
      username: Keyword.get(opts, :username),
      database: Keyword.get(opts, :database),
      timeout: Keyword.get(opts, :timeout, 5_000),
      sentinel_timeout: Keyword.get(opts, :sentinel_timeout, 500),
      protocol: Keyword.get(opts, :protocol, :resp3)
    }

    case resolve_and_connect(state) do
      {:ok, state} ->
        # Start failover monitor on the first reachable sentinel
        state = start_monitor(state)
        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  defp start_monitor(state) do
    # Try each sentinel until we can start a monitor
    monitor_pid =
      Enum.find_value(state.sentinels, fn {host, port} ->
        case RedisEx.Sentinel.Monitor.start_link(
               sentinel_host: host,
               sentinel_port: port,
               sentinel_password: state.sentinel_password,
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
  def handle_call({:command, args}, _from, %{conn: conn} = state) when conn != nil do
    case Connection.command(conn, args) do
      {:error, %RedisEx.ConnectionError{}} = error ->
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

  def handle_call({:pipeline, commands}, _from, %{conn: conn} = state) when conn != nil do
    {:reply, Connection.pipeline(conn, commands), state}
  end

  def handle_call({:transaction, commands}, _from, %{conn: conn} = state) when conn != nil do
    {:reply, Connection.transaction(conn, commands), state}
  end

  def handle_call(:info, _from, state) do
    info = %{
      group: state.group,
      role: state.role,
      current_addr: state.current_addr,
      sentinels: state.sentinels,
      connected: state.conn != nil
    }

    {:reply, info, state}
  end

  def handle_call(_msg, _from, %{conn: nil} = state) do
    {:reply, {:error, %RedisEx.ConnectionError{reason: :not_connected}}, state}
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, %{conn: pid} = state) when reason != :normal do
    Logger.warning("RedisEx.Sentinel: connection lost, re-resolving via sentinels")
    state = %{state | conn: nil, current_addr: nil}

    case resolve_and_connect(state) do
      {:ok, state} -> {:noreply, state}
      {:error, _} -> {:noreply, schedule_reconnect(state)}
    end
  end

  def handle_info({:EXIT, _pid, _reason}, state), do: {:noreply, state}

  def handle_info(:reconnect, state) do
    case resolve_and_connect(state) do
      {:ok, state} -> {:noreply, state}
      {:error, _} -> {:noreply, schedule_reconnect(state)}
    end
  end

  def handle_info({:failover, group, new_host, new_port}, %{group: group} = state) do
    Logger.info("RedisEx.Sentinel: proactive failover to #{new_host}:#{new_port}")

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
        Logger.debug("RedisEx.Sentinel: connected to new master #{new_host}:#{new_port}")
        {:noreply, %{state | conn: conn, current_addr: {new_host, new_port}}}

      {:error, reason} ->
        Logger.warning("RedisEx.Sentinel: failed to connect to new master: #{inspect(reason)}")
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
        RedisEx.Sentinel.Monitor.stop(state.monitor)
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
  end

  # -------------------------------------------------------------------
  # Sentinel resolution
  # -------------------------------------------------------------------

  defp resolve_and_connect(state) do
    case resolve_address(state) do
      {:ok, host, port} ->
        conn_opts =
          [
            host: host,
            port: port,
            protocol: state.protocol,
            timeout: state.timeout
          ]
          |> maybe_put(:password, state.password)
          |> maybe_put(:username, state.username)
          |> maybe_put(:database, state.database)

        case Connection.start_link(conn_opts) do
          {:ok, conn} ->
            # Verify role
            case verify_role(conn, state.role) do
              :ok ->
                Logger.debug("RedisEx.Sentinel: connected to #{state.role} at #{host}:#{port}")
                {:ok, %{state | conn: conn, current_addr: {host, port}, backoff_current: state.backoff_initial}}

              {:error, :wrong_role} ->
                Connection.stop(conn)
                {:error, :wrong_role}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
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

  defp maybe_auth_sentinel(socket, %{sentinel_password: pw, sentinel_timeout: timeout}) do
    :gen_tcp.send(socket, RESP2.encode(["AUTH", pw]))

    case :gen_tcp.recv(socket, 0, timeout) do
      {:ok, data} ->
        case RESP2.decode(data) do
          {:ok, "OK", _} -> :ok
          {:ok, %RedisEx.Error{message: msg}, _} -> {:error, {:sentinel_auth_failed, msg}}
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
          {:ok, replicas, _} when is_list(replicas) and length(replicas) > 0 ->
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
            other -> String.to_atom(other)
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
    %{state | backoff_current: min(state.backoff_current * 2, state.backoff_max)}
  end

  # -------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------

  defp parse_sentinels(sentinels) do
    Enum.map(sentinels, fn
      {host, port} -> {host, port}
      str when is_binary(str) ->
        case String.split(str, ":") do
          [host, port_str] -> {host, String.to_integer(port_str)}
          [host] -> {host, 26379}
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

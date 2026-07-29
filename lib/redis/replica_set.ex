defmodule Redis.ReplicaSet do
  @moduledoc """
  Routes writes to a Redis primary and eligible reads to replicas.

  `Redis.ReplicaSet` can use explicitly configured replicas:

      {:ok, redis} = Redis.ReplicaSet.start_link(
        primary: {"redis-primary", 6379},
        replicas: [{"redis-replica-1", 6379}, {"redis-replica-2", 6379}],
        read_preference: :prefer_replica
      )

  When `:replicas` is omitted, the process discovers online replicas from the
  primary's `INFO REPLICATION` response and periodically refreshes them:

      Redis.ReplicaSet.start_link(
        primary: "redis://redis-primary:6379",
        read_preference: :replica
      )

  Redis' `COMMAND` metadata determines which commands are read-only. Unknown
  commands are routed to the primary. Module or application-specific commands
  can be added with `:read_only_commands`.

  ## Read preferences

    * `:master` (default) - route every command to the primary
    * `:replica` - route reads to replicas. If replicas are configured but all
      fail, return the replica error. If none are available, use the primary.
    * `:prefer_replica` - route reads to replicas and fall back to the primary
      when replica execution fails

  Writes, mixed pipelines, transactions, and unknown commands always use the
  primary. Reads are distributed round-robin across connected replicas.

  ## Options

    * `:primary` - primary node as `{host, port}`, `"host:port"`, Redis URI, or
      connection keyword list (required)
    * `:replicas` - explicit list of replica nodes; omit for INFO discovery
    * `:read_preference` - `:master`, `:replica`, or `:prefer_replica`
    * `:read_only_commands` - extra command names that are safe on replicas
    * `:topology_refresh_interval` - INFO refresh interval in milliseconds
      (default: 30_000; applies only to discovered topology)

  Normal `Redis.Connection` options such as authentication, TLS, protocol,
  database, credential provider, and timeout are shared by all nodes. A node
  expressed as a keyword list or URI may override shared options.
  """

  use GenServer

  alias Redis.Connection
  alias Redis.ReplicaSet.{CommandMetadata, Topology}

  require Logger

  @connection_option_keys [
    :password,
    :username,
    :database,
    :ssl,
    :ssl_opts,
    :protocol,
    :timeout,
    :credential_provider,
    :client_name
  ]
  @read_preferences [:master, :replica, :prefer_replica]

  defstruct [
    :primary,
    :primary_spec,
    :read_commands,
    :read_preference,
    :connection_opts,
    :timeout,
    :topology_refresh_interval,
    replica_specs: %{},
    replicas: %{},
    replica_order: [],
    next_replica: 0,
    discover_replicas: false,
    extra_read_commands: []
  ]

  @type node_spec ::
          {String.t(), non_neg_integer()}
          | String.t()
          | keyword()

  # -------------------------------------------------------------------
  # Public API
  # -------------------------------------------------------------------

  @doc "Returns a child specification for a replica-set router."
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc "Routes a command according to its mutability and the configured read preference."
  @spec command(GenServer.server(), [term()], keyword()) :: {:ok, term()} | {:error, term()}
  def command(replica_set, arguments, opts \\ []) do
    GenServer.call(replica_set, {:command, arguments}, call_timeout(opts))
  end

  @doc "Routes an all-read pipeline to a replica and every other pipeline to the primary."
  @spec pipeline(GenServer.server(), [[term()]], keyword()) ::
          {:ok, [term()]} | {:error, term()}
  def pipeline(replica_set, commands, opts \\ []) do
    GenServer.call(replica_set, {:pipeline, commands}, call_timeout(opts))
  end

  @doc "Executes a transaction on the primary."
  @spec transaction(GenServer.server(), [[term()]], keyword()) ::
          {:ok, [term()]} | {:error, term()}
  def transaction(replica_set, commands, opts \\ []) do
    GenServer.call(replica_set, {:transaction, commands}, call_timeout(opts))
  end

  @doc "Replaces the primary and replica addresses without restarting the router."
  @spec update_topology(GenServer.server(), node_spec(), [node_spec()]) ::
          :ok | {:error, term()}
  def update_topology(replica_set, primary, replicas) do
    GenServer.call(replica_set, {:update_topology, primary, replicas}, 30_000)
  end

  @doc "Refreshes replica connections and INFO-discovered topology."
  @spec refresh(GenServer.server()) :: :ok | {:error, term()}
  def refresh(replica_set), do: GenServer.call(replica_set, :refresh, 30_000)

  @doc "Returns the current routing and topology state."
  @spec info(GenServer.server()) :: map()
  def info(replica_set), do: GenServer.call(replica_set, :info)

  @doc "Stops the replica-set router and all of its connections."
  @spec stop(GenServer.server()) :: :ok
  def stop(replica_set), do: GenServer.stop(replica_set, :normal)

  # -------------------------------------------------------------------
  # GenServer callbacks
  # -------------------------------------------------------------------

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    with {:ok, read_preference} <- validate_read_preference(opts),
         {:ok, primary_spec} <- opts |> Keyword.fetch!(:primary) |> normalize_node(),
         {:ok, configured_replicas} <- normalize_nodes(Keyword.get(opts, :replicas, [])),
         connection_opts = Keyword.take(opts, @connection_option_keys),
         timeout = Keyword.get(opts, :timeout, 5_000),
         {:ok, primary} <- connect_node(primary_spec, connection_opts, :primary, timeout) do
      extra_read_commands = Keyword.get(opts, :read_only_commands, [])
      discover_replicas = not Keyword.has_key?(opts, :replicas)

      replica_specs =
        initial_replica_specs(
          primary,
          configured_replicas,
          discover_replicas,
          timeout
        )

      state = %__MODULE__{
        primary: primary,
        primary_spec: primary_spec,
        read_commands: CommandMetadata.fetch(primary, extra_read_commands, timeout),
        read_preference: read_preference,
        connection_opts: connection_opts,
        timeout: timeout,
        topology_refresh_interval: Keyword.get(opts, :topology_refresh_interval, 30_000),
        discover_replicas: discover_replicas,
        extra_read_commands: extra_read_commands
      }

      state = reconcile_replicas(state, replica_specs)
      state = schedule_topology_refresh(state)
      {:ok, state}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call({:command, arguments}, _from, state) do
    if CommandMetadata.read_only?(state.read_commands, arguments) do
      {result, state} = execute_read(state, :command, arguments)
      {:reply, result, state}
    else
      {:reply, execute_primary(state, :command, arguments), state}
    end
  end

  def handle_call({:pipeline, []}, _from, state), do: {:reply, {:ok, []}, state}

  def handle_call({:pipeline, commands}, _from, state) do
    if Enum.all?(commands, &CommandMetadata.read_only?(state.read_commands, &1)) do
      {result, state} = execute_read(state, :pipeline, commands)
      {:reply, result, state}
    else
      {:reply, execute_primary(state, :pipeline, commands), state}
    end
  end

  def handle_call({:transaction, commands}, _from, state) do
    {:reply, execute_primary(state, :transaction, commands), state}
  end

  def handle_call({:update_topology, primary, replicas}, _from, state) do
    with {:ok, primary_spec} <- normalize_node(primary),
         {:ok, replica_specs} <- normalize_nodes(replicas),
         {:ok, state} <- replace_topology(state, primary_spec, replica_specs) do
      {:reply, :ok, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:refresh, _from, state) do
    case refresh_topology(state) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, reason, state} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:info, _from, state) do
    info = %{
      primary: node_key(state.primary_spec),
      replicas: Map.keys(state.replica_specs),
      connected_replicas: Map.keys(state.replicas),
      read_preference: state.read_preference,
      discovery: if(state.discover_replicas, do: :info, else: :configured)
    }

    {:reply, info, state}
  end

  @impl true
  def handle_info(:refresh_topology, state) do
    state =
      case refresh_topology(state) do
        {:ok, state} ->
          state

        {:error, reason, state} ->
          Logger.warning("Redis.ReplicaSet: topology refresh failed: #{inspect(reason)}")
          state
      end

    {:noreply, schedule_topology_refresh(state)}
  end

  def handle_info(:reconnect_primary, %{primary: nil} = state) do
    case connect_node(state.primary_spec, state.connection_opts, :primary, state.timeout) do
      {:ok, primary} ->
        read_commands =
          CommandMetadata.fetch(primary, state.extra_read_commands, state.timeout)

        {:noreply, %{state | primary: primary, read_commands: read_commands}}

      {:error, _reason} ->
        Process.send_after(self(), :reconnect_primary, 500)
        {:noreply, state}
    end
  end

  def handle_info(:reconnect_primary, state), do: {:noreply, state}

  def handle_info({:EXIT, pid, reason}, %{primary: pid} = state) do
    if reason != :normal do
      Logger.warning("Redis.ReplicaSet: primary connection exited: #{inspect(reason)}")
    end

    Process.send_after(self(), :reconnect_primary, 0)
    {:noreply, %{state | primary: nil}}
  end

  def handle_info({:EXIT, pid, reason}, state) do
    case Enum.find(state.replicas, fn {_address, connection} -> connection == pid end) do
      {address, ^pid} ->
        if reason != :normal do
          Logger.warning(
            "Redis.ReplicaSet: replica connection #{inspect(address)} exited: #{inspect(reason)}"
          )
        end

        replicas = Map.delete(state.replicas, address)
        order = Enum.reject(state.replica_order, &(&1 == address))
        Process.send_after(self(), :reconnect_replicas, 0)
        {:noreply, %{state | replicas: replicas, replica_order: order}}

      nil ->
        {:noreply, state}
    end
  end

  def handle_info(:reconnect_replicas, state) do
    {:noreply, reconcile_replicas(state, state.replica_specs)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    stop_connection(state.primary)
    Enum.each(state.replicas, fn {_address, connection} -> stop_connection(connection) end)
    :ok
  end

  # -------------------------------------------------------------------
  # Routing
  # -------------------------------------------------------------------

  defp execute_read(%{read_preference: :master} = state, operation, payload) do
    {execute_primary(state, operation, payload), state}
  end

  defp execute_read(state, operation, payload) do
    {candidates, state} = replica_candidates(state)

    case try_replicas(candidates, operation, payload, state.timeout) do
      {:result, result} ->
        {result, state}

      :no_replicas ->
        {execute_primary(state, operation, payload), state}

      {:failed, last_error} when state.read_preference == :prefer_replica ->
        _ = last_error
        {execute_primary(state, operation, payload), state}

      {:failed, last_error} ->
        {last_error, state}
    end
  end

  defp execute_primary(%{primary: nil}, _operation, _payload),
    do: {:error, %Redis.ConnectionError{reason: :not_connected}}

  defp execute_primary(state, operation, payload) do
    safe_execute(state.primary, operation, payload, state.timeout)
  end

  defp replica_candidates(%{replica_order: []} = state), do: {[], state}

  defp replica_candidates(state) do
    count = length(state.replica_order)
    index = rem(state.next_replica, count)
    {left, right} = Enum.split(state.replica_order, index)
    addresses = right ++ left

    candidates =
      Enum.flat_map(addresses, fn address ->
        case Map.fetch(state.replicas, address) do
          {:ok, connection} -> [connection]
          :error -> []
        end
      end)

    {candidates, %{state | next_replica: rem(index + 1, count)}}
  end

  defp try_replicas([], _operation, _payload, _timeout), do: :no_replicas

  defp try_replicas(candidates, operation, payload, timeout) do
    Enum.reduce_while(candidates, :no_replicas, fn connection, _last_error ->
      case safe_execute(connection, operation, payload, timeout) do
        {:error, %Redis.ConnectionError{}} = error -> {:cont, {:failed, error}}
        result -> {:halt, {:result, result}}
      end
    end)
  end

  defp safe_execute(connection, :command, arguments, timeout),
    do: safe_call(fn -> Connection.command(connection, arguments, timeout: timeout) end)

  defp safe_execute(connection, :pipeline, commands, timeout),
    do: safe_call(fn -> Connection.pipeline(connection, commands, timeout: timeout) end)

  defp safe_execute(connection, :transaction, commands, timeout),
    do: safe_call(fn -> Connection.transaction(connection, commands, timeout: timeout) end)

  defp safe_call(function) do
    function.()
  catch
    :exit, _reason -> {:error, %Redis.ConnectionError{reason: :connection_exited}}
  end

  # -------------------------------------------------------------------
  # Topology
  # -------------------------------------------------------------------

  defp initial_replica_specs(primary, _configured, true, timeout) do
    case Topology.discover(primary, timeout) do
      {:ok, replicas} ->
        normalize_nodes!(replicas)

      {:error, reason} ->
        Logger.warning("Redis.ReplicaSet: INFO replica discovery failed: #{inspect(reason)}")
        %{}
    end
  end

  defp initial_replica_specs(_primary, configured, false, _timeout),
    do: specs_by_key(configured)

  defp refresh_topology(%{discover_replicas: true, primary: primary} = state)
       when primary != nil do
    case Topology.discover(primary, state.timeout) do
      {:ok, replicas} ->
        {:ok, reconcile_replicas(state, normalize_nodes!(replicas))}

      {:error, reason} ->
        {:error, reason, reconcile_replicas(state, state.replica_specs)}
    end
  end

  defp refresh_topology(state),
    do: {:ok, reconcile_replicas(state, state.replica_specs)}

  defp replace_topology(state, primary_spec, replica_specs) do
    replica_specs = specs_by_key(replica_specs)

    if node_key(primary_spec) == node_key(state.primary_spec) and state.primary != nil do
      {:ok, reconcile_replicas(state, replica_specs)}
    else
      with {:ok, primary} <-
             connect_node(primary_spec, state.connection_opts, :primary, state.timeout) do
        old_primary = state.primary

        state =
          %{
            state
            | primary: primary,
              primary_spec: primary_spec,
              read_commands:
                CommandMetadata.fetch(primary, state.extra_read_commands, state.timeout)
          }
          |> reconcile_replicas(replica_specs)

        stop_connection(old_primary)
        {:ok, state}
      end
    end
  end

  defp reconcile_replicas(state, desired_specs) do
    desired_specs =
      desired_specs
      |> specs_by_key()
      |> Map.delete(node_key(state.primary_spec))

    desired_keys = Map.keys(desired_specs) |> MapSet.new()

    {kept, stale} =
      Map.split_with(state.replicas, fn {address, _connection} ->
        MapSet.member?(desired_keys, address)
      end)

    Enum.each(stale, fn {_address, connection} -> stop_connection(connection) end)

    replicas =
      Enum.reduce(
        desired_specs,
        kept,
        &ensure_replica_connection(&1, &2, state)
      )

    order = desired_specs |> Map.keys() |> Enum.filter(&Map.has_key?(replicas, &1)) |> Enum.sort()

    %{
      state
      | replica_specs: desired_specs,
        replicas: replicas,
        replica_order: order,
        next_replica: normalize_index(state.next_replica, length(order))
    }
  end

  defp ensure_replica_connection({address, _spec}, connections, _state)
       when is_map_key(connections, address),
       do: connections

  defp ensure_replica_connection({address, spec}, connections, state) do
    case connect_node(spec, state.connection_opts, :replica, state.timeout) do
      {:ok, connection} ->
        Map.put(connections, address, connection)

      {:error, reason} ->
        Logger.warning(
          "Redis.ReplicaSet: replica #{inspect(address)} unavailable: #{inspect(reason)}"
        )

        connections
    end
  end

  defp connect_node(spec, shared_opts, expected_role, timeout) do
    opts = Keyword.merge(shared_opts, spec)

    with {:ok, connection} <- Connection.start_link(opts),
         :ok <- verify_role(connection, expected_role, timeout) do
      {:ok, connection}
    else
      {:error, {:wrong_role, _actual} = reason} ->
        {:error, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp verify_role(connection, expected_role, timeout) do
    case Connection.command(connection, ["ROLE"], timeout: timeout) do
      {:ok, [role | _rest]} ->
        actual_role = normalize_role(role)

        if actual_role == expected_role do
          :ok
        else
          stop_connection(connection)
          {:error, {:wrong_role, actual_role}}
        end

      {:error, reason} ->
        stop_connection(connection)
        {:error, reason}

      _unexpected ->
        stop_connection(connection)
        {:error, :role_verification_failed}
    end
  end

  defp normalize_role("master"), do: :primary
  defp normalize_role("primary"), do: :primary
  defp normalize_role("slave"), do: :replica
  defp normalize_role("replica"), do: :replica
  defp normalize_role(_role), do: :unknown

  # -------------------------------------------------------------------
  # Node options
  # -------------------------------------------------------------------

  defp validate_read_preference(opts) do
    case Keyword.get(opts, :read_preference, :master) do
      preference when preference in @read_preferences -> {:ok, preference}
      :primary -> {:ok, :master}
      invalid -> {:error, {:invalid_read_preference, invalid}}
    end
  end

  defp normalize_nodes(nodes) when is_list(nodes) do
    Enum.reduce_while(nodes, {:ok, []}, fn node, {:ok, normalized} ->
      case normalize_node(node) do
        {:ok, spec} -> {:cont, {:ok, [spec | normalized]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      error -> error
    end
  end

  defp normalize_nodes(_nodes), do: {:error, :invalid_replicas}

  defp normalize_nodes!(nodes) do
    case normalize_nodes(nodes) do
      {:ok, specs} -> specs_by_key(specs)
      {:error, _reason} -> %{}
    end
  end

  defp normalize_node({host, port})
       when (is_binary(host) or is_list(host)) and port in 1..65_535 do
    {:ok, [host: to_string(host), port: port]}
  end

  defp normalize_node("redis://" <> _rest = uri), do: {:ok, Redis.URI.parse(uri)}
  defp normalize_node("rediss://" <> _rest = uri), do: {:ok, Redis.URI.parse(uri)}
  defp normalize_node("valkey://" <> _rest = uri), do: {:ok, Redis.URI.parse(uri)}

  defp normalize_node(address) when is_binary(address) do
    case String.split(address, ":", parts: 2) do
      [host, port] ->
        case Integer.parse(port) do
          {port, ""} when port in 1..65_535 -> {:ok, [host: host, port: port]}
          _ -> {:error, {:invalid_node, address}}
        end

      [host] when host != "" ->
        {:ok, [host: host, port: 6379]}

      _ ->
        {:error, {:invalid_node, address}}
    end
  end

  defp normalize_node(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      cond do
        is_binary(Keyword.get(opts, :socket)) ->
          {:ok, opts}

        (is_binary(Keyword.get(opts, :host)) or is_list(Keyword.get(opts, :host))) and
            Keyword.get(opts, :port, 6379) in 1..65_535 ->
          {:ok, Keyword.put_new(opts, :port, 6379)}

        true ->
          {:error, {:invalid_node, opts}}
      end
    else
      {:error, {:invalid_node, opts}}
    end
  end

  defp normalize_node(node), do: {:error, {:invalid_node, node}}

  defp specs_by_key(specs) when is_map(specs), do: specs
  defp specs_by_key(specs), do: Map.new(specs, &{node_key(&1), &1})

  defp node_key(spec) do
    case Keyword.get(spec, :socket) do
      nil -> {to_string(Keyword.get(spec, :host, "127.0.0.1")), Keyword.get(spec, :port, 6379)}
      socket -> {:local, socket}
    end
  end

  # -------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------

  defp call_timeout(opts), do: Keyword.get(opts, :timeout, 10_000)

  defp schedule_topology_refresh(state) do
    if state.discover_replicas and is_integer(state.topology_refresh_interval) and
         state.topology_refresh_interval > 0 do
      Process.send_after(self(), :refresh_topology, state.topology_refresh_interval)
    end

    state
  end

  defp normalize_index(_index, 0), do: 0
  defp normalize_index(index, count), do: rem(index, count)

  defp stop_connection(nil), do: :ok

  defp stop_connection(connection) do
    Connection.stop(connection)
  catch
    :exit, _reason -> :ok
  end
end

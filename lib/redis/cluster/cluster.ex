defmodule Redis.Cluster do
  @moduledoc """
  Redis Cluster client.

  Maintains topology awareness, routes commands to the correct node based on
  hash slot, and handles MOVED/ASK redirects transparently.

  ## Usage

      {:ok, cluster} = Redis.Cluster.start_link(
        nodes: [{"127.0.0.1", 7000}, {"127.0.0.1", 7001}],
        password: "secret"
      )

      {:ok, "OK"} = Redis.Cluster.command(cluster, ["SET", "mykey", "myvalue"])
      {:ok, "myvalue"} = Redis.Cluster.command(cluster, ["GET", "mykey"])

  ## Options

    * `:nodes` - list of seed nodes as `{host, port}` tuples or `"host:port"` strings
    * `:password` - Redis password (applied to all nodes)
    * `:name` - GenServer name registration
    * `:timeout` - command timeout ms (default: 5_000)
    * `:max_redirects` - max MOVED/ASK redirects before failing (default: 5)
  """

  use GenServer

  alias Redis.Cluster.{Router, Topology}
  alias Redis.Connection

  require Logger

  defstruct [
    :password,
    :timeout,
    :slot_table,
    seed_nodes: [],
    # {host, port} => conn pid
    connections: %{},
    max_redirects: 5
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

  @doc "Sends a command, routed to the correct node by key hash slot."
  @spec command(GenServer.server(), [String.t()], keyword()) ::
          {:ok, term()} | {:error, term()}
  def command(cluster, args, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 10_000)
    GenServer.call(cluster, {:command, args}, timeout)
  end

  @doc """
  Sends a pipeline of commands. If all commands target the same hash slot,
  they are sent as a single pipeline. Otherwise, commands are automatically
  split by slot, sent in parallel to the correct nodes, and results are
  reassembled in the original command order.
  """
  @spec pipeline(GenServer.server(), [[String.t()]], keyword()) ::
          {:ok, [term()]} | {:error, term()}
  def pipeline(cluster, commands, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 10_000)
    GenServer.call(cluster, {:pipeline, commands}, timeout)
  end

  @doc """
  Executes a MULTI/EXEC transaction in cluster mode.

  All commands must target the same hash slot. Returns `{:error, :cross_slot}`
  if commands span multiple slots. Use hash tags (e.g. `{user}.name`) to
  ensure related keys land in the same slot.

      Cluster.transaction(cluster, [
        ["SET", "{user:1}.name", "Alice"],
        ["SET", "{user:1}.email", "alice@example.com"]
      ])
  """
  @spec transaction(GenServer.server(), [[String.t()]], keyword()) ::
          {:ok, [term()]} | {:error, term()}
  def transaction(cluster, commands, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 10_000)
    GenServer.call(cluster, {:transaction, commands}, timeout)
  end

  @doc """
  Executes a WATCH-based optimistic locking transaction in cluster mode.

  All watched keys and all commands produced by the function must target
  the same hash slot. Returns `{:error, :cross_slot}` if they don't.

      Cluster.watch_transaction(cluster, ["{acct:1}.balance"], fn conn ->
        {:ok, bal} = Redis.Connection.command(conn, ["GET", "{acct:1}.balance"])
        new_bal = String.to_integer(bal) + 100
        [["SET", "{acct:1}.balance", to_string(new_bal)]]
      end)
  """
  @spec watch_transaction(
          GenServer.server(),
          [String.t()],
          (GenServer.server() -> [[String.t()]] | {:abort, term()}),
          keyword()
        ) :: {:ok, [term()]} | {:error, term()}
  def watch_transaction(cluster, keys, fun, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 10_000)
    GenServer.call(cluster, {:watch_transaction, keys, fun, opts}, timeout)
  end

  @doc "Returns cluster info: nodes, slot coverage."
  @spec info(GenServer.server()) :: map()
  def info(cluster), do: GenServer.call(cluster, :info)

  @doc "Forces a topology refresh."
  @spec refresh(GenServer.server()) :: :ok | {:error, term()}
  def refresh(cluster), do: GenServer.call(cluster, :refresh, 30_000)

  @spec stop(GenServer.server()) :: :ok
  def stop(cluster), do: GenServer.stop(cluster, :normal)

  # -------------------------------------------------------------------
  # GenServer callbacks
  # -------------------------------------------------------------------

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    seed_nodes = parse_nodes(Keyword.get(opts, :nodes, [{"127.0.0.1", 7000}]))
    password = Keyword.get(opts, :password)
    timeout = Keyword.get(opts, :timeout, 5_000)
    max_redirects = Keyword.get(opts, :max_redirects, 5)

    slot_table = :ets.new(:redis_cluster_slots, [:set, :protected])

    state = %__MODULE__{
      seed_nodes: seed_nodes,
      password: password,
      timeout: timeout,
      slot_table: slot_table,
      max_redirects: max_redirects
    }

    case discover_topology(state) do
      {:ok, state} ->
        {:ok, state}

      {:error, reason} ->
        :ets.delete(slot_table)
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:command, args}, _from, state) do
    case Router.slot_for_command(args) do
      {:ok, slot} ->
        {result, state} = execute_with_redirects(state, slot, args, :command, state.max_redirects)
        {:reply, result, state}

      {:error, :no_key} ->
        # Key-less commands (PING, INFO, etc.) — send to any node
        case any_connection(state) do
          {:ok, conn} -> {:reply, Connection.command(conn, args), state}
          error -> {:reply, error, state}
        end
    end
  end

  def handle_call({:pipeline, commands}, _from, state) do
    case Router.validate_pipeline(commands) do
      {:ok, slot} ->
        case get_connection_for_slot(state, slot) do
          {:ok, conn} ->
            {:reply, Connection.pipeline(conn, commands), state}

          error ->
            {:reply, error, state}
        end

      {:error, :cross_slot} ->
        {:reply, execute_split_pipeline(state, commands), state}

      {:error, :empty} ->
        {:reply, {:ok, []}, state}
    end
  end

  def handle_call({:transaction, commands}, _from, state) do
    case Router.validate_pipeline(commands) do
      {:ok, slot} ->
        case get_connection_for_slot(state, slot) do
          {:ok, conn} ->
            {:reply, Connection.transaction(conn, commands), state}

          error ->
            {:reply, error, state}
        end

      {:error, :cross_slot} ->
        {:reply, {:error, :cross_slot}, state}

      {:error, :empty} ->
        {:reply, {:error, :empty_transaction}, state}
    end
  end

  def handle_call({:watch_transaction, keys, fun, opts}, _from, state) do
    key_slots = keys |> Enum.map(&Router.slot/1) |> Enum.uniq()

    case key_slots do
      [slot] ->
        case get_connection_for_slot(state, slot) do
          {:ok, conn} ->
            result =
              Connection.watch_transaction(conn, keys, fun, opts)

            {:reply, result, state}

          error ->
            {:reply, error, state}
        end

      [] ->
        {:reply, {:error, :no_keys}, state}

      _ ->
        {:reply, {:error, :cross_slot}, state}
    end
  end

  def handle_call(:info, _from, state) do
    nodes =
      Map.keys(state.connections)
      |> Enum.map(fn {host, port} -> "#{host}:#{port}" end)

    slot_coverage = :ets.info(state.slot_table, :size)

    {:reply, %{nodes: nodes, slot_coverage: slot_coverage, seed_nodes: state.seed_nodes}, state}
  end

  def handle_call(:get_connections, _from, state) do
    {:reply, state.connections, state}
  end

  def handle_call(:refresh, _from, state) do
    case refresh_topology(state) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, state) do
    # A connection died — remove it so we reconnect on next use
    if reason != :normal do
      Logger.warning("Redis.Cluster: node connection #{inspect(pid)} died: #{inspect(reason)}")
    end

    connections =
      state.connections
      |> Enum.reject(fn {_addr, conn_pid} -> conn_pid == pid end)
      |> Map.new()

    {:noreply, %{state | connections: connections}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.connections, fn {_addr, pid} ->
      try do
        Connection.stop(pid)
      catch
        :exit, _ -> :ok
      end
    end)

    if state.slot_table, do: :ets.delete(state.slot_table)
    :ok
  end

  # -------------------------------------------------------------------
  # Topology discovery
  # -------------------------------------------------------------------

  defp discover_topology(state) do
    # Try each seed node until one works
    Enum.reduce_while(state.seed_nodes, {:error, :no_reachable_node}, fn {host, port}, _acc ->
      case discover_from_node(state, host, port) do
        {:ok, state} -> {:halt, {:ok, state}}
        {:error, reason} -> {:cont, {:error, reason}}
      end
    end)
  end

  defp discover_from_node(state, host, port) do
    case connect_node(state, host, port) do
      {:ok, conn} ->
        case Connection.command(conn, ["CLUSTER", "SLOTS"]) do
          {:ok, slots_data} ->
            apply_topology(state, slots_data, {host, port}, conn)

          {:error, reason} ->
            Connection.stop(conn)
            {:error, reason}
        end

      {:error, _reason} ->
        {:error, :no_reachable_node}
    end
  end

  defp apply_topology(state, slots_data, {host, port}, conn) do
    parsed = Topology.parse_slots(slots_data)
    slot_entries = Topology.build_slot_map(parsed)

    :ets.delete_all_objects(state.slot_table)
    :ets.insert(state.slot_table, slot_entries)

    nodes = Enum.uniq(Enum.map(parsed, fn {_, _, h, p} -> {h, p} end))
    connections = connect_discovered_nodes(state, nodes, %{{host, port} => conn})

    Logger.debug(
      "Redis.Cluster: discovered #{length(nodes)} nodes, #{length(slot_entries)} slots"
    )

    {:ok, %{state | connections: connections}}
  end

  defp connect_discovered_nodes(state, nodes, initial_conns) do
    Enum.reduce(nodes, initial_conns, fn {h, p}, conns ->
      maybe_connect_node(state, conns, h, p)
    end)
  end

  defp maybe_connect_node(_state, conns, h, p) when is_map_key(conns, {h, p}), do: conns

  defp maybe_connect_node(state, conns, h, p) do
    case connect_node(state, h, p) do
      {:ok, node_conn} -> Map.put(conns, {h, p}, node_conn)
      {:error, _} -> conns
    end
  end

  defp refresh_topology(state) do
    # Try any existing connection first, with a short timeout to skip dead nodes quickly
    result =
      Enum.find_value(state.connections, fn {_addr, conn} ->
        case Connection.command(conn, ["CLUSTER", "SLOTS"], timeout: 2_000) do
          {:ok, data} -> {:ok, data}
          _ -> nil
        end
      end)

    case result do
      {:ok, slots_data} ->
        refresh_from_slots(state, slots_data)

      nil ->
        # Fall back to seed nodes
        discover_topology(%{state | connections: %{}})
    end
  end

  defp refresh_from_slots(state, slots_data) do
    parsed = Topology.parse_slots(slots_data)
    slot_entries = Topology.build_slot_map(parsed)

    :ets.delete_all_objects(state.slot_table)
    :ets.insert(state.slot_table, slot_entries)

    nodes = Enum.uniq(Enum.map(parsed, fn {_, _, h, p} -> {h, p} end))
    node_set = MapSet.new(nodes)

    # Drop connections to nodes no longer in the topology
    {kept, stale} = Map.split_with(state.connections, fn {addr, _} -> addr in node_set end)

    Enum.each(stale, fn {addr, conn} ->
      Logger.debug("Redis.Cluster: dropping stale connection to #{inspect(addr)}")

      try do
        Connection.stop(conn)
      catch
        :exit, _ -> :ok
      end
    end)

    connections = connect_discovered_nodes(state, nodes, kept)

    {:ok, %{state | connections: connections}}
  end

  # -------------------------------------------------------------------
  # Command execution with redirect handling
  # -------------------------------------------------------------------

  defp execute_with_redirects(state, _slot, _args, _type, 0) do
    {{:error, :too_many_redirects}, state}
  end

  defp execute_with_redirects(state, slot, args, type, redirects_left) do
    case get_connection_for_slot(state, slot) do
      {:ok, conn} ->
        handle_execution_result(
          execute_on(conn, args, type),
          state,
          slot,
          args,
          type,
          redirects_left
        )

      {:error, _} = error ->
        # No connection for this slot — try refreshing topology
        case refresh_topology(state) do
          {:ok, state} -> execute_with_redirects(state, slot, args, type, redirects_left - 1)
          _ -> {error, state}
        end
    end
  end

  defp handle_execution_result(
         {:error, %Redis.Error{message: "MOVED " <> rest}},
         state,
         slot,
         args,
         type,
         redirects_left
       ) do
    Logger.debug("Redis.Cluster: MOVED redirect: #{rest}")
    {_new_slot, host, port} = parse_redirect(rest)
    state = ensure_connection(state, host, port)
    state = refresh_topology_best_effort(state)
    execute_with_redirects(state, slot, args, type, redirects_left - 1)
  end

  defp handle_execution_result(
         {:error, %Redis.Error{message: "ASK " <> rest}},
         state,
         _slot,
         args,
         _type,
         _redirects_left
       ) do
    Logger.debug("Redis.Cluster: ASK redirect: #{rest}")
    {_new_slot, host, port} = parse_redirect(rest)
    state = ensure_connection(state, host, port)
    handle_ask_redirect(state, host, port, args)
  end

  defp handle_execution_result(result, state, _slot, _args, _type, _redirects_left) do
    {result, state}
  end

  defp handle_ask_redirect(state, host, port, args) do
    case Map.get(state.connections, {host, port}) do
      nil ->
        {{:error, :node_unavailable}, state}

      target_conn ->
        case Connection.pipeline(target_conn, [["ASKING"], args]) do
          {:ok, [_asking_ok, result]} -> {wrap_result(result), state}
          {:ok, _other} -> {{:error, :ask_failed}, state}
          error -> {error, state}
        end
    end
  end

  defp refresh_topology_best_effort(state) do
    case refresh_topology(state) do
      {:ok, state} -> state
      {:error, _} -> state
    end
  end

  defp execute_on(conn, args, :command), do: Connection.command(conn, args)

  defp wrap_result(%Redis.Error{} = err), do: {:error, err}
  defp wrap_result(result), do: {:ok, result}

  # -------------------------------------------------------------------
  # Split pipeline execution
  # -------------------------------------------------------------------

  defp execute_split_pipeline(state, commands) do
    groups = group_commands_by_slot(commands)
    default_conn = default_connection(state)
    tasks = dispatch_pipeline_groups(state, groups, default_conn)
    task_results = Task.await_many(tasks, state.timeout || 5_000)
    assemble_pipeline_results(task_results)
  end

  defp group_commands_by_slot(commands) do
    commands
    |> Enum.with_index()
    |> Enum.map(fn {cmd, idx} ->
      slot =
        case Router.slot_for_command(cmd) do
          {:ok, s} -> s
          {:error, :no_key} -> :no_key
        end

      {idx, slot, cmd}
    end)
    |> Enum.group_by(fn {_idx, slot, _cmd} -> slot end)
  end

  defp default_connection(state) do
    case any_connection(state) do
      {:ok, conn} -> conn
      _ -> nil
    end
  end

  defp dispatch_pipeline_groups(state, groups, default_conn) do
    Enum.map(groups, fn {slot, entries} ->
      conn = connection_for_group(state, slot, default_conn)
      indices = Enum.map(entries, fn {idx, _s, _c} -> idx end)
      cmds = Enum.map(entries, fn {_idx, _s, c} -> c end)

      Task.async(fn -> execute_pipeline_group(conn, cmds, indices) end)
    end)
  end

  defp connection_for_group(_state, :no_key, default_conn), do: default_conn

  defp connection_for_group(state, slot, _default_conn) do
    case get_connection_for_slot(state, slot) do
      {:ok, c} -> c
      _ -> nil
    end
  end

  defp execute_pipeline_group(nil, _cmds, indices), do: {:error, :no_connection, indices}

  defp execute_pipeline_group(conn, cmds, indices) do
    case Connection.pipeline(conn, cmds) do
      {:ok, results} -> {:ok, Enum.zip(indices, results)}
      {:error, reason} -> {:error, reason, indices}
    end
  end

  defp assemble_pipeline_results(task_results) do
    {pairs, errors} =
      Enum.reduce(task_results, {[], []}, fn
        {:ok, idx_results}, {pairs, errs} ->
          {idx_results ++ pairs, errs}

        {:error, reason, indices}, {pairs, errs} ->
          {pairs, [{reason, indices} | errs]}
      end)

    if errors != [] do
      [{reason, _} | _] = errors
      {:error, reason}
    else
      results =
        pairs
        |> Enum.sort_by(fn {idx, _val} -> idx end)
        |> Enum.map(fn {_idx, val} -> val end)

      {:ok, results}
    end
  end

  # -------------------------------------------------------------------
  # Connection management
  # -------------------------------------------------------------------

  defp connect_node(state, host, port) do
    opts =
      [host: host, port: port, timeout: state.timeout]
      |> maybe_put(:password, state.password)

    Connection.start_link(opts)
  end

  defp get_connection_for_slot(state, slot) do
    case :ets.lookup(state.slot_table, slot) do
      [{^slot, {host, port}}] ->
        case Map.get(state.connections, {host, port}) do
          nil -> {:error, :node_not_connected}
          conn -> {:ok, conn}
        end

      [] ->
        {:error, :slot_not_covered}
    end
  end

  defp any_connection(state) do
    case Map.values(state.connections) do
      [] -> {:error, :no_connections}
      conns -> {:ok, Enum.random(conns)}
    end
  end

  defp ensure_connection(state, host, port) do
    if Map.has_key?(state.connections, {host, port}) do
      state
    else
      case connect_node(state, host, port) do
        {:ok, conn} -> %{state | connections: Map.put(state.connections, {host, port}, conn)}
        {:error, _} -> state
      end
    end
  end

  # -------------------------------------------------------------------
  # Parsing helpers
  # -------------------------------------------------------------------

  defp parse_nodes(nodes) do
    Enum.map(nodes, fn
      {host, port} ->
        {host, port}

      str when is_binary(str) ->
        case String.split(str, ":") do
          [host, port_str] -> {host, String.to_integer(port_str)}
          [host] -> {host, 7000}
        end
    end)
  end

  defp parse_redirect(rest) do
    # Format: "<slot> <host>:<port>"
    [slot_str, addr] = String.split(rest, " ", parts: 2)
    slot = String.to_integer(slot_str)

    [host, port_str] = String.split(addr, ":")
    port = String.to_integer(port_str)

    {slot, host, port}
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end

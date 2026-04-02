defmodule Redis.PubSub.Sharded do
  @moduledoc """
  Sharded Pub/Sub client for Redis Cluster (Redis 7+).

  Uses `SSUBSCRIBE` / `SUNSUBSCRIBE` / `SPUBLISH` to route messages by hash
  slot. Unlike regular pub/sub which broadcasts to every node, sharded pub/sub
  only involves the node that owns the channel's hash slot.

  ## Usage

      {:ok, sharded} = Redis.PubSub.Sharded.start_link(
        nodes: [{"127.0.0.1", 7000}, {"127.0.0.1", 7001}, {"127.0.0.1", 7002}]
      )

      :ok = Redis.PubSub.Sharded.ssubscribe(sharded, "orders:123")

      receive do
        {:redis_pubsub, :smessage, channel, payload} ->
          IO.puts("sharded message on " <> channel <> ": " <> payload)
      end

      :ok = Redis.PubSub.Sharded.sunsubscribe(sharded, "orders:123")

  ## Options

    * `:nodes`    - list of seed nodes as `{host, port}` tuples or `"host:port"` strings
    * `:cluster`  - pid of an existing `Redis.Cluster` (used to discover topology)
    * `:password` - Redis password (applied to all nodes)
    * `:timeout`  - connection timeout ms (default: 5_000)
    * `:name`     - GenServer name registration

  ## Message Format

      {:redis_pubsub, :smessage, channel, payload}
  """

  use GenServer

  alias Redis.Cluster.{Router, Topology}
  alias Redis.Connection
  alias Redis.Protocol.RESP2

  require Logger

  defstruct [
    :password,
    :timeout,
    :cluster,
    seed_nodes: [],
    # slot -> {host, port}
    slot_map: %{},
    # {host, port} -> socket (raw TCP for pub/sub)
    node_sockets: %{},
    # {host, port} -> binary buffer
    node_buffers: %{},
    # socket_port -> {host, port}  (reverse lookup for tcp messages)
    socket_to_node: %{},
    # channel -> MapSet of subscriber pids
    channels: %{},
    # channel -> {host, port}  (which node we subscribed on)
    channel_node: %{},
    # pid -> monitor ref
    monitors: %{}
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

  @doc """
  Subscribe `subscriber` to a sharded channel.

  Messages arrive as `{:redis_pubsub, :smessage, channel, payload}`.
  """
  @spec ssubscribe(GenServer.server(), String.t(), pid()) :: :ok | {:error, term()}
  def ssubscribe(sharded, channel, subscriber \\ self()) do
    GenServer.call(sharded, {:ssubscribe, channel, subscriber})
  end

  @doc "Unsubscribe `subscriber` from a sharded channel."
  @spec sunsubscribe(GenServer.server(), String.t(), pid()) :: :ok | {:error, term()}
  def sunsubscribe(sharded, channel, subscriber \\ self()) do
    GenServer.call(sharded, {:sunsubscribe, channel, subscriber})
  end

  @doc "Returns current subscription state: channels with their subscriber counts."
  @spec subscriptions(GenServer.server()) :: map()
  def subscriptions(sharded) do
    GenServer.call(sharded, :subscriptions)
  end

  @doc "Stops the sharded pub/sub client."
  @spec stop(GenServer.server()) :: :ok
  def stop(sharded), do: GenServer.stop(sharded, :normal)

  # -------------------------------------------------------------------
  # GenServer callbacks
  # -------------------------------------------------------------------

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    password = Keyword.get(opts, :password)
    timeout = Keyword.get(opts, :timeout, 5_000)
    cluster = Keyword.get(opts, :cluster)

    seed_nodes =
      case Keyword.get(opts, :nodes) do
        nil -> []
        nodes -> parse_nodes(nodes)
      end

    state = %__MODULE__{
      seed_nodes: seed_nodes,
      cluster: cluster,
      password: password,
      timeout: timeout
    }

    case discover_slots(state) do
      {:ok, state} -> {:ok, state}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call({:ssubscribe, channel, subscriber}, _from, state) do
    slot = Router.slot(channel)

    with {:ok, node_addr} <- node_for_slot(state, slot),
         {:ok, state} <- ensure_pubsub_socket(state, node_addr) do
      state = track_subscription(state, channel, subscriber, node_addr)
      subs = Map.fetch!(state.channels, channel)
      reply = maybe_send_ssubscribe(state, channel, subs, node_addr)
      {:reply, reply, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:sunsubscribe, channel, subscriber}, _from, state) do
    case Map.get(state.channels, channel) do
      nil ->
        {:reply, :ok, state}

      subs ->
        new_subs = MapSet.delete(subs, subscriber)
        state = apply_unsubscribe(state, channel, new_subs, subscriber)
        {:reply, :ok, state}
    end
  end

  def handle_call(:subscriptions, _from, state) do
    info = %{
      channels: Map.new(state.channels, fn {ch, subs} -> {ch, MapSet.size(subs)} end)
    }

    {:reply, info, state}
  end

  @impl true
  def handle_info({:tcp, socket, data}, state) do
    port = :erlang.port_info(socket, :id) |> elem(1)

    case Map.get(state.socket_to_node, port) do
      nil ->
        {:noreply, state}

      node_addr ->
        buffer = Map.get(state.node_buffers, node_addr, <<>>)
        buffer = buffer <> data
        state = %{state | node_buffers: Map.put(state.node_buffers, node_addr, buffer)}
        state = process_messages(state, node_addr)
        {:noreply, state}
    end
  end

  def handle_info({:tcp_closed, socket}, state) do
    Logger.warning("Redis.PubSub.Sharded: connection closed")
    state = remove_socket(state, socket)
    {:noreply, state}
  end

  def handle_info({:tcp_error, socket, reason}, state) do
    Logger.warning("Redis.PubSub.Sharded: connection error: #{inspect(reason)}")
    state = remove_socket(state, socket)
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    state = remove_subscriber(state, pid, ref)
    {:noreply, state}
  end

  def handle_info({:EXIT, _pid, _reason}, state), do: {:noreply, state}
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.node_sockets, fn {_addr, socket} ->
      :gen_tcp.close(socket)
    end)

    :ok
  end

  # -------------------------------------------------------------------
  # Subscription tracking helpers
  # -------------------------------------------------------------------

  defp track_subscription(state, channel, subscriber, node_addr) do
    state = monitor_subscriber(state, subscriber)
    subs = Map.get(state.channels, channel, MapSet.new()) |> MapSet.put(subscriber)
    state = %{state | channels: Map.put(state.channels, channel, subs)}
    %{state | channel_node: Map.put(state.channel_node, channel, node_addr)}
  end

  defp maybe_send_ssubscribe(state, channel, subs, node_addr) do
    if MapSet.size(subs) == 1 do
      socket = Map.fetch!(state.node_sockets, node_addr)
      data = RESP2.encode(["SSUBSCRIBE", channel])

      case :gen_tcp.send(socket, data) do
        :ok -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end

  defp apply_unsubscribe(state, channel, new_subs, subscriber) do
    if MapSet.size(new_subs) == 0 do
      send_sunsubscribe(state, channel)

      state = %{
        state
        | channels: Map.delete(state.channels, channel),
          channel_node: Map.delete(state.channel_node, channel)
      }

      maybe_demonitor(state, subscriber)
    else
      state = %{state | channels: Map.put(state.channels, channel, new_subs)}
      maybe_demonitor(state, subscriber)
    end
  end

  defp send_sunsubscribe(state, channel) do
    node_addr = Map.get(state.channel_node, channel)

    if node_addr do
      case Map.get(state.node_sockets, node_addr) do
        nil -> :ok
        socket -> :gen_tcp.send(socket, RESP2.encode(["SUNSUBSCRIBE", channel]))
      end
    end
  end

  # -------------------------------------------------------------------
  # Topology discovery
  # -------------------------------------------------------------------

  defp discover_slots(state) do
    nodes = effective_seed_nodes(state)

    Enum.reduce_while(nodes, {:error, :no_reachable_node}, fn {host, port}, _acc ->
      case fetch_slots_from_node(state, host, port) do
        {:ok, slot_map} -> {:halt, {:ok, %{state | slot_map: slot_map}}}
        {:error, reason} -> {:cont, {:error, reason}}
      end
    end)
  end

  defp fetch_slots_from_node(state, host, port) do
    conn_opts =
      [host: host, port: port, timeout: state.timeout]
      |> maybe_put(:password, state.password)

    case Connection.start_link(conn_opts) do
      {:ok, conn} ->
        result = Connection.command(conn, ["CLUSTER", "SLOTS"])
        Connection.stop(conn)

        case result do
          {:ok, slots_data} -> {:ok, build_slot_lookup(Topology.parse_slots(slots_data))}
          {:error, reason} -> {:error, reason}
        end

      {:error, _reason} ->
        {:error, :no_reachable_node}
    end
  end

  defp effective_seed_nodes(%{cluster: pid} = _state) when is_pid(pid) do
    info = Redis.Cluster.info(pid)

    Enum.map(info.nodes, fn addr_str ->
      [host, port_str] = String.split(addr_str, ":")
      {host, String.to_integer(port_str)}
    end)
  end

  defp effective_seed_nodes(state), do: state.seed_nodes

  defp build_slot_lookup(parsed_slots) do
    Enum.reduce(parsed_slots, %{}, fn {start_slot, end_slot, host, port}, acc ->
      Enum.reduce(start_slot..end_slot, acc, fn slot, inner_acc ->
        Map.put(inner_acc, slot, {host, port})
      end)
    end)
  end

  defp node_for_slot(state, slot) do
    case Map.get(state.slot_map, slot) do
      nil -> {:error, :slot_not_covered}
      addr -> {:ok, addr}
    end
  end

  # -------------------------------------------------------------------
  # Per-node pub/sub socket management
  # -------------------------------------------------------------------

  defp ensure_pubsub_socket(state, node_addr) do
    if Map.has_key?(state.node_sockets, node_addr) do
      {:ok, state}
    else
      open_pubsub_socket(state, node_addr)
    end
  end

  defp open_pubsub_socket(state, {host, port} = node_addr) do
    tcp_opts = [:binary, active: false, packet: :raw, nodelay: true]
    charlist_host = String.to_charlist(host)

    with {:ok, socket} <- :gen_tcp.connect(charlist_host, port, tcp_opts, state.timeout),
         :ok <- maybe_auth_socket(socket, state) do
      :inet.setopts(socket, active: true)
      socket_port = :erlang.port_info(socket, :id) |> elem(1)

      state = %{
        state
        | node_sockets: Map.put(state.node_sockets, node_addr, socket),
          node_buffers: Map.put(state.node_buffers, node_addr, <<>>),
          socket_to_node: Map.put(state.socket_to_node, socket_port, node_addr)
      }

      {:ok, state}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_auth_socket(_socket, %{password: nil}), do: :ok

  defp maybe_auth_socket(socket, state) do
    data = RESP2.encode(["AUTH", state.password])
    :gen_tcp.send(socket, data)

    case :gen_tcp.recv(socket, 0, state.timeout) do
      {:ok, resp} ->
        case RESP2.decode(resp) do
          {:ok, "OK", _} -> :ok
          {:ok, %Redis.Error{message: msg}, _} -> {:error, {:auth_failed, msg}}
          _ -> {:error, :auth_failed}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp remove_socket(state, socket) do
    socket_port = :erlang.port_info(socket, :id) |> elem(1)

    case Map.get(state.socket_to_node, socket_port) do
      nil ->
        state

      node_addr ->
        :gen_tcp.close(socket)

        %{
          state
          | node_sockets: Map.delete(state.node_sockets, node_addr),
            node_buffers: Map.delete(state.node_buffers, node_addr),
            socket_to_node: Map.delete(state.socket_to_node, socket_port)
        }
    end
  end

  # -------------------------------------------------------------------
  # Message processing
  # -------------------------------------------------------------------

  defp process_messages(state, node_addr) do
    buffer = Map.get(state.node_buffers, node_addr, <<>>)

    case RESP2.decode(buffer) do
      {:ok, message, rest} ->
        state = %{state | node_buffers: Map.put(state.node_buffers, node_addr, rest)}
        state = handle_pubsub_message(message, state)
        process_messages(state, node_addr)

      {:continuation, _} ->
        state
    end
  end

  defp handle_pubsub_message(["smessage", channel, payload], state) do
    dispatch(state.channels, channel, {:redis_pubsub, :smessage, channel, payload})
    state
  end

  defp handle_pubsub_message(["ssubscribe", _channel, _count], state), do: state
  defp handle_pubsub_message(["sunsubscribe", _channel, _count], state), do: state
  defp handle_pubsub_message(_msg, state), do: state

  defp dispatch(registry, key, message) do
    case Map.get(registry, key) do
      nil -> :ok
      subscribers -> Enum.each(subscribers, &send(&1, message))
    end
  end

  # -------------------------------------------------------------------
  # Subscriber monitoring
  # -------------------------------------------------------------------

  defp monitor_subscriber(state, pid) do
    if Map.has_key?(state.monitors, pid) do
      state
    else
      ref = Process.monitor(pid)
      %{state | monitors: Map.put(state.monitors, pid, ref)}
    end
  end

  defp maybe_demonitor(state, pid) do
    in_channels = Enum.any?(state.channels, fn {_ch, subs} -> MapSet.member?(subs, pid) end)

    if in_channels do
      state
    else
      case Map.pop(state.monitors, pid) do
        {nil, _} ->
          state

        {ref, monitors} ->
          Process.demonitor(ref, [:flush])
          %{state | monitors: monitors}
      end
    end
  end

  defp remove_subscriber(state, pid, ref) do
    Process.demonitor(ref, [:flush])

    {channels, channels_to_unsub} = partition_channels_by_subscriber(state.channels, pid)

    Enum.each(channels_to_unsub, fn ch -> send_sunsubscribe(state, ch) end)

    channel_node =
      Enum.reduce(channels_to_unsub, state.channel_node, fn ch, acc ->
        Map.delete(acc, ch)
      end)

    %{
      state
      | channels: channels,
        channel_node: channel_node,
        monitors: Map.delete(state.monitors, pid)
    }
  end

  defp partition_channels_by_subscriber(channels, pid) do
    Enum.reduce(channels, {%{}, []}, fn {ch, subs}, {chs, unsub} ->
      new_subs = MapSet.delete(subs, pid)

      if MapSet.size(new_subs) == 0 do
        {chs, [ch | unsub]}
      else
        {Map.put(chs, ch, new_subs), unsub}
      end
    end)
  end

  # -------------------------------------------------------------------
  # Helpers
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

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end

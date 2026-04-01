defmodule Redis.PubSub do
  @moduledoc """
  Pub/Sub client for Redis.

  Manages a dedicated pub/sub connection and routes messages to subscribing
  Elixir processes as regular Erlang messages.

  ## Usage

      {:ok, ps} = Redis.PubSub.start_link(port: 6379)
      :ok = Redis.PubSub.subscribe(ps, "mychannel", self())

      receive do
        {:redis_pubsub, :message, channel, payload} ->
          IO.puts(channel <> ": " <> payload)
      end

      :ok = Redis.PubSub.unsubscribe(ps, "mychannel", self())

  ## Message Format

      {:redis_pubsub, :message, channel, payload}
      {:redis_pubsub, :pmessage, pattern, channel, payload}
      {:redis_pubsub, :subscribed, channel_or_pattern, count}
      {:redis_pubsub, :unsubscribed, channel_or_pattern, count}

  ## Options

    * `:host` - Redis host (default: "127.0.0.1")
    * `:port` - Redis port (default: 6379)
    * `:password` - authentication password
    * `:username` - authentication username
    * `:name` - GenServer name registration
    * `:timeout` - connection timeout ms (default: 5_000)
  """

  use GenServer

  alias Redis.Protocol.RESP2

  require Logger

  defstruct [
    :host,
    :port,
    :password,
    :username,
    :socket,
    :timeout,
    state: :disconnected,
    buffer: <<>>,
    # channel -> MapSet of subscriber pids
    channels: %{},
    # pattern -> MapSet of subscriber pids
    patterns: %{},
    # pid -> monitor ref (for auto-unsubscribe on process death)
    monitors: %{},
    # Reconnect backoff
    backoff_initial: 500,
    backoff_max: 30_000,
    backoff_current: 500
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

  @doc "Subscribe `subscriber` to `channel`. Messages arrive as `{:redis_pubsub, :message, channel, payload}`."
  @spec subscribe(GenServer.server(), String.t() | [String.t()], pid()) :: :ok | {:error, term()}
  def subscribe(pubsub, channels, subscriber \\ self())

  def subscribe(pubsub, channel, subscriber) when is_binary(channel) do
    subscribe(pubsub, [channel], subscriber)
  end

  def subscribe(pubsub, channels, subscriber) when is_list(channels) do
    GenServer.call(pubsub, {:subscribe, channels, subscriber})
  end

  @doc "Unsubscribe `subscriber` from `channel`."
  @spec unsubscribe(GenServer.server(), String.t() | [String.t()], pid()) :: :ok | {:error, term()}
  def unsubscribe(pubsub, channels, subscriber \\ self())

  def unsubscribe(pubsub, channel, subscriber) when is_binary(channel) do
    unsubscribe(pubsub, [channel], subscriber)
  end

  def unsubscribe(pubsub, channels, subscriber) when is_list(channels) do
    GenServer.call(pubsub, {:unsubscribe, channels, subscriber})
  end

  @doc "Subscribe `subscriber` to a pattern. Messages arrive as `{:redis_pubsub, :pmessage, pattern, channel, payload}`."
  @spec psubscribe(GenServer.server(), String.t() | [String.t()], pid()) :: :ok | {:error, term()}
  def psubscribe(pubsub, patterns, subscriber \\ self())

  def psubscribe(pubsub, pattern, subscriber) when is_binary(pattern) do
    psubscribe(pubsub, [pattern], subscriber)
  end

  def psubscribe(pubsub, patterns, subscriber) when is_list(patterns) do
    GenServer.call(pubsub, {:psubscribe, patterns, subscriber})
  end

  @doc "Unsubscribe `subscriber` from a pattern."
  @spec punsubscribe(GenServer.server(), String.t() | [String.t()], pid()) :: :ok | {:error, term()}
  def punsubscribe(pubsub, patterns, subscriber \\ self())

  def punsubscribe(pubsub, pattern, subscriber) when is_binary(pattern) do
    punsubscribe(pubsub, [pattern], subscriber)
  end

  def punsubscribe(pubsub, patterns, subscriber) when is_list(patterns) do
    GenServer.call(pubsub, {:punsubscribe, patterns, subscriber})
  end

  @doc "Returns current subscription state: channels and patterns with their subscriber counts."
  @spec subscriptions(GenServer.server()) :: map()
  def subscriptions(pubsub) do
    GenServer.call(pubsub, :subscriptions)
  end

  @doc "Stops the pub/sub connection."
  @spec stop(GenServer.server()) :: :ok
  def stop(pubsub), do: GenServer.stop(pubsub, :normal)

  # -------------------------------------------------------------------
  # GenServer callbacks
  # -------------------------------------------------------------------

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    state = %__MODULE__{
      host: Keyword.get(opts, :host, "127.0.0.1"),
      port: Keyword.get(opts, :port, 6379),
      password: Keyword.get(opts, :password),
      username: Keyword.get(opts, :username),
      timeout: Keyword.get(opts, :timeout, 5_000)
    }

    case connect(state) do
      {:ok, state} -> {:ok, state}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call({:subscribe, channels, subscriber}, _from, %{state: :ready} = state) do
    # Monitor the subscriber so we can auto-unsubscribe on death
    state = monitor_subscriber(state, subscriber)

    # Track locally
    state =
      Enum.reduce(channels, state, fn ch, s ->
        subs = Map.get(s.channels, ch, MapSet.new()) |> MapSet.put(subscriber)
        %{s | channels: Map.put(s.channels, ch, subs)}
      end)

    # Send SUBSCRIBE to Redis
    data = RESP2.encode(["SUBSCRIBE" | channels])
    case :gen_tcp.send(state.socket, data) do
      :ok -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:unsubscribe, channels, subscriber}, _from, %{state: :ready} = state) do
    # Remove subscriber from local tracking
    {state, channels_to_unsub} =
      Enum.reduce(channels, {state, []}, fn ch, {s, unsub} ->
        case Map.get(s.channels, ch) do
          nil ->
            {s, unsub}

          subs ->
            new_subs = MapSet.delete(subs, subscriber)

            if MapSet.size(new_subs) == 0 do
              {%{s | channels: Map.delete(s.channels, ch)}, [ch | unsub]}
            else
              {%{s | channels: Map.put(s.channels, ch, new_subs)}, unsub}
            end
        end
      end)

    state = maybe_demonitor(state, subscriber)

    # Only send UNSUBSCRIBE if no subscribers left for the channel
    if channels_to_unsub != [] do
      data = RESP2.encode(["UNSUBSCRIBE" | channels_to_unsub])
      :gen_tcp.send(state.socket, data)
    end

    {:reply, :ok, state}
  end

  def handle_call({:psubscribe, patterns, subscriber}, _from, %{state: :ready} = state) do
    state = monitor_subscriber(state, subscriber)

    state =
      Enum.reduce(patterns, state, fn pat, s ->
        subs = Map.get(s.patterns, pat, MapSet.new()) |> MapSet.put(subscriber)
        %{s | patterns: Map.put(s.patterns, pat, subs)}
      end)

    data = RESP2.encode(["PSUBSCRIBE" | patterns])
    case :gen_tcp.send(state.socket, data) do
      :ok -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:punsubscribe, patterns, subscriber}, _from, %{state: :ready} = state) do
    {state, patterns_to_unsub} =
      Enum.reduce(patterns, {state, []}, fn pat, {s, unsub} ->
        case Map.get(s.patterns, pat) do
          nil ->
            {s, unsub}

          subs ->
            new_subs = MapSet.delete(subs, subscriber)

            if MapSet.size(new_subs) == 0 do
              {%{s | patterns: Map.delete(s.patterns, pat)}, [pat | unsub]}
            else
              {%{s | patterns: Map.put(s.patterns, pat, new_subs)}, unsub}
            end
        end
      end)

    state = maybe_demonitor(state, subscriber)

    if patterns_to_unsub != [] do
      data = RESP2.encode(["PUNSUBSCRIBE" | patterns_to_unsub])
      :gen_tcp.send(state.socket, data)
    end

    {:reply, :ok, state}
  end

  def handle_call(:subscriptions, _from, state) do
    info = %{
      channels: Map.new(state.channels, fn {ch, subs} -> {ch, MapSet.size(subs)} end),
      patterns: Map.new(state.patterns, fn {pat, subs} -> {pat, MapSet.size(subs)} end)
    }

    {:reply, info, state}
  end

  def handle_call(_msg, _from, state) do
    {:reply, {:error, :not_connected}, state}
  end

  @impl true
  def handle_info({:tcp, _socket, data}, state) do
    state = %{state | buffer: state.buffer <> data}
    process_messages(state)
  end

  def handle_info({:tcp_closed, _socket}, state) do
    Logger.warning("Redis.PubSub: connection closed")
    {:noreply, schedule_reconnect(%{state | socket: nil, state: :disconnected, buffer: <<>>})}
  end

  def handle_info({:tcp_error, _socket, reason}, state) do
    Logger.warning("Redis.PubSub: connection error: #{inspect(reason)}")
    {:noreply, schedule_reconnect(%{state | socket: nil, state: :disconnected, buffer: <<>>})}
  end

  def handle_info(:connect, state) do
    case connect(state) do
      {:ok, state} ->
        # Re-subscribe to everything
        state = resubscribe(state)
        {:noreply, state}

      {:error, reason} ->
        Logger.warning("Redis.PubSub: reconnect failed: #{inspect(reason)}")
        {:noreply, schedule_reconnect(state)}
    end
  end

  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    # Subscriber died — remove from all channels and patterns
    state = remove_subscriber(state, pid, ref)
    {:noreply, state}
  end

  def handle_info({:EXIT, _port, _reason}, state), do: {:noreply, state}
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{socket: nil}), do: :ok

  def terminate(_reason, %{socket: socket}) do
    :gen_tcp.close(socket)
  end

  # -------------------------------------------------------------------
  # Connection
  # -------------------------------------------------------------------

  defp connect(state) do
    host = String.to_charlist(state.host)
    tcp_opts = [:binary, active: false, packet: :raw, nodelay: true]

    with {:ok, socket} <- :gen_tcp.connect(host, state.port, tcp_opts, state.timeout),
         state = %{state | socket: socket},
         :ok <- maybe_auth(state),
         :ok <- :inet.setopts(socket, active: true) do
      Logger.debug("Redis.PubSub: connected to #{state.host}:#{state.port}")
      {:ok, %{state | state: :ready, buffer: <<>>, backoff_current: state.backoff_initial}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_auth(%{password: nil}), do: :ok

  defp maybe_auth(state) do
    args =
      case state.username do
        nil -> ["AUTH", state.password]
        user -> ["AUTH", user, state.password]
      end

    :gen_tcp.send(state.socket, RESP2.encode(args))

    case :gen_tcp.recv(state.socket, 0, state.timeout) do
      {:ok, data} ->
        case RESP2.decode(data) do
          {:ok, "OK", _} -> :ok
          {:ok, %Redis.Error{message: msg}, _} -> {:error, {:auth_failed, msg}}
          _ -> {:error, :auth_failed}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # -------------------------------------------------------------------
  # Message processing
  # -------------------------------------------------------------------

  # Pub/sub uses RESP2 push format (arrays), even on RESP3 connections.
  # We use RESP2 decoder exclusively here.

  defp process_messages(state) do
    case RESP2.decode(state.buffer) do
      {:ok, message, rest} ->
        state = %{state | buffer: rest}
        state = handle_pubsub_message(message, state)
        process_messages(state)

      {:continuation, _} ->
        {:noreply, state}
    end
  end

  defp handle_pubsub_message(["message", channel, payload], state) do
    dispatch(state.channels, channel, {:redis_pubsub, :message, channel, payload})
    state
  end

  defp handle_pubsub_message(["pmessage", pattern, channel, payload], state) do
    dispatch(state.patterns, pattern, {:redis_pubsub, :pmessage, pattern, channel, payload})
    state
  end

  defp handle_pubsub_message(["subscribe", channel, count], state) do
    dispatch(state.channels, channel, {:redis_pubsub, :subscribed, channel, count})
    state
  end

  defp handle_pubsub_message(["unsubscribe", channel, count], state) do
    dispatch(state.channels, channel, {:redis_pubsub, :unsubscribed, channel, count})
    state
  end

  defp handle_pubsub_message(["psubscribe", pattern, count], state) do
    dispatch(state.patterns, pattern, {:redis_pubsub, :subscribed, pattern, count})
    state
  end

  defp handle_pubsub_message(["punsubscribe", pattern, count], state) do
    dispatch(state.patterns, pattern, {:redis_pubsub, :unsubscribed, pattern, count})
    state
  end

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
    # Only demonitor if pid is not subscribed to anything
    in_channels = Enum.any?(state.channels, fn {_ch, subs} -> MapSet.member?(subs, pid) end)
    in_patterns = Enum.any?(state.patterns, fn {_pat, subs} -> MapSet.member?(subs, pid) end)

    if not in_channels and not in_patterns do
      case Map.pop(state.monitors, pid) do
        {nil, _} -> state
        {ref, monitors} ->
          Process.demonitor(ref, [:flush])
          %{state | monitors: monitors}
      end
    else
      state
    end
  end

  defp remove_subscriber(state, pid, ref) do
    Process.demonitor(ref, [:flush])

    # Remove from all channels
    {channels, channels_to_unsub} =
      Enum.reduce(state.channels, {%{}, []}, fn {ch, subs}, {chs, unsub} ->
        new_subs = MapSet.delete(subs, pid)

        if MapSet.size(new_subs) == 0 do
          {chs, [ch | unsub]}
        else
          {Map.put(chs, ch, new_subs), unsub}
        end
      end)

    # Remove from all patterns
    {patterns, patterns_to_unsub} =
      Enum.reduce(state.patterns, {%{}, []}, fn {pat, subs}, {pats, unsub} ->
        new_subs = MapSet.delete(subs, pid)

        if MapSet.size(new_subs) == 0 do
          {pats, [pat | unsub]}
        else
          {Map.put(pats, pat, new_subs), unsub}
        end
      end)

    # Unsubscribe from Redis for empty channels/patterns
    if channels_to_unsub != [] and state.socket do
      :gen_tcp.send(state.socket, RESP2.encode(["UNSUBSCRIBE" | channels_to_unsub]))
    end

    if patterns_to_unsub != [] and state.socket do
      :gen_tcp.send(state.socket, RESP2.encode(["PUNSUBSCRIBE" | patterns_to_unsub]))
    end

    %{state | channels: channels, patterns: patterns, monitors: Map.delete(state.monitors, pid)}
  end

  # -------------------------------------------------------------------
  # Reconnection
  # -------------------------------------------------------------------

  defp schedule_reconnect(state) do
    Process.send_after(self(), :connect, state.backoff_current)
    %{state | backoff_current: min(state.backoff_current * 2, state.backoff_max)}
  end

  defp resubscribe(state) do
    channels = Map.keys(state.channels)
    patterns = Map.keys(state.patterns)

    if channels != [] do
      :gen_tcp.send(state.socket, RESP2.encode(["SUBSCRIBE" | channels]))
    end

    if patterns != [] do
      :gen_tcp.send(state.socket, RESP2.encode(["PSUBSCRIBE" | patterns]))
    end

    state
  end
end

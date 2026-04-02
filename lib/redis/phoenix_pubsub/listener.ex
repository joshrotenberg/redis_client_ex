defmodule Redis.PhoenixPubSub.Listener do
  @moduledoc false

  # GenServer that subscribes to the Redis Pub/Sub channel and delivers
  # messages to the local Phoenix.PubSub registry.

  use GenServer

  require Logger

  defstruct [
    :adapter_name,
    :pubsub_name,
    :node_name,
    :channel,
    :redis_opts,
    :pubsub_conn
  ]

  def start_link({adapter_name, pubsub_name, node_name, channel, redis_opts}) do
    GenServer.start_link(__MODULE__, {adapter_name, pubsub_name, node_name, channel, redis_opts},
      name: :"#{adapter_name}.Listener"
    )
  end

  @impl true
  def init({adapter_name, pubsub_name, node_name, channel, redis_opts}) do
    state = %__MODULE__{
      adapter_name: adapter_name,
      pubsub_name: pubsub_name,
      node_name: node_name,
      channel: channel,
      redis_opts: redis_opts
    }

    case connect(state) do
      {:ok, state} -> {:ok, state}
      {:error, _reason} -> {:ok, schedule_reconnect(state)}
    end
  end

  @impl true
  def handle_info({:redis_pubsub, :message, _channel, payload}, state) do
    case safe_deserialize(payload) do
      {:except, from_node, topic, message, dispatcher} ->
        if from_node != state.node_name do
          Phoenix.PubSub.local_broadcast(state.pubsub_name, topic, message, dispatcher)
        end

      {:only, target_node, topic, message, dispatcher} ->
        if target_node == state.node_name do
          Phoenix.PubSub.local_broadcast(state.pubsub_name, topic, message, dispatcher)
        end

      _ ->
        Logger.warning("Redis.PhoenixPubSub: unexpected message format, ignoring")
    end

    {:noreply, state}
  end

  def handle_info({:redis_pubsub, :subscribed, _channel, _count}, state) do
    {:noreply, state}
  end

  def handle_info({:redis_pubsub, :unsubscribed, _channel, _count}, state) do
    {:noreply, state}
  end

  def handle_info(:reconnect, state) do
    case connect(state) do
      {:ok, state} -> {:noreply, state}
      {:error, _reason} -> {:noreply, schedule_reconnect(state)}
    end
  end

  def handle_info({:EXIT, pid, reason}, %{pubsub_conn: pid} = state) do
    Logger.warning("Redis.PhoenixPubSub: subscriber connection lost: #{inspect(reason)}")
    {:noreply, schedule_reconnect(%{state | pubsub_conn: nil})}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # -------------------------------------------------------------------
  # Private
  # -------------------------------------------------------------------

  defp connect(state) do
    case Redis.PubSub.start_link(state.redis_opts) do
      {:ok, conn} ->
        Process.link(conn)
        :ok = Redis.PubSub.subscribe(conn, state.channel, self())
        {:ok, %{state | pubsub_conn: conn}}

      {:error, reason} ->
        Logger.warning("Redis.PhoenixPubSub: failed to connect: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp schedule_reconnect(state) do
    Process.send_after(self(), :reconnect, 5_000)
    state
  end

  defp safe_deserialize(bin) do
    :erlang.binary_to_term(bin)
  rescue
    ArgumentError -> :invalid
  end
end

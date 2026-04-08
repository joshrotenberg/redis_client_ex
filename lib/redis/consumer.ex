defmodule Redis.Consumer do
  @moduledoc """
  A GenServer for consuming Redis Streams via consumer groups.

  Wraps `XREADGROUP` in a polling loop with automatic acknowledgement,
  pending message recovery via `XAUTOCLAIM`, and consumer group creation.
  The consumer group and stream are created automatically on startup if
  they don't already exist.

  ## Defining a Handler

  Implement the `Redis.Consumer.Handler` behaviour to process messages:

      defmodule MyApp.OrderHandler do
        @behaviour Redis.Consumer.Handler

        @impl true
        def handle_messages(messages, metadata) do
          for [stream, entries] <- messages, [id, fields] <- entries do
            # fields is a flat list: ["field1", "value1", "field2", "value2", ...]
            order = fields_to_map(fields)
            process_order(order)
            Logger.info("Processed order \#{id} from \#{stream}")
          end

          :ok
        end

        defp fields_to_map(fields) do
          fields
          |> Enum.chunk_every(2)
          |> Map.new(fn [k, v] -> {k, v} end)
        end

        defp process_order(order), do: # ...
      end

  ## Return Values

  The handler can control acknowledgement:

    * `:ok` - all messages are acknowledged automatically
    * `{:ok, ids}` - only the specified message IDs are acknowledged
    * `{:error, reason}` - no messages are acknowledged; they will be
      redelivered to this or another consumer via XAUTOCLAIM

  ## Starting a Consumer

      {:ok, consumer} = Redis.Consumer.start_link(
        conn: conn,
        stream: "orders",
        group: "processors",
        consumer: "proc-1",
        handler: MyApp.OrderHandler
      )

  ## Supervision

  Add consumers to your supervision tree alongside the connection:

      children = [
        {Redis.Connection, port: 6379, name: :redis},
        {Redis.Consumer,
         conn: :redis,
         stream: "orders",
         group: "processors",
         consumer: "proc-1",
         handler: MyApp.OrderHandler,
         name: :order_consumer}
      ]

  Scale out by adding more consumers with different `:consumer` names.
  Redis distributes unacknowledged messages across consumers in the group.

  ## Producing Messages

  Any connection can write to the stream:

      Redis.command(conn, ["XADD", "orders", "*",
        "user_id", "123",
        "item", "widget",
        "qty", "5"
      ])

  Or use the command builder:

      alias Redis.Commands.Stream
      Redis.command(conn, Stream.xadd("orders", "*", [
        {"user_id", "123"},
        {"item", "widget"},
        {"qty", "5"}
      ]))

  ## Options

    * `:conn` (required) - Redis connection (pid or registered name)
    * `:stream` (required) - stream key to consume from
    * `:group` (required) - consumer group name
    * `:consumer` (required) - consumer name within the group
    * `:handler` (required) - module implementing `Redis.Consumer.Handler`
    * `:count` - max entries per XREADGROUP call (default: 10)
    * `:block` - block timeout in ms waiting for new messages (default: 5000)
    * `:claim_interval` - ms between XAUTOCLAIM runs (default: 30_000)
    * `:claim_min_idle` - min idle time in ms for XAUTOCLAIM (default: 60_000)
    * `:name` - GenServer name registration

  ## Message Recovery

  On startup and periodically (every `:claim_interval` ms), the consumer
  runs `XAUTOCLAIM` to reclaim messages that were delivered to other consumers
  in the group but not acknowledged within `:claim_min_idle` ms. This handles
  consumer crashes and restarts gracefully -- if a consumer dies mid-processing,
  another consumer (or the restarted one) will pick up its pending messages.
  """

  use GenServer

  alias Redis.Commands.Stream
  alias Redis.Connection

  require Logger

  defstruct [
    :conn,
    :stream,
    :group,
    :consumer,
    :handler,
    count: 10,
    block: 5_000,
    claim_interval: 30_000,
    claim_min_idle: 60_000
  ]

  # -------------------------------------------------------------------
  # Public API
  # -------------------------------------------------------------------

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    if name do
      GenServer.start_link(__MODULE__, opts, name: name)
    else
      GenServer.start_link(__MODULE__, opts)
    end
  end

  @doc "Returns consumer info: stream, group, consumer name, handler."
  @spec info(GenServer.server()) :: map()
  def info(consumer), do: GenServer.call(consumer, :info)

  @doc "Stops the consumer gracefully."
  @spec stop(GenServer.server()) :: :ok
  def stop(consumer), do: GenServer.stop(consumer, :normal)

  # -------------------------------------------------------------------
  # GenServer callbacks
  # -------------------------------------------------------------------

  @impl true
  def init(opts) do
    state = %__MODULE__{
      conn: Keyword.fetch!(opts, :conn),
      stream: Keyword.fetch!(opts, :stream),
      group: Keyword.fetch!(opts, :group),
      consumer: Keyword.fetch!(opts, :consumer),
      handler: Keyword.fetch!(opts, :handler),
      count: Keyword.get(opts, :count, 10),
      block: Keyword.get(opts, :block, 5_000),
      claim_interval: Keyword.get(opts, :claim_interval, 30_000),
      claim_min_idle: Keyword.get(opts, :claim_min_idle, 60_000)
    }

    ensure_group(state)
    schedule_claim(state)
    send(self(), :poll)

    {:ok, state}
  end

  @impl true
  def handle_info(:poll, state) do
    case read_messages(state) do
      {:ok, messages} when messages != nil and messages != %{} and messages != [] ->
        process_messages(state, normalize_messages(messages))

      _ ->
        :ok
    end

    send(self(), :poll)
    {:noreply, state}
  end

  def handle_info(:claim, state) do
    claim_pending(state)
    schedule_claim(state)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call(:info, _from, state) do
    info = %{
      stream: state.stream,
      group: state.group,
      consumer: state.consumer,
      handler: state.handler
    }

    {:reply, info, state}
  end

  # -------------------------------------------------------------------
  # Private
  # -------------------------------------------------------------------

  defp ensure_group(state) do
    cmd = Stream.xgroup_create(state.stream, state.group, "0", mkstream: true)

    case Connection.command(state.conn, cmd) do
      {:ok, "OK"} ->
        Logger.debug("Redis.Consumer: created group #{state.group} on #{state.stream}")

      {:error, %Redis.Error{message: "BUSYGROUP" <> _}} ->
        # Group already exists, that's fine
        :ok

      {:error, reason} ->
        Logger.warning("Redis.Consumer: failed to create group: #{inspect(reason)}")
    end
  end

  defp read_messages(state) do
    cmd =
      Stream.xreadgroup(state.group, state.consumer,
        streams: [{state.stream, ">"}],
        count: state.count,
        block: state.block
      )

    Connection.command(state.conn, cmd, timeout: state.block + 5_000)
  end

  defp process_messages(state, messages) do
    ids = extract_ids(messages)

    case state.handler.handle_messages(messages, %{stream: state.stream, group: state.group}) do
      :ok ->
        ack_messages(state, ids)

      {:ok, ack_ids} when is_list(ack_ids) ->
        ack_messages(state, ack_ids)

      {:error, reason} ->
        Logger.warning(
          "Redis.Consumer: handler error for #{length(ids)} messages: #{inspect(reason)}"
        )
    end
  rescue
    e ->
      Logger.error(
        "Redis.Consumer: handler crashed: #{Exception.format(:error, e, __STACKTRACE__)}"
      )
  end

  defp ack_messages(_state, []), do: :ok

  defp ack_messages(state, ids) do
    cmd = Stream.xack(state.stream, state.group, ids)

    case Connection.command(state.conn, cmd) do
      {:ok, _count} -> :ok
      {:error, reason} -> Logger.warning("Redis.Consumer: XACK failed: #{inspect(reason)}")
    end
  end

  defp claim_pending(state) do
    cmd =
      Stream.xautoclaim(
        state.stream,
        state.group,
        state.consumer,
        state.claim_min_idle,
        "0-0",
        count: state.count
      )

    case Connection.command(state.conn, cmd) do
      {:ok, [_cursor, messages | _]} when messages != [] ->
        Logger.debug("Redis.Consumer: claimed #{length(messages)} pending messages")
        ids = Enum.map(messages, fn [id | _] -> id end)
        process_claimed(state, messages, ids)

      _ ->
        :ok
    end
  end

  defp process_claimed(state, messages, ids) do
    # Wrap claimed messages in the same format as XREADGROUP
    wrapped = [[state.stream, messages]]

    case state.handler.handle_messages(wrapped, %{
           stream: state.stream,
           group: state.group,
           claimed: true
         }) do
      :ok -> ack_messages(state, ids)
      {:ok, ack_ids} when is_list(ack_ids) -> ack_messages(state, ack_ids)
      {:error, _} -> :ok
    end
  rescue
    _ -> :ok
  end

  # RESP3 returns a map %{"stream" => entries}, RESP2 returns [["stream", entries]].
  # Normalize to [[stream, entries]] for consistent handling.
  defp normalize_messages(messages) when is_map(messages) do
    Enum.map(messages, fn {stream, entries} -> [stream, entries] end)
  end

  defp normalize_messages(messages) when is_list(messages), do: messages

  defp extract_ids(messages) do
    for [_stream, entries] <- messages,
        [id | _] <- entries,
        do: id
  end

  defp schedule_claim(state) do
    Process.send_after(self(), :claim, state.claim_interval)
  end
end

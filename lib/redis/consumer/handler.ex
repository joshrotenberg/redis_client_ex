defmodule Redis.Consumer.Handler do
  @moduledoc """
  Behaviour for handling messages from a Redis Streams consumer group.

  ## Example

      defmodule MyApp.NotificationHandler do
        @behaviour Redis.Consumer.Handler
        require Logger

        @impl true
        def handle_messages(messages, metadata) do
          for [stream, entries] <- messages, [id, fields] <- entries do
            fields_map = fields |> Enum.chunk_every(2) |> Map.new(fn [k, v] -> {k, v} end)

            case send_notification(fields_map) do
              :ok -> Logger.info("Sent notification \#{id}")
              {:error, reason} -> Logger.error("Failed \#{id}: \#{inspect(reason)}")
            end
          end

          :ok
        end

        defp send_notification(fields), do: # ...
      end

  ## Selective Acknowledgement

  Return `{:ok, ids}` to acknowledge only specific messages. Unacknowledged
  messages remain pending and will be redelivered via XAUTOCLAIM:

      def handle_messages(messages, _metadata) do
        {succeeded, _failed} =
          messages
          |> Enum.flat_map(fn [_stream, entries] -> entries end)
          |> Enum.split_with(fn [_id, fields] -> process(fields) == :ok end)

        {:ok, Enum.map(succeeded, fn [id, _] -> id end)}
      end

  ## Return Values

    * `:ok` - all messages processed successfully, acknowledge all
    * `{:ok, ids}` - selectively acknowledge only the given message IDs
    * `{:error, reason}` - processing failed, messages will NOT be acknowledged
      and will be redelivered on the next XAUTOCLAIM cycle

  ## Metadata

  The `metadata` map contains:

    * `:stream` - the stream key
    * `:group` - the consumer group name
    * `:claimed` - `true` when messages were recovered via XAUTOCLAIM
      (absent for normal deliveries)
  """

  @type message_id :: String.t()
  @type field :: String.t()
  @type entry :: {message_id(), [field()]}
  @type stream_messages :: {String.t(), [entry()]}
  @type metadata :: map()

  @doc """
  Called when messages are received from the stream.

  `messages` is a list of `{stream_key, entries}` tuples where each entry
  is `{message_id, [field1, value1, field2, value2, ...]}`.

  `metadata` contains `:stream`, `:group`, and optionally `:claimed` (true
  when messages were recovered via XAUTOCLAIM).
  """
  @callback handle_messages([stream_messages()], metadata()) ::
              :ok | {:ok, [message_id()]} | {:error, term()}
end

defmodule Redis.Consumer.Handler do
  @moduledoc """
  Behaviour for handling messages from a Redis Streams consumer group.

  ## Example

      defmodule MyApp.EventHandler do
        @behaviour Redis.Consumer.Handler

        @impl true
        def handle_messages(messages, metadata) do
          for {stream, entries} <- messages, {id, fields} <- entries do
            IO.puts("[\#{stream}] \#{id}: \#{inspect(fields)}")
          end

          :ok
        end
      end

  ## Return Values

    * `:ok` - all messages processed successfully, acknowledge all
    * `{:ok, ids}` - selectively acknowledge only the given message IDs
    * `{:error, reason}` - processing failed, messages will NOT be acknowledged
      and will be redelivered on the next XAUTOCLAIM cycle
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

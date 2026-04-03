defmodule Redis.ConsumerTest do
  use ExUnit.Case, async: false

  alias Redis.Connection
  alias Redis.Consumer

  # Uses redis-server on port 6398 from test_helper.exs

  defmodule TestHandler do
    @behaviour Redis.Consumer.Handler

    @impl true
    def handle_messages(messages, metadata) do
      # Send messages to the test process stored in the process dictionary
      test_pid = :persistent_term.get(:consumer_test_pid)

      for [stream, entries] <- messages, [id | fields] <- entries do
        send(test_pid, {:consumed, stream, id, fields, metadata})
      end

      :ok
    end
  end

  defmodule ErrorHandler do
    @behaviour Redis.Consumer.Handler

    @impl true
    def handle_messages(_messages, _metadata) do
      {:error, :simulated_failure}
    end
  end

  defmodule SelectiveAckHandler do
    @behaviour Redis.Consumer.Handler

    @impl true
    def handle_messages(messages, _metadata) do
      # Only ack messages with "important" field
      ids =
        for [_stream, entries] <- messages,
            [id | fields] <- entries,
            "important" in fields,
            do: id

      {:ok, ids}
    end
  end

  setup do
    {:ok, conn} = Connection.start_link(port: 6398)
    :persistent_term.put(:consumer_test_pid, self())

    stream = "test:stream:#{:erlang.unique_integer([:positive])}"
    group = "test_group"

    on_exit(fn ->
      :persistent_term.erase(:consumer_test_pid)

      case Connection.start_link(port: 6398) do
        {:ok, cleanup} ->
          Connection.command(cleanup, ["DEL", stream])
          Connection.stop(cleanup)

        _ ->
          :ok
      end
    end)

    {:ok, conn: conn, stream: stream, group: group}
  end

  describe "consumer lifecycle" do
    test "starts, creates group, and consumes messages", %{
      conn: conn,
      stream: stream,
      group: group
    } do
      # Add some messages before starting the consumer
      Connection.command(conn, ["XADD", stream, "*", "event", "click", "url", "/home"])
      Connection.command(conn, ["XADD", stream, "*", "event", "view", "url", "/about"])

      {:ok, consumer} =
        Consumer.start_link(
          conn: conn,
          stream: stream,
          group: group,
          consumer: "worker-1",
          handler: TestHandler,
          block: 100,
          count: 10
        )

      # Wait for the consumer to process messages
      assert_receive {:consumed, ^stream, _id1, fields1, _meta}, 2000
      assert List.flatten(fields1) == ["event", "click", "url", "/home"]
      assert_receive {:consumed, ^stream, _id2, fields2, _meta}, 2000
      assert List.flatten(fields2) == ["event", "view", "url", "/about"]

      Consumer.stop(consumer)
    end

    test "consumes messages added after startup", %{conn: conn, stream: stream, group: group} do
      {:ok, consumer} =
        Consumer.start_link(
          conn: conn,
          stream: stream,
          group: group,
          consumer: "worker-1",
          handler: TestHandler,
          block: 100
        )

      # Small delay to let consumer start polling
      Process.sleep(200)

      # Add message after consumer is running
      Connection.command(conn, ["XADD", stream, "*", "type", "new_event"])

      assert_receive {:consumed, ^stream, _id, fields, _meta}, 2000
      assert List.flatten(fields) == ["type", "new_event"]

      Consumer.stop(consumer)
    end

    test "info returns consumer metadata", %{conn: conn, stream: stream, group: group} do
      {:ok, consumer} =
        Consumer.start_link(
          conn: conn,
          stream: stream,
          group: group,
          consumer: "worker-1",
          handler: TestHandler,
          block: 100
        )

      info = Consumer.info(consumer)
      assert info.stream == stream
      assert info.group == group
      assert info.consumer == "worker-1"
      assert info.handler == TestHandler

      Consumer.stop(consumer)
    end
  end

  describe "acknowledgement" do
    test "messages are acknowledged after successful processing", %{
      conn: conn,
      stream: stream,
      group: group
    } do
      Connection.command(conn, ["XADD", stream, "*", "data", "value"])

      {:ok, consumer} =
        Consumer.start_link(
          conn: conn,
          stream: stream,
          group: group,
          consumer: "worker-1",
          handler: TestHandler,
          block: 100
        )

      assert_receive {:consumed, _, _, _, _}, 2000
      Process.sleep(100)

      # Check that there are no pending messages
      {:ok, pending} = Connection.command(conn, ["XPENDING", stream, group, "-", "+", "10"])
      assert pending == [] or pending == nil

      Consumer.stop(consumer)
    end

    test "selective ack only acknowledges returned ids", %{
      conn: conn,
      stream: stream,
      group: group
    } do
      Connection.command(conn, ["XADD", stream, "*", "data", "normal"])
      Connection.command(conn, ["XADD", stream, "*", "important", "true", "data", "critical"])

      {:ok, consumer} =
        Consumer.start_link(
          conn: conn,
          stream: stream,
          group: group,
          consumer: "worker-1",
          handler: SelectiveAckHandler,
          block: 100
        )

      Process.sleep(500)

      # The "normal" message should still be pending (not acked)
      {:ok, pending} = Connection.command(conn, ["XPENDING", stream, group, "-", "+", "10"])
      # At least one message should be pending (the non-important one)
      assert [_ | _] = pending

      Consumer.stop(consumer)
    end
  end

  describe "error handling" do
    test "handler errors don't crash the consumer", %{conn: conn, stream: stream, group: group} do
      Connection.command(conn, ["XADD", stream, "*", "data", "will_fail"])

      {:ok, consumer} =
        Consumer.start_link(
          conn: conn,
          stream: stream,
          group: group,
          consumer: "worker-1",
          handler: ErrorHandler,
          block: 100
        )

      # Consumer should still be alive after handler returns error
      Process.sleep(500)
      assert Process.alive?(consumer)

      Consumer.stop(consumer)
    end
  end

  describe "group creation" do
    test "creates group with MKSTREAM if stream doesn't exist", %{
      conn: conn,
      stream: stream,
      group: group
    } do
      # Stream doesn't exist yet -- consumer should create it
      {:ok, consumer} =
        Consumer.start_link(
          conn: conn,
          stream: stream,
          group: group,
          consumer: "worker-1",
          handler: TestHandler,
          block: 100
        )

      # Verify the stream and group exist
      {:ok, groups} = Connection.command(conn, ["XINFO", "GROUPS", stream])
      assert is_list(groups)

      Consumer.stop(consumer)
    end

    test "handles already existing group gracefully", %{conn: conn, stream: stream, group: group} do
      # Pre-create the group
      Connection.command(conn, ["XGROUP", "CREATE", stream, group, "0", "MKSTREAM"])

      # Consumer should start without error
      {:ok, consumer} =
        Consumer.start_link(
          conn: conn,
          stream: stream,
          group: group,
          consumer: "worker-1",
          handler: TestHandler,
          block: 100
        )

      assert Process.alive?(consumer)
      Consumer.stop(consumer)
    end
  end
end

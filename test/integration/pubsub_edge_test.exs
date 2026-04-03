defmodule Redis.PubSubEdgeTest do
  use ExUnit.Case, async: false

  alias Redis.Connection
  alias Redis.PubSub

  # Uses redis-server on port 6398 (no auth) from test_helper.exs

  describe "pattern subscribe receives pmessage" do
    test "psubscribe with multiple patterns receives pmessage from each matching channel" do
      {:ok, ps} = PubSub.start_link(port: 6398)
      :ok = PubSub.psubscribe(ps, ["user:*", "order:*"], self())

      assert_receive {:redis_pubsub, :subscribed, "user:*", _}, 1000
      assert_receive {:redis_pubsub, :subscribed, "order:*", _}, 1000

      {:ok, conn} = Connection.start_link(port: 6398)
      Connection.command(conn, ["PUBLISH", "user:42:login", "session_abc"])
      Connection.command(conn, ["PUBLISH", "order:99:created", "item_xyz"])
      Connection.command(conn, ["PUBLISH", "other:channel", "ignored"])

      assert_receive {:redis_pubsub, :pmessage, "user:*", "user:42:login", "session_abc"}, 1000
      assert_receive {:redis_pubsub, :pmessage, "order:*", "order:99:created", "item_xyz"}, 1000
      refute_receive {:redis_pubsub, :pmessage, _, "other:channel", _}, 300

      PubSub.stop(ps)
      Connection.stop(conn)
    end
  end

  describe "subscriber process death auto-cleans subscription" do
    test "killing a subscribed process removes its subscription and stops message delivery" do
      {:ok, ps} = PubSub.start_link(port: 6398)
      channel = "death:cleanup:#{:erlang.unique_integer([:positive])}"

      # Also subscribe self so we can verify publish works
      :ok = PubSub.subscribe(ps, channel, self())
      assert_receive {:redis_pubsub, :subscribed, ^channel, _}, 1000

      # Spawn a short-lived subscriber
      victim =
        spawn(fn ->
          receive do
            :die -> :ok
          end
        end)

      :ok = PubSub.subscribe(ps, channel, victim)
      Process.sleep(100)

      # Both subscribers should be tracked
      subs = PubSub.subscriptions(ps)
      assert subs.channels[channel] == 2

      # Kill the victim
      send(victim, :die)
      Process.sleep(200)

      # Only self() should remain
      subs = PubSub.subscriptions(ps)
      assert subs.channels[channel] == 1

      # Publish a message -- only self() should receive it, no crash from dead pid
      {:ok, conn} = Connection.start_link(port: 6398)
      Connection.command(conn, ["PUBLISH", channel, "after_death"])

      assert_receive {:redis_pubsub, :message, ^channel, "after_death"}, 1000

      PubSub.stop(ps)
      Connection.stop(conn)
    end
  end

  describe "multiple subscribers on the same channel" do
    test "all subscribers receive every published message" do
      {:ok, ps} = PubSub.start_link(port: 6398)
      channel = "multi:sub:#{:erlang.unique_integer([:positive])}"

      # Spawn two additional subscriber processes
      parent = self()

      sub1 =
        spawn(fn ->
          receive do
            {:redis_pubsub, :message, _ch, payload} -> send(parent, {:sub1, payload})
          end

          # Keep alive long enough for cleanup
          Process.sleep(1000)
        end)

      sub2 =
        spawn(fn ->
          receive do
            {:redis_pubsub, :message, _ch, payload} -> send(parent, {:sub2, payload})
          end

          Process.sleep(1000)
        end)

      :ok = PubSub.subscribe(ps, channel, self())
      :ok = PubSub.subscribe(ps, channel, sub1)
      :ok = PubSub.subscribe(ps, channel, sub2)

      assert_receive {:redis_pubsub, :subscribed, ^channel, _}, 1000

      subs = PubSub.subscriptions(ps)
      assert subs.channels[channel] == 3

      {:ok, conn} = Connection.start_link(port: 6398)
      Connection.command(conn, ["PUBLISH", channel, "broadcast"])

      assert_receive {:redis_pubsub, :message, ^channel, "broadcast"}, 1000
      assert_receive {:sub1, "broadcast"}, 1000
      assert_receive {:sub2, "broadcast"}, 1000

      PubSub.stop(ps)
      Connection.stop(conn)
    end
  end

  describe "unsubscribe from never-subscribed channel" do
    test "unsubscribing from a channel that was never subscribed does not error" do
      {:ok, ps} = PubSub.start_link(port: 6398)

      # This should return :ok without raising
      assert :ok = PubSub.unsubscribe(ps, "never:subscribed:channel", self())

      # Also test pattern variant
      assert :ok = PubSub.punsubscribe(ps, "never:subscribed:*", self())

      # PubSub should still be fully functional after
      :ok = PubSub.subscribe(ps, "after:noop:unsub", self())
      assert_receive {:redis_pubsub, :subscribed, "after:noop:unsub", _}, 1000

      PubSub.stop(ps)
    end
  end
end

defmodule Redis.ConsumerEdgeTest do
  use ExUnit.Case, async: false

  alias Redis.Connection
  alias Redis.Consumer

  # Uses redis-server on port 6398 from test_helper.exs

  defmodule CollectorHandler do
    @behaviour Redis.Consumer.Handler

    @impl true
    def handle_messages(messages, metadata) do
      test_pid = :persistent_term.get(:edge_consumer_test_pid)

      for [stream, entries] <- messages, [id | fields] <- entries do
        send(test_pid, {:consumed, stream, id, fields, metadata})
      end

      :ok
    end
  end

  defmodule SelectiveAckHandler do
    @behaviour Redis.Consumer.Handler

    @impl true
    def handle_messages(messages, _metadata) do
      test_pid = :persistent_term.get(:edge_consumer_test_pid)
      send(test_pid, :selective_handler_called)

      # Only ack messages whose first field key is "ack"
      ids =
        for [_stream, entries] <- messages,
            [id | fields] <- entries,
            hd(List.flatten(fields)) == "ack",
            do: id

      {:ok, ids}
    end
  end

  defmodule CrashingHandler do
    @behaviour Redis.Consumer.Handler

    @impl true
    def handle_messages(_messages, _metadata) do
      test_pid = :persistent_term.get(:edge_consumer_test_pid)
      send(test_pid, :crash_handler_called)
      raise "intentional handler crash"
    end
  end

  setup do
    {:ok, conn} = Connection.start_link(port: 6398)
    :persistent_term.put(:edge_consumer_test_pid, self())

    stream = "edge:stream:#{:erlang.unique_integer([:positive])}"
    group = "edge_group"

    on_exit(fn ->
      :persistent_term.erase(:edge_consumer_test_pid)

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

  describe "XAUTOCLAIM recovery" do
    test "second consumer claims messages left unacked by first consumer", %{
      conn: conn,
      stream: stream,
      group: group
    } do
      # Create group and add messages
      Connection.command(conn, ["XGROUP", "CREATE", stream, group, "0", "MKSTREAM"])

      {:ok, id1} = Connection.command(conn, ["XADD", stream, "*", "data", "msg1"])
      {:ok, id2} = Connection.command(conn, ["XADD", stream, "*", "data", "msg2"])

      # Read messages as consumer "stale-worker" but do NOT ack them
      Connection.command(conn, [
        "XREADGROUP",
        "GROUP",
        group,
        "stale-worker",
        "COUNT",
        "10",
        "STREAMS",
        stream,
        ">"
      ])

      # Verify messages are pending under stale-worker
      {:ok, pending} = Connection.command(conn, ["XPENDING", stream, group, "-", "+", "10"])
      assert length(pending) == 2

      # Start a second consumer with a very short claim interval and min idle
      {:ok, claimer} =
        Consumer.start_link(
          conn: conn,
          stream: stream,
          group: group,
          consumer: "claimer-worker",
          handler: CollectorHandler,
          block: 100,
          claim_interval: 200,
          claim_min_idle: 0
        )

      # The claimer should pick up the pending messages via XAUTOCLAIM
      assert_receive {:consumed, ^stream, ^id1, _, %{claimed: true}}, 5000
      assert_receive {:consumed, ^stream, ^id2, _, %{claimed: true}}, 5000

      # After processing, messages should be acknowledged
      Process.sleep(200)

      {:ok, pending_after} =
        Connection.command(conn, ["XPENDING", stream, group, "-", "+", "10"])

      assert pending_after == [] or pending_after == nil

      Consumer.stop(claimer)
    end
  end

  describe "selective ack via {:ok, ids}" do
    test "handler returning {:ok, ids} acks only those ids, rest stay pending", %{
      conn: conn,
      stream: stream,
      group: group
    } do
      # Add two messages: one to ack, one to skip
      Connection.command(conn, ["XADD", stream, "*", "ack", "yes"])
      Connection.command(conn, ["XADD", stream, "*", "skip", "yes"])

      {:ok, consumer} =
        Consumer.start_link(
          conn: conn,
          stream: stream,
          group: group,
          consumer: "selective-worker",
          handler: SelectiveAckHandler,
          block: 100,
          claim_interval: 600_000
        )

      assert_receive :selective_handler_called, 2000
      Process.sleep(300)

      # Check pending: the "skip" message should still be pending
      {:ok, pending} = Connection.command(conn, ["XPENDING", stream, group, "-", "+", "10"])
      assert length(pending) == 1

      # The pending message should be the "skip" one
      [entry] = pending
      pending_id = hd(entry)

      # Verify the pending message is the non-acked one by reading it
      {:ok, messages} = Connection.command(conn, ["XRANGE", stream, pending_id, pending_id])
      [[^pending_id, fields]] = messages
      assert "skip" in fields

      Consumer.stop(consumer)
    end
  end

  describe "handler crash does not kill consumer" do
    test "consumer stays alive after handler raises an exception", %{
      conn: conn,
      stream: stream,
      group: group
    } do
      Connection.command(conn, ["XADD", stream, "*", "data", "will_crash"])

      {:ok, consumer} =
        Consumer.start_link(
          conn: conn,
          stream: stream,
          group: group,
          consumer: "crash-worker",
          handler: CrashingHandler,
          block: 100,
          claim_interval: 600_000
        )

      # Wait for the handler to be called (it will crash)
      assert_receive :crash_handler_called, 2000

      # Give it a moment to recover
      Process.sleep(300)

      # Consumer process should still be alive
      assert Process.alive?(consumer)

      # Consumer should still be functional: verify it keeps polling
      # by adding another message that also triggers the crash handler
      Connection.command(conn, ["XADD", stream, "*", "data", "second_crash"])
      assert_receive :crash_handler_called, 2000

      assert Process.alive?(consumer)

      Consumer.stop(consumer)
    end
  end
end

defmodule Redis.PubSubTest do
  use ExUnit.Case, async: false

  alias Redis.Connection
  alias Redis.PubSub

  # Uses redis-server on port 6398 (no auth) from test_helper.exs

  describe "subscribe and receive" do
    test "receives messages on subscribed channel" do
      {:ok, ps} = PubSub.start_link(port: 6398)
      :ok = PubSub.subscribe(ps, "test:chan", self())

      # Wait for subscription confirmation
      assert_receive {:redis_pubsub, :subscribed, "test:chan", _count}, 1000

      # Publish from a separate connection
      {:ok, conn} = Connection.start_link(port: 6398)
      {:ok, _} = Connection.command(conn, ["PUBLISH", "test:chan", "hello"])

      assert_receive {:redis_pubsub, :message, "test:chan", "hello"}, 1000

      PubSub.stop(ps)
      Connection.stop(conn)
    end

    test "receives messages on multiple channels" do
      {:ok, ps} = PubSub.start_link(port: 6398)
      :ok = PubSub.subscribe(ps, ["chan:a", "chan:b"], self())

      assert_receive {:redis_pubsub, :subscribed, "chan:a", _}, 1000
      assert_receive {:redis_pubsub, :subscribed, "chan:b", _}, 1000

      {:ok, conn} = Connection.start_link(port: 6398)
      Connection.command(conn, ["PUBLISH", "chan:a", "msg1"])
      Connection.command(conn, ["PUBLISH", "chan:b", "msg2"])

      assert_receive {:redis_pubsub, :message, "chan:a", "msg1"}, 1000
      assert_receive {:redis_pubsub, :message, "chan:b", "msg2"}, 1000

      PubSub.stop(ps)
      Connection.stop(conn)
    end
  end

  describe "pattern subscribe" do
    test "receives messages matching pattern" do
      {:ok, ps} = PubSub.start_link(port: 6398)
      :ok = PubSub.psubscribe(ps, "events:*", self())

      assert_receive {:redis_pubsub, :subscribed, "events:*", _}, 1000

      {:ok, conn} = Connection.start_link(port: 6398)
      Connection.command(conn, ["PUBLISH", "events:login", "user1"])
      Connection.command(conn, ["PUBLISH", "events:logout", "user2"])

      assert_receive {:redis_pubsub, :pmessage, "events:*", "events:login", "user1"}, 1000
      assert_receive {:redis_pubsub, :pmessage, "events:*", "events:logout", "user2"}, 1000

      PubSub.stop(ps)
      Connection.stop(conn)
    end
  end

  describe "unsubscribe" do
    test "stops receiving after unsubscribe" do
      {:ok, ps} = PubSub.start_link(port: 6398)
      :ok = PubSub.subscribe(ps, "unsub:test", self())
      assert_receive {:redis_pubsub, :subscribed, "unsub:test", _}, 1000

      :ok = PubSub.unsubscribe(ps, "unsub:test", self())

      # Small delay to let unsubscribe propagate
      Process.sleep(100)

      {:ok, conn} = Connection.start_link(port: 6398)
      Connection.command(conn, ["PUBLISH", "unsub:test", "should_not_arrive"])

      refute_receive {:redis_pubsub, :message, "unsub:test", _}, 500

      PubSub.stop(ps)
      Connection.stop(conn)
    end
  end

  describe "subscriber monitoring" do
    test "auto-unsubscribes when subscriber process dies" do
      {:ok, ps} = PubSub.start_link(port: 6398)

      # Spawn a subscriber that will die
      subscriber =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      :ok = PubSub.subscribe(ps, "monitor:test", subscriber)
      Process.sleep(100)

      # Verify subscription exists
      subs = PubSub.subscriptions(ps)
      assert subs.channels["monitor:test"] == 1

      # Kill the subscriber
      send(subscriber, :stop)
      Process.sleep(200)

      # Subscription should be cleaned up
      subs = PubSub.subscriptions(ps)
      assert subs.channels["monitor:test"] == nil

      PubSub.stop(ps)
    end
  end

  describe "subscriptions" do
    test "returns current subscription state" do
      {:ok, ps} = PubSub.start_link(port: 6398)
      :ok = PubSub.subscribe(ps, "info:a", self())
      :ok = PubSub.psubscribe(ps, "info:*", self())
      Process.sleep(100)

      subs = PubSub.subscriptions(ps)
      assert subs.channels["info:a"] == 1
      assert subs.patterns["info:*"] == 1

      PubSub.stop(ps)
    end
  end
end

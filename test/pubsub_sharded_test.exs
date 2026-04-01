defmodule RedisEx.PubSub.ShardedTest do
  use ExUnit.Case, async: false

  alias RedisEx.PubSub.Sharded
  alias RedisEx.Connection

  @moduletag timeout: 60_000

  # --- Cluster setup ---

  setup_all do
    {:ok, cluster_srv} =
      RedisServerWrapper.Cluster.start_link(
        masters: 3,
        base_port: 7400
      )

    assert RedisServerWrapper.Cluster.healthy?(cluster_srv)

    on_exit(fn ->
      try do
        RedisServerWrapper.Cluster.stop(cluster_srv)
      catch
        :exit, _ -> :ok
      end

      Process.sleep(1000)
    end)

    {:ok, cluster_srv: cluster_srv}
  end

  defp nodes_opt, do: [{"127.0.0.1", 7400}, {"127.0.0.1", 7401}, {"127.0.0.1", 7402}]

  describe "ssubscribe and receive" do
    test "receives sharded messages on subscribed channel" do
      {:ok, sharded} = Sharded.start_link(nodes: nodes_opt())

      :ok = Sharded.ssubscribe(sharded, "sharded:chan1", self())

      # Give Redis a moment to register the subscription
      Process.sleep(200)

      # Publish via SPUBLISH from a regular connection to any cluster node
      spublish(7400, "sharded:chan1", "hello_sharded")

      assert_receive {:redis_pubsub, :smessage, "sharded:chan1", "hello_sharded"}, 3000

      Sharded.stop(sharded)
    end

    test "receives messages on multiple channels hashing to different nodes" do
      {:ok, sharded} = Sharded.start_link(nodes: nodes_opt())

      # These keys will likely hash to different slots/nodes
      :ok = Sharded.ssubscribe(sharded, "chan:alpha", self())
      :ok = Sharded.ssubscribe(sharded, "chan:beta", self())

      Process.sleep(200)

      spublish(7400, "chan:alpha", "msg_alpha")
      spublish(7400, "chan:beta", "msg_beta")

      assert_receive {:redis_pubsub, :smessage, "chan:alpha", "msg_alpha"}, 3000
      assert_receive {:redis_pubsub, :smessage, "chan:beta", "msg_beta"}, 3000

      Sharded.stop(sharded)
    end
  end

  describe "sunsubscribe" do
    test "stops receiving after sunsubscribe" do
      {:ok, sharded} = Sharded.start_link(nodes: nodes_opt())

      :ok = Sharded.ssubscribe(sharded, "unsub:sharded", self())
      Process.sleep(200)

      :ok = Sharded.sunsubscribe(sharded, "unsub:sharded", self())
      Process.sleep(200)

      spublish(7400, "unsub:sharded", "should_not_arrive")

      refute_receive {:redis_pubsub, :smessage, "unsub:sharded", _}, 1000

      Sharded.stop(sharded)
    end
  end

  describe "subscriptions" do
    test "returns current subscription state" do
      {:ok, sharded} = Sharded.start_link(nodes: nodes_opt())

      :ok = Sharded.ssubscribe(sharded, "info:x", self())
      :ok = Sharded.ssubscribe(sharded, "info:y", self())
      Process.sleep(100)

      subs = Sharded.subscriptions(sharded)
      assert subs.channels["info:x"] == 1
      assert subs.channels["info:y"] == 1

      Sharded.stop(sharded)
    end
  end

  describe "subscriber monitoring" do
    test "auto-unsubscribes when subscriber process dies" do
      {:ok, sharded} = Sharded.start_link(nodes: nodes_opt())

      subscriber =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      :ok = Sharded.ssubscribe(sharded, "monitor:sharded", subscriber)
      Process.sleep(100)

      subs = Sharded.subscriptions(sharded)
      assert subs.channels["monitor:sharded"] == 1

      # Kill the subscriber
      send(subscriber, :stop)
      Process.sleep(300)

      subs = Sharded.subscriptions(sharded)
      assert subs.channels["monitor:sharded"] == nil

      Sharded.stop(sharded)
    end
  end

  describe "multiple subscribers" do
    test "multiple subscribers on same channel both receive" do
      {:ok, sharded} = Sharded.start_link(nodes: nodes_opt())

      parent = self()

      sub1 = spawn(fn -> relay_loop(parent, :sub1) end)
      sub2 = spawn(fn -> relay_loop(parent, :sub2) end)

      :ok = Sharded.ssubscribe(sharded, "multi:chan", sub1)
      :ok = Sharded.ssubscribe(sharded, "multi:chan", sub2)
      Process.sleep(200)

      spublish(7400, "multi:chan", "for_both")

      assert_receive {:relayed, :sub1, {:redis_pubsub, :smessage, "multi:chan", "for_both"}}, 3000
      assert_receive {:relayed, :sub2, {:redis_pubsub, :smessage, "multi:chan", "for_both"}}, 3000

      Process.exit(sub1, :kill)
      Process.exit(sub2, :kill)
      Sharded.stop(sharded)
    end
  end

  describe "node reuse" do
    test "channels hashing to the same node reuse the same socket" do
      {:ok, sharded} = Sharded.start_link(nodes: nodes_opt())

      # Use hash tags to ensure same slot
      :ok = Sharded.ssubscribe(sharded, "{same}.a", self())
      :ok = Sharded.ssubscribe(sharded, "{same}.b", self())
      Process.sleep(200)

      # Both should use the same node socket
      subs = Sharded.subscriptions(sharded)
      assert subs.channels["{same}.a"] == 1
      assert subs.channels["{same}.b"] == 1

      Sharded.stop(sharded)
    end
  end

  # -------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------

  # Publish a sharded message by connecting to one of the cluster nodes.
  # SPUBLISH can be sent from any node; the cluster will route internally.
  defp spublish(port, channel, message) do
    # Try each node in case the first one doesn't know about the slot
    ports = [port, port + 1, port + 2]

    Enum.find_value(ports, {:error, :publish_failed}, fn p ->
      case Connection.start_link(host: "127.0.0.1", port: p) do
        {:ok, conn} ->
          result = Connection.command(conn, ["SPUBLISH", channel, message])
          Connection.stop(conn)

          case result do
            {:ok, _count} -> true
            _ -> nil
          end

        _ ->
          nil
      end
    end)
  end

  defp relay_loop(parent, tag) do
    receive do
      msg ->
        send(parent, {:relayed, tag, msg})
        relay_loop(parent, tag)
    end
  end
end

defmodule Redis.PhoenixPubSubTest do
  use ExUnit.Case, async: false

  # Uses redis-server on port 6398 from test_helper.exs

  @pubsub_name :"test_pubsub_#{:erlang.unique_integer([:positive])}"

  setup_all do
    # Start Phoenix.PubSub with our Redis adapter
    {:ok, _} =
      Supervisor.start_link(
        [
          {Phoenix.PubSub,
           name: @pubsub_name,
           adapter: Redis.PhoenixPubSub,
           redis_opts: [port: 6398],
           node_name: :test_node}
        ],
        strategy: :one_for_one
      )

    # Give the listener time to connect and subscribe
    Process.sleep(200)

    :ok
  end

  describe "Phoenix.PubSub integration" do
    test "subscribe and broadcast delivers messages" do
      :ok = Phoenix.PubSub.subscribe(@pubsub_name, "events")

      :ok = Phoenix.PubSub.broadcast(@pubsub_name, "events", {:hello, "world"})

      # Local broadcasts are delivered synchronously by Phoenix.PubSub
      assert_receive {:hello, "world"}, 1000
    end

    test "broadcast to unsubscribed topic is not received" do
      :ok = Phoenix.PubSub.subscribe(@pubsub_name, "topic:a")

      :ok = Phoenix.PubSub.broadcast(@pubsub_name, "topic:b", :nope)

      refute_receive :nope, 200
    end

    test "multiple subscribers receive the same message" do
      parent = self()

      pids =
        for i <- 1..3 do
          spawn(fn ->
            :ok = Phoenix.PubSub.subscribe(@pubsub_name, "multi")
            send(parent, {:subscribed, i})

            receive do
              msg -> send(parent, {:got, i, msg})
            end
          end)
        end

      # Wait for all to subscribe
      for i <- 1..3, do: assert_receive({:subscribed, ^i}, 1000)

      :ok = Phoenix.PubSub.broadcast(@pubsub_name, "multi", :ping)

      for i <- 1..3, do: assert_receive({:got, ^i, :ping}, 1000)

      for pid <- pids, do: Process.exit(pid, :normal)
    end

    test "unsubscribe stops delivery" do
      :ok = Phoenix.PubSub.subscribe(@pubsub_name, "unsub_test")
      :ok = Phoenix.PubSub.unsubscribe(@pubsub_name, "unsub_test")

      :ok = Phoenix.PubSub.broadcast(@pubsub_name, "unsub_test", :gone)

      refute_receive :gone, 200
    end

    test "broadcast_from excludes the sender" do
      :ok = Phoenix.PubSub.subscribe(@pubsub_name, "from_test")

      :ok = Phoenix.PubSub.broadcast_from(@pubsub_name, self(), "from_test", :excluded)

      refute_receive :excluded, 200
    end

    test "local_broadcast delivers without going through Redis" do
      :ok = Phoenix.PubSub.subscribe(@pubsub_name, "local_test")

      :ok = Phoenix.PubSub.local_broadcast(@pubsub_name, "local_test", :local_msg)

      assert_receive :local_msg, 1000
    end

    test "complex messages are preserved" do
      :ok = Phoenix.PubSub.subscribe(@pubsub_name, "complex")

      msg = %{users: [%{name: "Alice", age: 30}], timestamp: ~U[2026-01-01 00:00:00Z]}
      :ok = Phoenix.PubSub.broadcast(@pubsub_name, "complex", msg)

      assert_receive ^msg, 1000
    end
  end

  describe "adapter callbacks" do
    test "node_name returns configured name" do
      # Phoenix.PubSub generates adapter_name as Module.concat(name, "Adapter")
      adapter_name = Module.concat(@pubsub_name, "Adapter")
      assert Redis.PhoenixPubSub.node_name(adapter_name) == :test_node
    end
  end
end

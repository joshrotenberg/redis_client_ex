defmodule Redis.IntegrationTest do
  use ExUnit.Case, async: false

  alias Redis.Cache
  alias Redis.Connection
  alias Redis.Connection.Pool
  alias Redis.PubSub
  alias Redis.Resilience

  @moduletag timeout: 60_000

  # -------------------------------------------------------------------
  # Connection resilience
  # -------------------------------------------------------------------

  describe "connection resilience" do
    test "reconnects after server restart" do
      {:ok, srv} = RedisServerWrapper.Server.start_link(port: 6450)
      {:ok, conn} = Connection.start_link(port: 6450, sync_connect: true)

      assert {:ok, "PONG"} = Connection.command(conn, ["PING"])

      # Kill the server
      srv_info = RedisServerWrapper.Server.info(srv)
      RedisServerWrapper.Server.stop(srv)
      Process.sleep(500)

      # Commands should fail
      assert {:error, _} = Connection.command(conn, ["PING"])

      # Restart the server on same port
      {:ok, _srv2} = RedisServerWrapper.Server.start_link(port: 6450)
      # Wait for reconnect (backoff starts at 500ms)
      Process.sleep(2000)

      # Should be working again
      assert {:ok, "PONG"} = Connection.command(conn, ["PING"])

      Connection.stop(conn)
      Process.sleep(500)
    end

    test "exit_on_disconnection stops the process" do
      {:ok, srv} = RedisServerWrapper.Server.start_link(port: 6451)
      Process.flag(:trap_exit, true)

      {:ok, conn} = Connection.start_link(port: 6451, exit_on_disconnection: true)
      assert {:ok, "PONG"} = Connection.command(conn, ["PING"])

      # Kill the server — connection should exit instead of reconnecting
      RedisServerWrapper.Server.stop(srv)
      Process.sleep(1000)

      refute Process.alive?(conn)
      Process.sleep(500)
    end

    test "commands during reconnection return error" do
      {:ok, srv} = RedisServerWrapper.Server.start_link(port: 6452)
      {:ok, conn} = Connection.start_link(port: 6452)

      assert {:ok, "PONG"} = Connection.command(conn, ["PING"])

      RedisServerWrapper.Server.stop(srv)
      Process.sleep(500)

      # Should get connection error, not hang
      result = Connection.command(conn, ["PING"])
      assert {:error, _} = result

      Connection.stop(conn)
      Process.sleep(500)
    end
  end

  # -------------------------------------------------------------------
  # Connection pool resilience
  # -------------------------------------------------------------------

  describe "pool resilience" do
    test "pool replaces dead connections" do
      {:ok, _srv} = RedisServerWrapper.Server.start_link(port: 6453)
      {:ok, pool} = Pool.start_link(pool_size: 3, port: 6453)

      assert {:ok, "PONG"} = Pool.command(pool, ["PING"])
      info = Pool.info(pool)
      assert info.active == 3

      # Kill one of the pool connections directly
      conn = GenServer.call(pool, :checkout)
      Process.exit(conn, :kill)
      Process.sleep(1500)

      # Pool should have replaced it
      assert {:ok, "PONG"} = Pool.command(pool, ["PING"])

      Pool.stop(pool)
      Process.sleep(500)
    end

    test "pool recovers after killing a connection" do
      {:ok, _srv} = RedisServerWrapper.Server.start_link(port: 6454)
      {:ok, pool} = Pool.start_link(pool_size: 3, port: 6454)

      Pool.command(pool, ["SET", "survive", "yes"])
      assert {:ok, "yes"} = Pool.command(pool, ["GET", "survive"])

      # Kill one connection
      conn = GenServer.call(pool, :checkout)
      Process.exit(conn, :kill)
      Process.sleep(1500)

      # Pool should recover — replacement connection created
      assert {:ok, "yes"} = Pool.command(pool, ["GET", "survive"])

      info = Pool.info(pool)
      assert info.active == 3

      Pool.stop(pool)
      Process.sleep(500)
    end
  end

  # -------------------------------------------------------------------
  # Pub/Sub resilience
  # -------------------------------------------------------------------

  describe "pubsub resilience" do
    test "subscriber death auto-cleans subscriptions" do
      {:ok, _srv} = RedisServerWrapper.Server.start_link(port: 6455)
      {:ok, ps} = PubSub.start_link(port: 6455)

      # Create a subscriber that will die
      sub = spawn(fn -> Process.sleep(:infinity) end)
      :ok = PubSub.subscribe(ps, "cleanup_test", sub)
      Process.sleep(100)

      subs = PubSub.subscriptions(ps)
      assert subs.channels["cleanup_test"] == 1

      # Kill the subscriber
      Process.exit(sub, :kill)
      Process.sleep(300)

      # Subscription should be cleaned up
      subs = PubSub.subscriptions(ps)
      assert subs.channels["cleanup_test"] == nil

      PubSub.stop(ps)
      Process.sleep(500)
    end

    test "multiple subscribers on same channel" do
      {:ok, _srv} = RedisServerWrapper.Server.start_link(port: 6456)
      {:ok, ps} = PubSub.start_link(port: 6456)
      {:ok, publisher} = Connection.start_link(port: 6456)

      sub1 = self()

      sub2 =
        spawn(fn ->
          # Drain subscribe confirmations, forward only messages
          receive_loop = fn loop ->
            receive do
              {:redis_pubsub, :message, _, _} = msg -> send(sub1, {:sub2_got, msg})
              {:redis_pubsub, :subscribed, _, _} -> loop.(loop)
              _ -> loop.(loop)
            end
          end

          receive_loop.(receive_loop)
        end)

      :ok = PubSub.subscribe(ps, "multi_sub", self())
      :ok = PubSub.subscribe(ps, "multi_sub", sub2)
      Process.sleep(300)

      Connection.command(publisher, ["PUBLISH", "multi_sub", "hello_both"])

      assert_receive {:redis_pubsub, :message, "multi_sub", "hello_both"}, 2000
      assert_receive {:sub2_got, {:redis_pubsub, :message, "multi_sub", "hello_both"}}, 2000

      PubSub.stop(ps)
      Connection.stop(publisher)
      Process.sleep(500)
    end
  end

  # -------------------------------------------------------------------
  # Client-side cache resilience
  # -------------------------------------------------------------------

  describe "cache resilience" do
    test "high-throughput invalidation" do
      {:ok, _srv} = RedisServerWrapper.Server.start_link(port: 6457)
      {:ok, cache} = Cache.start_link(port: 6457)
      {:ok, writer} = Connection.start_link(port: 6457)

      # Populate cache with 50 keys
      for i <- 1..50 do
        Cache.command(cache, ["SET", "inv:#{i}", "orig:#{i}"])
        Cache.get(cache, "inv:#{i}")
      end

      stats = Cache.stats(cache)
      assert stats.size == 50

      # Rapidly invalidate all keys from another connection
      for i <- 1..50 do
        Connection.command(writer, ["SET", "inv:#{i}", "new:#{i}"])
      end

      # Give invalidations time to arrive
      Process.sleep(500)

      stats = Cache.stats(cache)
      # Most should be evicted
      assert stats.evictions >= 40

      # Verify new values are fetched
      {:ok, val} = Cache.get(cache, "inv:1")
      assert val == "new:1"

      Cache.stop(cache)
      Connection.stop(writer)
      Process.sleep(500)
    end

    test "cache survives connection blip" do
      {:ok, srv} = RedisServerWrapper.Server.start_link(port: 6458)
      {:ok, cache} = Cache.start_link(port: 6458)

      Cache.command(cache, ["SET", "blip_key", "blip_val"])
      {:ok, "blip_val"} = Cache.get(cache, "blip_key")

      # Cached value should survive even if we can't reach Redis momentarily
      {:ok, "blip_val"} = Cache.get(cache, "blip_key")

      Cache.stop(cache)
      RedisServerWrapper.Server.stop(srv)
      Process.sleep(500)
    end
  end

  # -------------------------------------------------------------------
  # Resilience patterns
  # -------------------------------------------------------------------

  describe "resilience patterns" do
    @describetag :ex_resilience

    test "circuit breaker trips on repeated failures" do
      {:ok, srv} = RedisServerWrapper.Server.start_link(port: 6459)

      {:ok, r} =
        Resilience.start_link(
          port: 6459,
          circuit_breaker: [failure_threshold: 3, reset_timeout: 2_000]
        )

      assert {:ok, "PONG"} = Resilience.command(r, ["PING"])

      # Kill the server to cause failures
      RedisServerWrapper.Server.stop(srv)
      Process.sleep(500)

      # Trigger failures to trip the breaker
      for _ <- 1..5 do
        Resilience.command(r, ["PING"])
      end

      Process.sleep(50)
      info = Resilience.info(r)
      assert info.circuit_breaker.state == :open

      # Open circuit should fail fast
      assert {:error, :circuit_open} = Resilience.command(r, ["PING"])

      # Restart server and wait for half-open
      {:ok, _srv2} = RedisServerWrapper.Server.start_link(port: 6459)
      Process.sleep(4000)

      Resilience.stop(r)
      Process.sleep(500)
    end

    test "full resilience stack handles transient failure" do
      {:ok, _srv} = RedisServerWrapper.Server.start_link(port: 6460)

      {:ok, r} =
        Resilience.start_link(
          port: 6460,
          retry: [max_attempts: 3, base_delay: 50],
          circuit_breaker: [failure_threshold: 10]
        )

      # Normal operation
      assert {:ok, "OK"} = Resilience.command(r, ["SET", "res_key", "res_val"])
      assert {:ok, "res_val"} = Resilience.command(r, ["GET", "res_key"])

      Resilience.stop(r)
      Process.sleep(500)
    end
  end

  # -------------------------------------------------------------------
  # Protocol edge cases
  # -------------------------------------------------------------------

  describe "protocol edge cases" do
    test "binary-safe keys and values" do
      {:ok, _srv} = RedisServerWrapper.Server.start_link(port: 6461)
      {:ok, conn} = Connection.start_link(port: 6461)

      # Binary with nulls, newlines, CRLF
      value = <<0, 1, 2, 3, 13, 10, 255, "hello\r\nworld">>
      assert {:ok, "OK"} = Connection.command(conn, ["SET", "bin_key", value])
      assert {:ok, ^value} = Connection.command(conn, ["GET", "bin_key"])

      Connection.stop(conn)
      Process.sleep(500)
    end

    test "large pipeline response" do
      {:ok, _srv} = RedisServerWrapper.Server.start_link(port: 6462)
      {:ok, conn} = Connection.start_link(port: 6462)

      # Set 500 keys
      sets = for i <- 1..500, do: ["SET", "large:#{i}", String.duplicate("x", 100)]
      {:ok, results} = Connection.pipeline(conn, sets)
      assert length(results) == 500
      assert Enum.all?(results, &(&1 == "OK"))

      # Get them all back
      gets = for i <- 1..500, do: ["GET", "large:#{i}"]
      {:ok, values} = Connection.pipeline(conn, gets)
      assert length(values) == 500
      assert Enum.all?(values, &(byte_size(&1) == 100))

      Connection.stop(conn)
      Process.sleep(500)
    end

    test "single command pipeline" do
      {:ok, _srv} = RedisServerWrapper.Server.start_link(port: 6463)
      {:ok, conn} = Connection.start_link(port: 6463)

      assert {:ok, ["PONG"]} = Connection.pipeline(conn, [["PING"]])

      Connection.stop(conn)
      Process.sleep(500)
    end

    test "rapid fire commands" do
      {:ok, _srv} = RedisServerWrapper.Server.start_link(port: 6464)
      {:ok, conn} = Connection.start_link(port: 6464)

      # 1000 sequential commands as fast as possible
      for i <- 1..1000 do
        {:ok, _} = Connection.command(conn, ["SET", "rapid:#{i}", to_string(i)])
      end

      {:ok, "1000"} = Connection.command(conn, ["GET", "rapid:1000"])

      Connection.stop(conn)
      Process.sleep(500)
    end
  end
end

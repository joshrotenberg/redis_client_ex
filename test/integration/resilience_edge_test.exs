defmodule Redis.ResilienceEdgeTest do
  use ExUnit.Case, async: false

  alias Redis.Connection
  alias Redis.Resilience.{Bulkhead, CircuitBreaker, Coalesce, Retry}
  alias RedisServerWrapper.Server

  @moduletag timeout: 60_000

  # -------------------------------------------------------------------
  # Bulkhead edge cases
  # -------------------------------------------------------------------

  describe "Bulkhead: max_concurrent rejection under saturation" do
    test "rejects requests when all slots are occupied" do
      {:ok, srv} = Server.start_link(port: 6510)
      Process.sleep(200)
      {:ok, conn} = Connection.start_link(port: 6510, sync_connect: true)

      {:ok, bh} = Bulkhead.start_link(conn: conn, max_concurrent: 2, max_wait: 0)

      barrier = :ets.new(:barrier, [:set, :public])
      :ets.insert(barrier, {:go, false})

      # Saturate the bulkhead with 2 slow commands (BLPOP on nonexistent keys)
      blockers =
        for i <- 1..2 do
          Task.async(fn ->
            Bulkhead.command(bh, ["BLPOP", "edge_block_#{i}_#{System.unique_integer()}", "3"])
          end)
        end

      # Let the blocking commands land
      Process.sleep(200)

      # Verify state shows 2 active
      state = Bulkhead.state(bh)
      assert state.active == 2

      # Additional requests should be rejected immediately (max_wait: 0)
      assert {:error, :bulkhead_full} = Bulkhead.command(bh, ["PING"])
      assert {:error, :bulkhead_full} = Bulkhead.command(bh, ["PING"])

      # Wait for blockers to finish
      Task.await_many(blockers, 10_000)

      # After slots free up, commands should succeed again
      assert {:ok, "PONG"} = Bulkhead.command(bh, ["PING"])

      Bulkhead.stop(bh)
      Connection.stop(conn)
      Server.stop(srv)
    end

    test "queued requests time out when max_wait expires" do
      {:ok, srv} = Server.start_link(port: 6511)
      Process.sleep(200)
      {:ok, conn} = Connection.start_link(port: 6511, sync_connect: true)

      {:ok, bh} = Bulkhead.start_link(conn: conn, max_concurrent: 1, max_wait: 200)

      # Occupy the single slot with a slow command
      blocker =
        Task.async(fn ->
          Bulkhead.command(bh, ["BLPOP", "edge_wait_#{System.unique_integer()}", "3"])
        end)

      Process.sleep(100)

      # This request should be queued and then time out after max_wait (200ms)
      start = System.monotonic_time(:millisecond)
      result = Bulkhead.command(bh, ["PING"])
      elapsed = System.monotonic_time(:millisecond) - start

      assert result == {:error, :bulkhead_full}
      # Should have waited roughly max_wait duration (allow some tolerance)
      assert elapsed >= 150
      assert elapsed < 1000

      Task.await(blocker, 10_000)
      Bulkhead.stop(bh)
      Connection.stop(conn)
      Server.stop(srv)
    end
  end

  # -------------------------------------------------------------------
  # CircuitBreaker edge cases
  # -------------------------------------------------------------------

  describe "CircuitBreaker: success_threshold > 1 in half-open state" do
    test "requires multiple successes to close from half-open" do
      {:ok, srv} = Server.start_link(port: 6512)
      Process.sleep(200)
      {:ok, conn} = Connection.start_link(port: 6512, sync_connect: true)

      {:ok, cb} =
        CircuitBreaker.start_link(
          conn: conn,
          failure_threshold: 2,
          reset_timeout: 500,
          success_threshold: 3
        )

      # Confirm closed
      assert %{state: :closed} = CircuitBreaker.state(cb)

      # Kill server to trigger failures
      Server.stop(srv)
      Process.sleep(300)

      # Trip the circuit open (2 failures)
      CircuitBreaker.command(cb, ["PING"])
      CircuitBreaker.command(cb, ["PING"])
      assert %{state: :open} = CircuitBreaker.state(cb)

      # Restart server and wait for half-open transition
      {:ok, srv2} = Server.start_link(port: 6512)
      Process.sleep(2000)

      state_info = CircuitBreaker.state(cb)
      assert state_info.state in [:half_open, :closed]

      if state_info.state == :half_open do
        # First success in half-open: should NOT close yet (need 3)
        assert {:ok, "PONG"} = CircuitBreaker.command(cb, ["PING"])
        state_after_1 = CircuitBreaker.state(cb)
        # Could still be half_open or might have closed if success_count reached threshold
        # With success_threshold=3, after 1 success we should still be half_open
        assert state_after_1.state == :half_open
        assert state_after_1.success_count == 1

        # Second success: still half-open
        assert {:ok, "PONG"} = CircuitBreaker.command(cb, ["PING"])
        state_after_2 = CircuitBreaker.state(cb)
        assert state_after_2.state == :half_open
        assert state_after_2.success_count == 2

        # Third success: should close the circuit
        assert {:ok, "PONG"} = CircuitBreaker.command(cb, ["PING"])

        assert %{state: :closed, success_count: 0, failure_count: 0} =
                 CircuitBreaker.state(cb)
      end

      CircuitBreaker.stop(cb)
      Connection.stop(conn)
      Server.stop(srv2)
    end

    test "state/1 returns correct counts during operation" do
      {:ok, srv} = Server.start_link(port: 6513)
      Process.sleep(200)
      {:ok, conn} = Connection.start_link(port: 6513, sync_connect: true)

      {:ok, cb} =
        CircuitBreaker.start_link(
          conn: conn,
          failure_threshold: 5,
          reset_timeout: 500,
          success_threshold: 2
        )

      # Initial state
      info = CircuitBreaker.state(cb)
      assert info.state == :closed
      assert info.failure_count == 0
      assert info.success_count == 0

      # A success in closed state resets failure_count to 0
      assert {:ok, "PONG"} = CircuitBreaker.command(cb, ["PING"])
      info = CircuitBreaker.state(cb)
      assert info.state == :closed
      assert info.failure_count == 0

      # Kill server, produce failures
      Server.stop(srv)
      Process.sleep(300)

      CircuitBreaker.command(cb, ["PING"])
      info = CircuitBreaker.state(cb)
      assert info.state == :closed
      assert info.failure_count == 1

      CircuitBreaker.command(cb, ["PING"])
      info = CircuitBreaker.state(cb)
      assert info.state == :closed
      assert info.failure_count == 2

      CircuitBreaker.stop(cb)
      Connection.stop(conn)
    end
  end

  # -------------------------------------------------------------------
  # Retry edge cases
  # -------------------------------------------------------------------

  describe "Retry: max_attempts exhaustion" do
    test "returns last error after all attempts exhausted" do
      {:ok, srv} = Server.start_link(port: 6514)
      Process.sleep(200)
      {:ok, conn} = Connection.start_link(port: 6514, sync_connect: true)

      # Kill the server so all retries fail
      Server.stop(srv)
      Process.sleep(300)

      {:ok, retried} =
        Retry.start_link(
          conn: conn,
          max_attempts: 3,
          backoff: :fixed,
          base_delay: 50,
          jitter: 0.0
        )

      start = System.monotonic_time(:millisecond)
      result = Retry.command(retried, ["PING"])
      elapsed = System.monotonic_time(:millisecond) - start

      # Should have failed with a connection error
      assert {:error, %Redis.ConnectionError{}} = result

      # Should have taken at least 2 retry delays (50ms each, 2 retries after first attempt)
      assert elapsed >= 80

      Retry.stop(retried)
      Connection.stop(conn)
    end

    test "linear backoff increases delay linearly" do
      {:ok, srv} = Server.start_link(port: 6514)
      Process.sleep(200)
      {:ok, conn} = Connection.start_link(port: 6514, sync_connect: true)

      Server.stop(srv)
      Process.sleep(300)

      {:ok, retried} =
        Retry.start_link(
          conn: conn,
          max_attempts: 4,
          backoff: :linear,
          base_delay: 100,
          jitter: 0.0
        )

      # Linear: delays are base*1, base*2, base*3 = 100, 200, 300 = 600ms total
      start = System.monotonic_time(:millisecond)
      _result = Retry.command(retried, ["PING"])
      elapsed = System.monotonic_time(:millisecond) - start

      # Total delay should be around 600ms (100+200+300), allow tolerance
      assert elapsed >= 500
      assert elapsed < 1200

      Retry.stop(retried)
      Connection.stop(conn)
    end

    test "exponential backoff increases delay exponentially" do
      {:ok, srv} = Server.start_link(port: 6514)
      Process.sleep(200)
      {:ok, conn} = Connection.start_link(port: 6514, sync_connect: true)

      Server.stop(srv)
      Process.sleep(300)

      {:ok, retried} =
        Retry.start_link(
          conn: conn,
          max_attempts: 4,
          backoff: :exponential,
          base_delay: 50,
          jitter: 0.0
        )

      # Exponential: delays are 50*2^0, 50*2^1, 50*2^2 = 50, 100, 200 = 350ms total
      start = System.monotonic_time(:millisecond)
      _result = Retry.command(retried, ["PING"])
      elapsed = System.monotonic_time(:millisecond) - start

      # Total delay should be around 350ms, allow tolerance
      assert elapsed >= 280
      assert elapsed < 800

      Retry.stop(retried)
      Connection.stop(conn)
    end

    test "non-retryable Redis app errors are not retried" do
      {:ok, _srv} = Server.start_link(port: 6515)
      Process.sleep(200)
      {:ok, conn} = Connection.start_link(port: 6515, sync_connect: true)

      # Set up a string key, then try an operation that produces a WRONGTYPE error
      {:ok, "OK"} = Connection.command(conn, ["SET", "wrongtype_key", "hello"])

      {:ok, retried} =
        Retry.start_link(
          conn: conn,
          max_attempts: 5,
          backoff: :fixed,
          base_delay: 100,
          jitter: 0.0
        )

      # LPUSH on a string key produces WRONGTYPE error, which should NOT be retried
      start = System.monotonic_time(:millisecond)
      result = Retry.command(retried, ["LPUSH", "wrongtype_key", "item"])
      elapsed = System.monotonic_time(:millisecond) - start

      # Should get a Redis error (not connection error)
      assert {:error, %Redis.Error{}} = result

      # Should return almost immediately (no retries), well under one retry delay
      assert elapsed < 80

      Retry.stop(retried)
      Connection.stop(conn)
    end
  end

  # -------------------------------------------------------------------
  # Coalesce edge cases
  # -------------------------------------------------------------------

  describe "Coalesce: concurrent identical commands get same result" do
    test "multiple tasks with same command receive identical results" do
      {:ok, _srv} = Server.start_link(port: 6515)
      Process.sleep(200)
      {:ok, conn} = Connection.start_link(port: 6515, sync_connect: true)

      {:ok, "OK"} = Connection.command(conn, ["SET", "coal_edge_key", "shared_value"])

      {:ok, coal} = Coalesce.start_link(conn: conn)

      # Launch many concurrent requests for the exact same command
      tasks =
        for _ <- 1..20 do
          Task.async(fn ->
            Coalesce.command(coal, ["GET", "coal_edge_key"])
          end)
        end

      results = Task.await_many(tasks, 10_000)

      # All should get the same successful result
      assert length(results) == 20
      assert Enum.all?(results, &(&1 == {:ok, "shared_value"}))

      Coalesce.stop(coal)
      Connection.stop(conn)
    end

    test "different commands are not coalesced" do
      {:ok, _srv} = Server.start_link(port: 6515)
      Process.sleep(200)
      {:ok, conn} = Connection.start_link(port: 6515, sync_connect: true)

      {:ok, "OK"} = Connection.command(conn, ["SET", "coal_a", "val_a"])
      {:ok, "OK"} = Connection.command(conn, ["SET", "coal_b", "val_b"])

      {:ok, coal} = Coalesce.start_link(conn: conn)

      # Launch concurrent requests for different keys
      task_a = Task.async(fn -> Coalesce.command(coal, ["GET", "coal_a"]) end)
      task_b = Task.async(fn -> Coalesce.command(coal, ["GET", "coal_b"]) end)

      result_a = Task.await(task_a, 5_000)
      result_b = Task.await(task_b, 5_000)

      assert result_a == {:ok, "val_a"}
      assert result_b == {:ok, "val_b"}

      Coalesce.stop(coal)
      Connection.stop(conn)
    end
  end
end

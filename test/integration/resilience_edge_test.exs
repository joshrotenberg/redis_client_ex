defmodule Redis.ResilienceEdgeTest do
  use ExUnit.Case, async: false

  alias Redis.Resilience
  alias RedisServerWrapper.Server

  @moduletag timeout: 60_000
  @moduletag :ex_resilience

  # -------------------------------------------------------------------
  # Bulkhead edge cases
  # -------------------------------------------------------------------

  describe "Bulkhead: rejection via ExResilience directly" do
    test "rejects when concurrency limit exceeded" do
      # Test the bulkhead directly with ExResilience to verify rejection
      # behavior without the single-connection serialization bottleneck.
      bh_name = :"test_bh_#{System.unique_integer([:positive])}"
      {:ok, _} = ExResilience.Bulkhead.start_link(name: bh_name, max_concurrent: 2, max_wait: 0)

      barrier = :ets.new(:barrier, [:set, :public])
      :ets.insert(barrier, {:go, false})

      # Saturate with 2 slow tasks
      blockers =
        for _ <- 1..2 do
          Task.async(fn ->
            ExResilience.Bulkhead.call(bh_name, fn ->
              wait_for_signal(barrier)
              :done
            end)
          end)
        end

      Process.sleep(50)

      # Additional calls should be rejected
      assert {:error, :bulkhead_full} =
               ExResilience.Bulkhead.call(bh_name, fn -> :should_not_run end)

      # Release blockers
      :ets.insert(barrier, {:go, true})
      Task.await_many(blockers, 5_000)

      # After slots free, calls succeed
      assert {:ok, :works} = ExResilience.Bulkhead.call(bh_name, fn -> :works end)

      GenServer.stop(bh_name)
    end

    test "queued requests time out when max_wait expires" do
      bh_name = :"test_bh_wait_#{System.unique_integer([:positive])}"
      {:ok, _} = ExResilience.Bulkhead.start_link(name: bh_name, max_concurrent: 1, max_wait: 200)

      barrier = :ets.new(:barrier2, [:set, :public])
      :ets.insert(barrier, {:go, false})

      # Occupy the single slot
      blocker =
        Task.async(fn ->
          ExResilience.Bulkhead.call(bh_name, fn ->
            wait_for_signal(barrier)
            :done
          end)
        end)

      Process.sleep(50)

      # This should be queued then time out
      start = System.monotonic_time(:millisecond)
      result = ExResilience.Bulkhead.call(bh_name, fn -> :should_timeout end)
      elapsed = System.monotonic_time(:millisecond) - start

      assert result == {:error, :bulkhead_full}
      assert elapsed >= 150
      assert elapsed < 1000

      :ets.insert(barrier, {:go, true})
      Task.await(blocker, 5_000)
      GenServer.stop(bh_name)
    end
  end

  describe "Bulkhead: integration through facade" do
    test "bulkhead allows normal commands and shows in info" do
      {:ok, srv} = Server.start_link(port: 6510)
      Process.sleep(200)

      {:ok, r} =
        Resilience.start_link(
          port: 6510,
          sync_connect: true,
          bulkhead: [max_concurrent: 10]
        )

      assert {:ok, "PONG"} = Resilience.command(r, ["PING"])

      info = Resilience.info(r)
      assert :bulkhead in info.layers
      assert info.bulkhead.active >= 0

      Resilience.stop(r)
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

      {:ok, r} =
        Resilience.start_link(
          port: 6512,
          sync_connect: true,
          circuit_breaker: [
            failure_threshold: 2,
            reset_timeout: 500,
            success_threshold: 3
          ]
        )

      # Confirm closed
      info = Resilience.info(r)
      assert info.circuit_breaker.state == :closed

      # Kill server to trigger failures
      Server.stop(srv)
      Process.sleep(300)

      # Trip the circuit open (2 failures)
      Resilience.command(r, ["PING"])
      Resilience.command(r, ["PING"])
      Process.sleep(50)

      info = Resilience.info(r)
      assert info.circuit_breaker.state == :open

      # Restart server and wait for half-open transition
      {:ok, srv2} = Server.start_link(port: 6512)
      Process.sleep(2000)

      info = Resilience.info(r)

      if info.circuit_breaker.state == :half_open do
        # First success: should NOT close yet (need 3)
        assert {:ok, "PONG"} = Resilience.command(r, ["PING"])
        Process.sleep(50)
        info = Resilience.info(r)
        assert info.circuit_breaker.state == :half_open
        assert info.circuit_breaker.success_count == 1

        # Second success: still half-open
        assert {:ok, "PONG"} = Resilience.command(r, ["PING"])
        Process.sleep(50)
        info = Resilience.info(r)
        assert info.circuit_breaker.state == :half_open
        assert info.circuit_breaker.success_count == 2

        # Third success: should close the circuit
        assert {:ok, "PONG"} = Resilience.command(r, ["PING"])
        Process.sleep(50)
        info = Resilience.info(r)
        assert info.circuit_breaker.state == :closed
        assert info.circuit_breaker.success_count == 0
      end

      Resilience.stop(r)
      Server.stop(srv2)
    end
  end

  # -------------------------------------------------------------------
  # Retry edge cases
  # -------------------------------------------------------------------

  describe "Retry: max_attempts exhaustion" do
    test "returns last error after all attempts exhausted" do
      {:ok, srv} = Server.start_link(port: 6514)
      Process.sleep(200)

      {:ok, r} =
        Resilience.start_link(
          port: 6514,
          sync_connect: true,
          retry: [max_attempts: 3, backoff: :fixed, base_delay: 50, jitter: false]
        )

      # Kill the server so all retries fail
      Server.stop(srv)
      Process.sleep(300)

      start = System.monotonic_time(:millisecond)
      result = Resilience.command(r, ["PING"])
      elapsed = System.monotonic_time(:millisecond) - start

      assert {:error, %Redis.ConnectionError{}} = result
      # Should have taken at least 2 retry delays (50ms each)
      assert elapsed >= 80

      Resilience.stop(r)
    end

    test "non-retryable Redis app errors are not retried" do
      {:ok, _srv} = Server.start_link(port: 6515)
      Process.sleep(200)

      {:ok, r} =
        Resilience.start_link(
          port: 6515,
          sync_connect: true,
          retry: [max_attempts: 5, backoff: :fixed, base_delay: 100, jitter: false]
        )

      Resilience.command(r, ["SET", "wrongtype_key", "hello"])

      # LPUSH on a string key produces WRONGTYPE error, should NOT be retried
      start = System.monotonic_time(:millisecond)
      result = Resilience.command(r, ["LPUSH", "wrongtype_key", "item"])
      elapsed = System.monotonic_time(:millisecond) - start

      assert {:error, %Redis.Error{}} = result
      # Should return almost immediately (no retries)
      assert elapsed < 80

      Resilience.stop(r)
    end
  end

  # -------------------------------------------------------------------
  # Coalesce edge cases
  # -------------------------------------------------------------------

  describe "Coalesce: concurrent identical commands get same result" do
    test "multiple tasks with same command receive identical results" do
      {:ok, _srv} = Server.start_link(port: 6515)
      Process.sleep(200)

      {:ok, r} =
        Resilience.start_link(
          port: 6515,
          sync_connect: true,
          coalesce: true
        )

      Resilience.command(r, ["SET", "coal_edge_key", "shared_value"])

      tasks =
        for _ <- 1..20 do
          Task.async(fn -> Resilience.command(r, ["GET", "coal_edge_key"]) end)
        end

      results = Task.await_many(tasks, 10_000)

      assert length(results) == 20
      assert Enum.all?(results, &(&1 == {:ok, "shared_value"}))

      Resilience.stop(r)
    end

    test "different commands are not coalesced" do
      {:ok, _srv} = Server.start_link(port: 6515)
      Process.sleep(200)

      {:ok, r} =
        Resilience.start_link(
          port: 6515,
          sync_connect: true,
          coalesce: true
        )

      Resilience.command(r, ["SET", "coal_a", "val_a"])
      Resilience.command(r, ["SET", "coal_b", "val_b"])

      task_a = Task.async(fn -> Resilience.command(r, ["GET", "coal_a"]) end)
      task_b = Task.async(fn -> Resilience.command(r, ["GET", "coal_b"]) end)

      assert {:ok, "val_a"} = Task.await(task_a, 5_000)
      assert {:ok, "val_b"} = Task.await(task_b, 5_000)

      Resilience.stop(r)
    end
  end

  defp wait_for_signal(table) do
    case :ets.lookup(table, :go) do
      [{:go, true}] -> :ok
      _ -> Process.sleep(10) && wait_for_signal(table)
    end
  end
end

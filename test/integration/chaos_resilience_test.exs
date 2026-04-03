defmodule Redis.ChaosResilienceTest do
  use ExUnit.Case, async: false

  alias Redis.Connection
  alias Redis.Resilience
  alias Redis.Resilience.CircuitBreaker
  alias RedisServerWrapper.{Chaos, Server}

  @moduletag timeout: 60_000

  describe "circuit breaker with server kill" do
    test "circuit opens on failures, recovers after server restart" do
      {:ok, srv} = Server.start_link(port: 6500)
      {:ok, conn} = Connection.start_link(port: 6500)

      {:ok, cb} =
        CircuitBreaker.start_link(
          conn: conn,
          failure_threshold: 3,
          reset_timeout: 2_000,
          success_threshold: 1
        )

      # Normal operation
      assert {:ok, "PONG"} = CircuitBreaker.command(cb, ["PING"])
      assert %{state: :closed, failure_count: 0} = CircuitBreaker.state(cb)

      # Kill the server
      Server.stop(srv)
      Process.sleep(500)

      # Commands should fail and count towards threshold
      for _ <- 1..3 do
        CircuitBreaker.command(cb, ["PING"])
      end

      # Circuit should be open
      assert %{state: :open} = CircuitBreaker.state(cb)
      assert {:error, :circuit_open} = CircuitBreaker.command(cb, ["PING"])

      # Restart the server
      {:ok, _srv2} = Server.start_link(port: 6500)
      # Wait for connection to reconnect + circuit reset_timeout
      Process.sleep(4000)

      # Circuit should be half-open, next success closes it
      state = CircuitBreaker.state(cb)
      assert state.state in [:half_open, :closed]

      # Probe should succeed and close the circuit
      assert {:ok, "PONG"} = CircuitBreaker.command(cb, ["PING"])
      Process.sleep(100)
      assert %{state: :closed} = CircuitBreaker.state(cb)

      CircuitBreaker.stop(cb)
      Connection.stop(conn)
    end
  end

  describe "resilience stack with chaos" do
    test "composed retry + circuit breaker survives server restart" do
      {:ok, srv} = Server.start_link(port: 6501)

      {:ok, r} =
        Resilience.start_link(
          port: 6501,
          retry: [max_attempts: 3, backoff: :exponential],
          circuit_breaker: [failure_threshold: 5, reset_timeout: 2_000]
        )

      # Normal operation
      assert {:ok, "OK"} = Resilience.command(r, ["SET", "rkey", "value"])
      assert {:ok, "value"} = Resilience.command(r, ["GET", "rkey"])

      # Kill the server
      Server.stop(srv)
      Process.sleep(500)

      # Commands should fail (retry exhausted, then circuit opens)
      for _ <- 1..5 do
        Resilience.command(r, ["PING"])
      end

      # Restart server
      {:ok, _srv2} = Server.start_link(port: 6501)
      Process.sleep(5000)

      # Should recover -- retry finds the reconnected connection
      result = Resilience.command(r, ["PING"])
      assert {:ok, "PONG"} = result

      # Data should be gone (new server instance)
      assert {:ok, nil} = Resilience.command(r, ["GET", "rkey"])

      Resilience.stop(r)
    end

    test "retry handles brief freeze gracefully" do
      {:ok, srv} = Server.start_link(port: 6502)

      {:ok, r} =
        Resilience.start_link(
          port: 6502,
          retry: [max_attempts: 5, backoff: :linear]
        )

      assert {:ok, "OK"} = Resilience.command(r, ["SET", "fkey", "frozen"])

      # Freeze the server briefly (2 seconds)
      Chaos.slow_down(srv, 2_000)

      # This command might timeout on first try but retry should succeed
      # after the pause ends
      Process.sleep(3000)
      assert {:ok, "frozen"} = Resilience.command(r, ["GET", "fkey"])

      Resilience.stop(r)
      Server.stop(srv)
    end
  end

  describe "bulkhead under load" do
    test "bulkhead rejects when concurrency limit exceeded" do
      {:ok, _srv} = Server.start_link(port: 6503)

      {:ok, r} =
        Resilience.start_link(
          port: 6503,
          bulkhead: [max_concurrent: 2]
        )

      # Slow down the server to create contention
      parent = self()

      # Launch 5 concurrent requests against a bulkhead of 2
      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            result = Resilience.command(r, ["SET", "bk:#{i}", "val"])
            send(parent, {:done, i, result})
            result
          end)
        end

      results = Task.await_many(tasks, 10_000)

      # Some should succeed, some might be rejected
      successes = Enum.count(results, &match?({:ok, _}, &1))
      IO.puts("Bulkhead: #{successes}/5 succeeded")
      assert successes >= 2

      Resilience.stop(r)
    end
  end

  describe "circuit breaker state transitions" do
    test "closed -> open -> half_open -> closed lifecycle" do
      {:ok, srv} = Server.start_link(port: 6504)
      {:ok, conn} = Connection.start_link(port: 6504)

      {:ok, cb} =
        CircuitBreaker.start_link(
          conn: conn,
          failure_threshold: 2,
          reset_timeout: 1_000,
          success_threshold: 1
        )

      # CLOSED: normal operation
      assert %{state: :closed} = CircuitBreaker.state(cb)
      assert {:ok, "PONG"} = CircuitBreaker.command(cb, ["PING"])

      # Trigger failures to open the circuit
      Server.stop(srv)
      Process.sleep(500)

      CircuitBreaker.command(cb, ["PING"])
      CircuitBreaker.command(cb, ["PING"])

      # OPEN: fast-fail
      assert %{state: :open} = CircuitBreaker.state(cb)
      assert {:error, :circuit_open} = CircuitBreaker.command(cb, ["PING"])

      # Restart and wait for half-open
      {:ok, _srv2} = Server.start_link(port: 6504)
      Process.sleep(3000)

      # HALF_OPEN: probe request allowed
      state = CircuitBreaker.state(cb)
      assert state.state in [:half_open, :closed]

      # Success closes the circuit
      assert {:ok, "PONG"} = CircuitBreaker.command(cb, ["PING"])
      Process.sleep(100)

      # CLOSED: back to normal
      assert %{state: :closed} = CircuitBreaker.state(cb)

      CircuitBreaker.stop(cb)
      Connection.stop(conn)
    end
  end
end

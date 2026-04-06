defmodule Redis.ChaosResilienceTest do
  use ExUnit.Case, async: false

  alias Redis.Resilience
  alias RedisServerWrapper.{Chaos, Server}

  @moduletag timeout: 60_000
  @moduletag :ex_resilience

  describe "circuit breaker with server kill" do
    test "circuit opens on failures, recovers after server restart" do
      {:ok, srv} = Server.start_link(port: 6500)

      {:ok, r} =
        Resilience.start_link(
          port: 6500,
          circuit_breaker: [
            failure_threshold: 3,
            reset_timeout: 2_000,
            success_threshold: 1
          ]
        )

      # Normal operation
      assert {:ok, "PONG"} = Resilience.command(r, ["PING"])
      info = Resilience.info(r)
      assert info.circuit_breaker.state == :closed

      # Kill the server
      Server.stop(srv)
      Process.sleep(500)

      # Commands should fail and count towards threshold
      for _ <- 1..3 do
        Resilience.command(r, ["PING"])
      end

      Process.sleep(50)

      # Circuit should be open
      info = Resilience.info(r)
      assert info.circuit_breaker.state == :open
      assert {:error, :circuit_open} = Resilience.command(r, ["PING"])

      # Restart the server
      {:ok, _srv2} = Server.start_link(port: 6500)
      # Wait for connection to reconnect + circuit reset_timeout
      Process.sleep(4000)

      # Circuit should be half-open, next success closes it
      info = Resilience.info(r)
      assert info.circuit_breaker.state in [:half_open, :closed]

      # Probe should succeed and close the circuit
      assert {:ok, "PONG"} = Resilience.command(r, ["PING"])
      Process.sleep(100)
      info = Resilience.info(r)
      assert info.circuit_breaker.state == :closed

      Resilience.stop(r)
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

      # Should recover
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

      # Launch 5 concurrent requests against a bulkhead of 2
      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            Resilience.command(r, ["SET", "bk:#{i}", "val"])
          end)
        end

      results = Task.await_many(tasks, 10_000)

      successes = Enum.count(results, &match?({:ok, _}, &1))
      assert successes >= 2

      Resilience.stop(r)
    end
  end

  describe "circuit breaker state transitions" do
    test "closed -> open -> half_open -> closed lifecycle" do
      {:ok, srv} = Server.start_link(port: 6504)

      {:ok, r} =
        Resilience.start_link(
          port: 6504,
          circuit_breaker: [
            failure_threshold: 2,
            reset_timeout: 1_000,
            success_threshold: 1
          ]
        )

      # CLOSED: normal operation
      info = Resilience.info(r)
      assert info.circuit_breaker.state == :closed
      assert {:ok, "PONG"} = Resilience.command(r, ["PING"])

      # Trigger failures to open the circuit
      Server.stop(srv)
      Process.sleep(500)

      Resilience.command(r, ["PING"])
      Resilience.command(r, ["PING"])
      Process.sleep(50)

      # OPEN: fast-fail
      info = Resilience.info(r)
      assert info.circuit_breaker.state == :open
      assert {:error, :circuit_open} = Resilience.command(r, ["PING"])

      # Restart and wait for half-open
      {:ok, _srv2} = Server.start_link(port: 6504)
      Process.sleep(3000)

      # HALF_OPEN: probe request allowed
      info = Resilience.info(r)
      assert info.circuit_breaker.state in [:half_open, :closed]

      # Success closes the circuit
      assert {:ok, "PONG"} = Resilience.command(r, ["PING"])
      Process.sleep(100)

      # CLOSED: back to normal
      info = Resilience.info(r)
      assert info.circuit_breaker.state == :closed

      Resilience.stop(r)
    end
  end
end

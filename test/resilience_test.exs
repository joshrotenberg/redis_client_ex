defmodule RedisEx.ResilienceTest do
  use ExUnit.Case, async: false

  alias RedisEx.Connection
  alias RedisEx.Resilience
  alias RedisEx.Resilience.{CircuitBreaker, Retry, Coalesce, Bulkhead}

  # Uses redis-server on port 6398 from test_helper.exs

  describe "CircuitBreaker" do
    test "passes through when closed" do
      {:ok, conn} = Connection.start_link(port: 6398)
      {:ok, cb} = CircuitBreaker.start_link(conn: conn, failure_threshold: 3)

      assert {:ok, "PONG"} = CircuitBreaker.command(cb, ["PING"])
      assert %{state: :closed, failure_count: 0} = CircuitBreaker.state(cb)

      CircuitBreaker.stop(cb)
      Connection.stop(conn)
    end

    test "manual reset" do
      {:ok, conn} = Connection.start_link(port: 6398)
      {:ok, cb} = CircuitBreaker.start_link(conn: conn, failure_threshold: 3)

      CircuitBreaker.reset(cb)
      assert %{state: :closed} = CircuitBreaker.state(cb)

      CircuitBreaker.stop(cb)
      Connection.stop(conn)
    end
  end

  describe "Retry" do
    test "succeeds on first attempt" do
      {:ok, conn} = Connection.start_link(port: 6398)
      {:ok, retried} = Retry.start_link(conn: conn, max_attempts: 3)

      assert {:ok, "PONG"} = Retry.command(retried, ["PING"])

      Retry.stop(retried)
      Connection.stop(conn)
    end

    test "does not retry Redis errors" do
      {:ok, conn} = Connection.start_link(port: 6398)
      Connection.command(conn, ["SET", "str", "notanumber"])
      {:ok, retried} = Retry.start_link(conn: conn, max_attempts: 3)

      # INCR on a string produces a Redis error, not a connection error
      assert {:error, %RedisEx.Error{}} = Retry.command(retried, ["INCR", "str"])

      Retry.stop(retried)
      Connection.stop(conn)
    end
  end

  describe "Coalesce" do
    test "deduplicates concurrent identical requests" do
      {:ok, conn} = Connection.start_link(port: 6398)
      Connection.command(conn, ["SET", "coal_key", "coal_val"])
      {:ok, coal} = Coalesce.start_link(conn: conn)

      # Fire 5 concurrent requests for the same key
      tasks =
        for _ <- 1..5 do
          Task.async(fn -> Coalesce.command(coal, ["GET", "coal_key"]) end)
        end

      results = Enum.map(tasks, &Task.await/1)

      # All should get the same result
      assert Enum.all?(results, &(&1 == {:ok, "coal_val"}))

      Coalesce.stop(coal)
      Connection.stop(conn)
    end
  end

  describe "Bulkhead" do
    test "allows requests within limit" do
      {:ok, conn} = Connection.start_link(port: 6398)
      {:ok, bh} = Bulkhead.start_link(conn: conn, max_concurrent: 10)

      assert {:ok, "PONG"} = Bulkhead.command(bh, ["PING"])
      assert %{active: 0, max_concurrent: 10, queued: 0} = Bulkhead.state(bh)

      Bulkhead.stop(bh)
      Connection.stop(conn)
    end

    test "rejects when full and max_wait is 0" do
      {:ok, conn} = Connection.start_link(port: 6398)
      {:ok, bh} = Bulkhead.start_link(conn: conn, max_concurrent: 1, max_wait: 0)

      # Fill the single slot with a blocking command (BLPOP with 2s timeout on empty list)
      task = Task.async(fn -> Bulkhead.command(bh, ["BLPOP", "nonexistent_list_#{System.unique_integer()}", "2"]) end)
      Process.sleep(100)

      # This should be rejected immediately since the slot is occupied
      result = Bulkhead.command(bh, ["PING"])
      assert result == {:error, :bulkhead_full}

      Task.await(task, 5000)
      Bulkhead.stop(bh)
      Connection.stop(conn)
    end
  end

  describe "Resilience (composed)" do
    test "full stack works" do
      {:ok, r} =
        Resilience.start_link(
          port: 6398,
          retry: [max_attempts: 2],
          circuit_breaker: [failure_threshold: 5],
          bulkhead: [max_concurrent: 20]
        )

      assert {:ok, "PONG"} = Resilience.command(r, ["PING"])
      assert {:ok, "OK"} = Resilience.command(r, ["SET", "res_key", "res_val"])
      assert {:ok, "res_val"} = Resilience.command(r, ["GET", "res_key"])

      info = Resilience.info(r)
      assert :retry in info.layers
      assert :circuit_breaker in info.layers
      assert :bulkhead in info.layers
      assert info.circuit_breaker.state == :closed

      Resilience.stop(r)
    end

    test "pipeline through resilience stack" do
      {:ok, r} =
        Resilience.start_link(
          port: 6398,
          retry: [max_attempts: 2],
          circuit_breaker: [failure_threshold: 5]
        )

      {:ok, results} =
        Resilience.pipeline(r, [
          ["SET", "rp_a", "1"],
          ["SET", "rp_b", "2"],
          ["GET", "rp_a"]
        ])

      assert results == ["OK", "OK", "1"]

      Resilience.stop(r)
    end

    test "connection only (no resilience layers)" do
      {:ok, r} = Resilience.start_link(port: 6398)

      assert {:ok, "PONG"} = Resilience.command(r, ["PING"])

      info = Resilience.info(r)
      assert info.layers == []

      Resilience.stop(r)
    end
  end
end

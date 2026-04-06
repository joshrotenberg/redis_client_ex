defmodule Redis.ResilienceTest do
  use ExUnit.Case, async: false

  alias Redis.Connection
  alias Redis.Resilience

  @moduletag :ex_resilience

  # Uses redis-server on port 6398 from test_helper.exs

  describe "individual layers through facade" do
    test "circuit breaker passes through when closed" do
      {:ok, r} =
        Resilience.start_link(
          port: 6398,
          circuit_breaker: [failure_threshold: 3]
        )

      assert {:ok, "PONG"} = Resilience.command(r, ["PING"])

      info = Resilience.info(r)
      assert :circuit_breaker in info.layers
      assert info.circuit_breaker.state == :closed

      Resilience.stop(r)
    end

    test "retry succeeds on first attempt" do
      {:ok, r} =
        Resilience.start_link(
          port: 6398,
          retry: [max_attempts: 3]
        )

      assert {:ok, "PONG"} = Resilience.command(r, ["PING"])

      Resilience.stop(r)
    end

    test "retry does not retry Redis app errors" do
      {:ok, r} =
        Resilience.start_link(
          port: 6398,
          retry: [max_attempts: 3]
        )

      Connection.command(r |> resilience_conn(), ["SET", "str", "notanumber"])

      # INCR on a string produces a Redis error, not a connection error
      assert {:error, %Redis.Error{}} = Resilience.command(r, ["INCR", "str"])

      Resilience.stop(r)
    end

    test "coalesce deduplicates concurrent identical requests" do
      {:ok, r} =
        Resilience.start_link(
          port: 6398,
          coalesce: true
        )

      Resilience.command(r, ["SET", "coal_key", "coal_val"])

      tasks =
        for _ <- 1..5 do
          Task.async(fn -> Resilience.command(r, ["GET", "coal_key"]) end)
        end

      results = Enum.map(tasks, &Task.await/1)
      assert Enum.all?(results, &(&1 == {:ok, "coal_val"}))

      Resilience.stop(r)
    end

    test "bulkhead allows requests within limit" do
      {:ok, r} =
        Resilience.start_link(
          port: 6398,
          bulkhead: [max_concurrent: 10]
        )

      assert {:ok, "PONG"} = Resilience.command(r, ["PING"])

      info = Resilience.info(r)
      assert :bulkhead in info.layers

      Resilience.stop(r)
    end
  end

  describe "composed stack" do
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

  # Helper to get the underlying connection from a resilience wrapper
  # (via GenServer state inspection)
  defp resilience_conn(r) do
    state = :sys.get_state(r)
    state.conn
  end
end

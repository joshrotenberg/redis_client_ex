defmodule Redis.Connection.PoolTest do
  use ExUnit.Case, async: false

  alias Redis.Connection.Pool

  # Uses redis-server on port 6398 from test_helper.exs

  describe "basic operations" do
    test "start pool and run commands" do
      {:ok, pool} = Pool.start_link(pool_size: 3, port: 6398)

      assert {:ok, "PONG"} = Pool.command(pool, ["PING"])
      assert {:ok, "OK"} = Pool.command(pool, ["SET", "pool_key", "pool_val"])
      assert {:ok, "pool_val"} = Pool.command(pool, ["GET", "pool_key"])

      Pool.stop(pool)
    end

    test "pipeline through pool" do
      {:ok, pool} = Pool.start_link(pool_size: 3, port: 6398)

      {:ok, results} =
        Pool.pipeline(pool, [
          ["SET", "pp_a", "1"],
          ["SET", "pp_b", "2"],
          ["GET", "pp_a"],
          ["GET", "pp_b"]
        ])

      assert results == ["OK", "OK", "1", "2"]

      Pool.stop(pool)
    end

    test "transaction through pool" do
      {:ok, pool} = Pool.start_link(pool_size: 3, port: 6398)

      {:ok, results} =
        Pool.transaction(pool, [
          ["INCR", "pool_tx"],
          ["INCR", "pool_tx"]
        ])

      assert results == [1, 2]

      Pool.stop(pool)
    end
  end

  describe "pool management" do
    test "info returns pool state" do
      {:ok, pool} = Pool.start_link(pool_size: 5, port: 6398)

      info = Pool.info(pool)
      assert info.pool_size == 5
      assert info.active == 5
      assert info.strategy == :round_robin

      Pool.stop(pool)
    end

    test "round-robin distributes across connections" do
      {:ok, pool} = Pool.start_link(pool_size: 3, port: 6398)

      # Run enough commands to cycle through all connections
      for _ <- 1..9 do
        assert {:ok, "PONG"} = Pool.command(pool, ["PING"])
      end

      Pool.stop(pool)
    end

    test "random strategy works" do
      {:ok, pool} = Pool.start_link(pool_size: 3, port: 6398, strategy: :random)

      for _ <- 1..10 do
        assert {:ok, "PONG"} = Pool.command(pool, ["PING"])
      end

      Pool.stop(pool)
    end

    test "rejects invalid pool options" do
      Process.flag(:trap_exit, true)

      assert {:error, {:invalid_pool_size, 0}} = Pool.start_link(pool_size: 0, port: 6398)

      assert {:error, {:invalid_strategy, :least_loaded}} =
               Pool.start_link(pool_size: 1, strategy: :least_loaded, port: 6398)
    end

    test "retries a failed replacement until the pool recovers" do
      {:ok, server} = RedisServerWrapper.Server.start(port: 6466)

      {:ok, pool} =
        Pool.start_link(pool_size: 1, port: 6466, exit_on_disconnection: true, timeout: 200)

      assert %{active: 1} = Pool.info(pool)

      RedisServerWrapper.Server.stop(server)
      wait_until(fn -> Pool.info(pool).active == 0 end)
      assert {:error, :no_connections} = Pool.command(pool, ["PING"])

      restarted = start_server_when_available(6466)

      on_exit(fn ->
        if Process.alive?(restarted), do: RedisServerWrapper.Server.stop(restarted)
      end)

      wait_until(fn -> Pool.info(pool).active == 1 end, 4_000)

      assert {:ok, "PONG"} = Pool.command(pool, ["PING"])
      Pool.stop(pool)
    end
  end

  describe "concurrent usage" do
    test "handles concurrent commands" do
      {:ok, pool} = Pool.start_link(pool_size: 5, port: 6398)

      Pool.command(pool, ["FLUSHDB"])

      # Fire 50 concurrent commands
      tasks =
        for i <- 1..50 do
          Task.async(fn ->
            key = "conc_#{i}"
            Pool.command(pool, ["SET", key, to_string(i)])
            Pool.command(pool, ["GET", key])
          end)
        end

      results = Enum.map(tasks, &Task.await/1)

      # All should succeed
      for {result, i} <- Enum.with_index(results, 1) do
        assert result == {:ok, to_string(i)}
      end

      Pool.stop(pool)
    end
  end

  describe "resilience wrapper compatibility" do
    test "pool works with resilience stack" do
      {:ok, pool} = Pool.start_link(pool_size: 3, port: 6398)

      # The pool accepts 3-tuple messages for resilience compat
      assert {:ok, "PONG"} = GenServer.call(pool, {:command, ["PING"], []})

      assert {:ok, ["OK", "PONG"]} =
               GenServer.call(pool, {:pipeline, [["SET", "x", "1"], ["PING"]], []})

      Pool.stop(pool)
    end
  end

  defp start_server_when_available(port, timeout \\ 4_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_start_server_when_available(port, deadline)
  end

  defp do_start_server_when_available(port, deadline) do
    case RedisServerWrapper.Server.start(port: port) do
      {:ok, server} ->
        server

      {:error, {:port_in_use, ^port, :eaddrinuse}} ->
        if System.monotonic_time(:millisecond) >= deadline do
          flunk("Redis port #{port} was not released before timeout")
        else
          Process.sleep(50)
          do_start_server_when_available(port, deadline)
        end

      {:error, reason} ->
        flunk("failed to restart Redis on port #{port}: #{inspect(reason)}")
    end
  end

  defp wait_until(fun, timeout \\ 2_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait_until(fun, deadline)
  end

  defp do_wait_until(fun, deadline) do
    cond do
      fun.() ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("condition was not met before timeout")

      true ->
        Process.sleep(25)
        do_wait_until(fun, deadline)
    end
  end
end

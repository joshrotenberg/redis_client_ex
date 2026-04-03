defmodule Redis.Connection.EdgeTest do
  use ExUnit.Case, async: false

  alias Redis.Connection
  alias Redis.Connection.Pool

  # Uses redis-server started by test_helper.exs on port 6398 (no auth)
  # and port 6399 (password: "testpass")

  describe "connection with invalid host" do
    test "sync connect to unreachable host fails" do
      Process.flag(:trap_exit, true)

      result =
        Connection.start_link(
          host: "192.0.2.1",
          port: 6398,
          timeout: 500,
          sync_connect: true
        )

      assert {:error, _reason} = result
    end

    test "sync connect to invalid port fails" do
      Process.flag(:trap_exit, true)

      result =
        Connection.start_link(
          host: "127.0.0.1",
          port: 1,
          timeout: 500,
          sync_connect: true
        )

      assert {:error, _reason} = result
    end

    test "async connect to unreachable host stays disconnected" do
      {:ok, conn} =
        Connection.start_link(
          host: "192.0.2.1",
          port: 6398,
          timeout: 500,
          sync_connect: false,
          backoff_initial: 60_000
        )

      Process.sleep(100)

      # Should be alive but not connected
      assert Process.alive?(conn)
      result = Connection.command(conn, ["PING"], timeout: 500)
      assert {:error, %Redis.ConnectionError{reason: :not_connected}} = result

      Connection.stop(conn)
    end
  end

  describe "command on disconnected connection" do
    test "command returns not_connected error" do
      {:ok, conn} =
        Connection.start_link(
          host: "192.0.2.1",
          port: 6398,
          timeout: 500,
          sync_connect: false,
          backoff_initial: 60_000
        )

      Process.sleep(100)

      result = Connection.command(conn, ["PING"], timeout: 500)
      assert {:error, %Redis.ConnectionError{reason: :not_connected}} = result

      Connection.stop(conn)
    end

    test "pipeline returns not_connected error" do
      {:ok, conn} =
        Connection.start_link(
          host: "192.0.2.1",
          port: 6398,
          timeout: 500,
          sync_connect: false,
          backoff_initial: 60_000
        )

      Process.sleep(100)

      result = Connection.pipeline(conn, [["PING"], ["PING"]], timeout: 500)
      assert {:error, %Redis.ConnectionError{reason: :not_connected}} = result

      Connection.stop(conn)
    end

    test "transaction returns not_connected error" do
      {:ok, conn} =
        Connection.start_link(
          host: "192.0.2.1",
          port: 6398,
          timeout: 500,
          sync_connect: false,
          backoff_initial: 60_000
        )

      Process.sleep(100)

      result = Connection.transaction(conn, [["SET", "k", "v"]], timeout: 500)
      assert {:error, %Redis.ConnectionError{reason: :not_connected}} = result

      Connection.stop(conn)
    end

    test "noreply_command returns not_connected error" do
      {:ok, conn} =
        Connection.start_link(
          host: "192.0.2.1",
          port: 6398,
          timeout: 500,
          sync_connect: false,
          backoff_initial: 60_000
        )

      Process.sleep(100)

      result = Connection.noreply_command(conn, ["SET", "k", "v"], timeout: 500)
      assert {:error, %Redis.ConnectionError{reason: :not_connected}} = result

      Connection.stop(conn)
    end

    test "noreply_pipeline returns not_connected error" do
      {:ok, conn} =
        Connection.start_link(
          host: "192.0.2.1",
          port: 6398,
          timeout: 500,
          sync_connect: false,
          backoff_initial: 60_000
        )

      Process.sleep(100)

      result = Connection.noreply_pipeline(conn, [["SET", "k", "v"]], timeout: 500)
      assert {:error, %Redis.ConnectionError{reason: :not_connected}} = result

      Connection.stop(conn)
    end
  end

  describe "pipeline with empty command list" do
    test "empty pipeline times out because no response is expected from server" do
      {:ok, conn} = Connection.start_link(port: 6398)

      # An empty pipeline sends no data to Redis but the caller is queued
      # waiting for 0 decoded responses. Since process_buffer is only
      # triggered by incoming data, the caller never gets a reply and
      # the GenServer.call times out.
      assert catch_exit(Connection.pipeline(conn, [], timeout: 500))

      Connection.stop(conn)
    end
  end

  describe "transaction with empty command list" do
    test "empty transaction sends only MULTI/EXEC and returns empty results" do
      {:ok, conn} = Connection.start_link(port: 6398)
      Connection.command(conn, ["FLUSHDB"])

      # Transaction wraps with MULTI + EXEC, so empty commands list sends
      # [MULTI, EXEC]. EXEC returns empty list.
      result = Connection.transaction(conn, [])
      assert {:ok, []} = result

      # Connection should remain usable
      assert {:ok, "PONG"} = Connection.command(conn, ["PING"])

      Connection.stop(conn)
    end
  end

  describe "pool with pool_size: 1 under concurrent access" do
    test "serialized access through single connection works" do
      {:ok, pool} = Pool.start_link(pool_size: 1, port: 6398)

      Pool.command(pool, ["FLUSHDB"])

      info = Pool.info(pool)
      assert info.pool_size == 1
      assert info.active == 1

      # Run 20 concurrent tasks through a single-connection pool
      tasks =
        for i <- 1..20 do
          Task.async(fn ->
            key = "pool1_#{i}"
            {:ok, "OK"} = Pool.command(pool, ["SET", key, to_string(i)])
            Pool.command(pool, ["GET", key])
          end)
        end

      results = Enum.map(tasks, &Task.await(&1, 10_000))

      for {result, i} <- Enum.with_index(results, 1) do
        assert {:ok, to_string(i)} == result
      end

      Pool.stop(pool)
    end

    test "pipeline and transaction through single-connection pool" do
      {:ok, pool} = Pool.start_link(pool_size: 1, port: 6398)

      Pool.command(pool, ["FLUSHDB"])

      {:ok, results} =
        Pool.pipeline(pool, [
          ["SET", "pa", "1"],
          ["SET", "pb", "2"],
          ["GET", "pa"],
          ["GET", "pb"]
        ])

      assert results == ["OK", "OK", "1", "2"]

      {:ok, tx_results} =
        Pool.transaction(pool, [
          ["INCR", "counter"],
          ["INCR", "counter"]
        ])

      assert tx_results == [1, 2]

      Pool.stop(pool)
    end
  end

  describe "pool startup with bad connection options" do
    test "pool fails to start when connections cannot be established" do
      Process.flag(:trap_exit, true)

      result =
        Pool.start_link(
          pool_size: 3,
          host: "127.0.0.1",
          port: 1,
          timeout: 500,
          sync_connect: true
        )

      assert {:error, _reason} = result
    end

    test "pool with invalid host fails to start" do
      Process.flag(:trap_exit, true)

      result =
        Pool.start_link(
          pool_size: 2,
          host: "192.0.2.1",
          port: 6398,
          timeout: 500,
          sync_connect: true
        )

      assert {:error, _reason} = result
    end
  end

  describe "connection with wrong password on auth-required server" do
    test "fails with auth_failed during HELLO handshake" do
      Process.flag(:trap_exit, true)

      result =
        Connection.start_link(
          port: 6399,
          password: "completely_wrong_password",
          sync_connect: true
        )

      assert {:error, {:auth_failed, _msg}} = result
    end

    test "fails with no password on auth-required server" do
      Process.flag(:trap_exit, true)

      result =
        Connection.start_link(
          port: 6399,
          sync_connect: true
        )

      # Should be either auth_required or auth_failed depending on Redis version
      assert {:error, {auth_error, _msg}} = result
      assert auth_error in [:auth_failed, :auth_required]
    end

    test "pool fails to start with wrong password" do
      Process.flag(:trap_exit, true)

      result =
        Pool.start_link(
          pool_size: 2,
          port: 6399,
          password: "wrong_password",
          sync_connect: true
        )

      assert {:error, {:auth_failed, _}} = result
    end
  end

  describe "connection timeout behavior" do
    test "command with zero timeout causes caller exit" do
      {:ok, conn} = Connection.start_link(port: 6398)

      # A 0ms timeout on GenServer.call should cause an exit
      assert catch_exit(Connection.command(conn, ["PING"], timeout: 0))

      Connection.stop(conn)
    end

    test "pipeline with zero timeout causes caller exit" do
      {:ok, conn} = Connection.start_link(port: 6398)

      assert catch_exit(Connection.pipeline(conn, [["SET", "a", "1"], ["GET", "a"]], timeout: 0))

      Connection.stop(conn)
    end
  end

  describe "exit_on_disconnection option" do
    test "connection with exit_on_disconnection starts and works normally" do
      {:ok, conn} =
        Connection.start_link(
          port: 6398,
          exit_on_disconnection: true,
          sync_connect: true
        )

      assert {:ok, "PONG"} = Connection.command(conn, ["PING"])
      Connection.stop(conn)
    end
  end

  describe "RESP2 protocol edge cases" do
    test "error response through RESP2" do
      {:ok, conn} = Connection.start_link(port: 6398, protocol: :resp2)

      Connection.command(conn, ["SET", "strkey", "notanumber"])
      assert {:error, %Redis.Error{}} = Connection.command(conn, ["INCR", "strkey"])

      Connection.stop(conn)
    end

    test "empty transaction with RESP2" do
      {:ok, conn} = Connection.start_link(port: 6398, protocol: :resp2)

      result = Connection.transaction(conn, [])
      assert {:ok, []} = result

      assert {:ok, "PONG"} = Connection.command(conn, ["PING"])

      Connection.stop(conn)
    end

    test "pipeline with mixed success and error in RESP2" do
      {:ok, conn} = Connection.start_link(port: 6398, protocol: :resp2)

      Connection.command(conn, ["SET", "str", "hello"])

      {:ok, results} =
        Connection.pipeline(conn, [
          ["SET", "x", "1"],
          ["INCR", "str"],
          ["GET", "x"]
        ])

      assert [_, %Redis.Error{}, _] = results

      Connection.stop(conn)
    end
  end

  describe "connection database selection" do
    test "selecting invalid database returns error" do
      Process.flag(:trap_exit, true)

      # Redis typically supports databases 0-15 by default
      result =
        Connection.start_link(
          port: 6398,
          database: 9999,
          sync_connect: true
        )

      assert {:error, {:select_failed, _}} = result
    end
  end

  describe "pool info reflects actual state" do
    test "info reflects pool_size: 1" do
      {:ok, pool} = Pool.start_link(pool_size: 1, port: 6398)

      info = Pool.info(pool)
      assert info.pool_size == 1
      assert info.active == 1
      assert info.strategy == :round_robin

      Pool.stop(pool)
    end

    test "pool with random strategy reports correctly" do
      {:ok, pool} = Pool.start_link(pool_size: 2, port: 6398, strategy: :random)

      info = Pool.info(pool)
      assert info.pool_size == 2
      assert info.active == 2
      assert info.strategy == :random

      Pool.stop(pool)
    end
  end
end

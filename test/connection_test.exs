defmodule RedisEx.ConnectionTest do
  use ExUnit.Case, async: false

  alias RedisEx.Connection

  # Uses redis-server started in test_helper.exs on port 6398 (no auth)
  # and port 6399 (password: "testpass")

  describe "connect" do
    test "connects to redis-server" do
      {:ok, conn} = Connection.start_link(port: 6398)
      assert {:ok, "PONG"} = Connection.command(conn, ["PING"])
      Connection.stop(conn)
    end

    test "connects with password" do
      {:ok, conn} = Connection.start_link(port: 6399, password: "testpass")
      assert {:ok, "PONG"} = Connection.command(conn, ["PING"])
      Connection.stop(conn)
    end

    test "fails with wrong password" do
      Process.flag(:trap_exit, true)
      result = Connection.start_link(port: 6399, password: "wrong")
      assert {:error, {:auth_failed, _}} = result
    end

    test "connects with RESP2 fallback" do
      {:ok, conn} = Connection.start_link(port: 6398, protocol: :resp2)
      assert {:ok, "PONG"} = Connection.command(conn, ["PING"])
      Connection.stop(conn)
    end

    test "connects with database selection" do
      {:ok, conn} = Connection.start_link(port: 6398, database: 1)
      assert {:ok, "PONG"} = Connection.command(conn, ["PING"])
      Connection.stop(conn)
    end

    test "connects with client name" do
      {:ok, conn} = Connection.start_link(port: 6398, client_name: "redis_ex_test")
      assert {:ok, "redis_ex_test"} = Connection.command(conn, ["CLIENT", "GETNAME"])
      Connection.stop(conn)
    end
  end

  describe "command" do
    setup do
      {:ok, conn} = Connection.start_link(port: 6398)
      Connection.command(conn, ["FLUSHDB"])
      {:ok, conn: conn}
    end

    test "SET and GET", %{conn: conn} do
      assert {:ok, "OK"} = Connection.command(conn, ["SET", "mykey", "myvalue"])
      assert {:ok, "myvalue"} = Connection.command(conn, ["GET", "mykey"])
    end

    test "GET nonexistent key returns nil", %{conn: conn} do
      assert {:ok, nil} = Connection.command(conn, ["GET", "nonexistent"])
    end

    test "INCR", %{conn: conn} do
      assert {:ok, 1} = Connection.command(conn, ["INCR", "counter"])
      assert {:ok, 2} = Connection.command(conn, ["INCR", "counter"])
      assert {:ok, 12} = Connection.command(conn, ["INCRBY", "counter", "10"])
    end

    test "DEL returns count", %{conn: conn} do
      Connection.command(conn, ["SET", "a", "1"])
      Connection.command(conn, ["SET", "b", "2"])
      assert {:ok, 2} = Connection.command(conn, ["DEL", "a", "b"])
    end

    test "HSET and HGETALL", %{conn: conn} do
      Connection.command(conn, ["HSET", "myhash", "f1", "v1", "f2", "v2"])
      {:ok, result} = Connection.command(conn, ["HGETALL", "myhash"])

      # RESP3 returns a map, RESP2 returns a flat list
      case result do
        %{} = map ->
          assert map["f1"] == "v1"
          assert map["f2"] == "v2"

        list when is_list(list) ->
          assert list == ["f1", "v1", "f2", "v2"]
      end
    end

    test "LPUSH and LRANGE", %{conn: conn} do
      Connection.command(conn, ["LPUSH", "mylist", "c", "b", "a"])
      assert {:ok, ["a", "b", "c"]} = Connection.command(conn, ["LRANGE", "mylist", "0", "-1"])
    end

    test "SADD and SMEMBERS", %{conn: conn} do
      Connection.command(conn, ["SADD", "myset", "a", "b", "c"])
      {:ok, result} = Connection.command(conn, ["SMEMBERS", "myset"])

      members =
        case result do
          %MapSet{} -> MapSet.to_list(result) |> Enum.sort()
          list -> Enum.sort(list)
        end

      assert members == ["a", "b", "c"]
    end

    test "error response", %{conn: conn} do
      Connection.command(conn, ["SET", "mykey", "notanumber"])
      assert {:error, %RedisEx.Error{}} = Connection.command(conn, ["INCR", "mykey"])
    end

    test "binary-safe values", %{conn: conn} do
      value = "hello\r\nworld\x00binary"
      assert {:ok, "OK"} = Connection.command(conn, ["SET", "binkey", value])
      assert {:ok, ^value} = Connection.command(conn, ["GET", "binkey"])
    end
  end

  describe "pipeline" do
    setup do
      {:ok, conn} = Connection.start_link(port: 6398)
      Connection.command(conn, ["FLUSHDB"])
      {:ok, conn: conn}
    end

    test "sends multiple commands", %{conn: conn} do
      {:ok, results} =
        Connection.pipeline(conn, [
          ["SET", "a", "1"],
          ["SET", "b", "2"],
          ["GET", "a"],
          ["GET", "b"]
        ])

      assert results == ["OK", "OK", "1", "2"]
    end

    test "pipeline with mixed types", %{conn: conn} do
      {:ok, results} =
        Connection.pipeline(conn, [
          ["SET", "x", "hello"],
          ["INCR", "counter"],
          ["GET", "x"],
          ["GET", "nonexistent"]
        ])

      assert results == ["OK", 1, "hello", nil]
    end
  end

  describe "transaction" do
    setup do
      {:ok, conn} = Connection.start_link(port: 6398)
      Connection.command(conn, ["FLUSHDB"])
      {:ok, conn: conn}
    end

    test "MULTI/EXEC transaction", %{conn: conn} do
      {:ok, results} =
        Connection.transaction(conn, [
          ["SET", "tx1", "a"],
          ["SET", "tx2", "b"],
          ["GET", "tx1"]
        ])

      assert results == ["OK", "OK", "a"]
    end

    test "transaction with INCR", %{conn: conn} do
      Connection.command(conn, ["SET", "counter", "0"])

      {:ok, results} =
        Connection.transaction(conn, [
          ["INCR", "counter"],
          ["INCR", "counter"],
          ["INCR", "counter"]
        ])

      assert results == [1, 2, 3]
    end
  end
end

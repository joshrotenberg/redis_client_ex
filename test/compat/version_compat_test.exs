defmodule Redis.VersionCompatTest do
  @moduledoc """
  Version compatibility tests for Redis 6, 7, and 8.

  Run against specific versions via docker-compose:

      docker compose up -d
      REDIS_PORT=6376 mix test test/compat/  # Redis 6
      REDIS_PORT=6377 mix test test/compat/  # Redis 7
      REDIS_PORT=6378 mix test test/compat/  # Redis 8

  Or use the default port (6379 for redis-stack, or 6398 from test_helper).
  """
  use ExUnit.Case, async: false

  alias Redis.Connection

  @moduletag :compat

  @port String.to_integer(System.get_env("REDIS_PORT") || "6398")

  setup do
    {:ok, conn} = Connection.start_link(port: @port)

    on_exit(fn ->
      try do
        Connection.command(conn, ["FLUSHDB"])
        Connection.stop(conn)
      catch
        :exit, _ -> :ok
      end
    end)

    {:ok, conn: conn}
  end

  # -------------------------------------------------------------------
  # Core operations (all versions)
  # -------------------------------------------------------------------

  describe "core CRUD" do
    test "SET and GET", %{conn: conn} do
      assert {:ok, "OK"} = Connection.command(conn, ["SET", "compat:key", "value"])
      assert {:ok, "value"} = Connection.command(conn, ["GET", "compat:key"])
    end

    test "DEL", %{conn: conn} do
      Connection.command(conn, ["SET", "compat:del", "x"])
      assert {:ok, 1} = Connection.command(conn, ["DEL", "compat:del"])
      assert {:ok, nil} = Connection.command(conn, ["GET", "compat:del"])
    end

    test "INCR/DECR", %{conn: conn} do
      assert {:ok, 1} = Connection.command(conn, ["INCR", "compat:counter"])
      assert {:ok, 2} = Connection.command(conn, ["INCR", "compat:counter"])
      assert {:ok, 1} = Connection.command(conn, ["DECR", "compat:counter"])
    end

    test "EXPIRE and TTL", %{conn: conn} do
      Connection.command(conn, ["SET", "compat:ttl", "val"])
      Connection.command(conn, ["EXPIRE", "compat:ttl", "60"])
      {:ok, ttl} = Connection.command(conn, ["TTL", "compat:ttl"])
      assert ttl > 0 and ttl <= 60
    end

    test "hash operations", %{conn: conn} do
      Connection.command(conn, ["HSET", "compat:hash", "f1", "v1", "f2", "v2"])
      {:ok, result} = Connection.command(conn, ["HGETALL", "compat:hash"])
      # RESP3 returns map, RESP2 returns flat list
      assert is_map(result) or is_list(result)
    end

    test "list operations", %{conn: conn} do
      Connection.command(conn, ["RPUSH", "compat:list", "a", "b", "c"])
      {:ok, result} = Connection.command(conn, ["LRANGE", "compat:list", "0", "-1"])
      assert result == ["a", "b", "c"]
    end

    test "set operations", %{conn: conn} do
      Connection.command(conn, ["SADD", "compat:set", "a", "b", "c"])
      {:ok, result} = Connection.command(conn, ["SMEMBERS", "compat:set"])
      members = if is_struct(result, MapSet), do: MapSet.to_list(result), else: result
      assert Enum.sort(members) == ["a", "b", "c"]
    end
  end

  # -------------------------------------------------------------------
  # Pipeline and transactions (all versions)
  # -------------------------------------------------------------------

  describe "pipeline" do
    test "multiple commands in one round-trip", %{conn: conn} do
      {:ok, results} =
        Connection.pipeline(conn, [
          ["SET", "compat:p1", "a"],
          ["SET", "compat:p2", "b"],
          ["GET", "compat:p1"],
          ["GET", "compat:p2"]
        ])

      assert results == ["OK", "OK", "a", "b"]
    end
  end

  describe "transaction" do
    test "MULTI/EXEC", %{conn: conn} do
      {:ok, results} =
        Connection.transaction(conn, [
          ["SET", "compat:tx", "val"],
          ["GET", "compat:tx"]
        ])

      assert results == ["OK", "val"]
    end
  end

  # -------------------------------------------------------------------
  # Protocol negotiation
  # -------------------------------------------------------------------

  describe "protocol" do
    test "connection succeeds (RESP3 or RESP2 fallback)", %{conn: conn} do
      assert {:ok, "PONG"} = Connection.command(conn, ["PING"])
    end

    test "INFO returns server info as string", %{conn: conn} do
      {:ok, info} = Connection.command(conn, ["INFO", "server"])
      assert is_binary(info)
      assert String.contains?(info, "redis_version")
    end

    test "CLIENT INFO shows lib-name on 7.2+", %{conn: conn} do
      case Connection.command(conn, ["CLIENT", "INFO"]) do
        {:ok, info} when is_binary(info) ->
          # Redis 7.2+ should show lib-name
          if String.contains?(info, "lib-name") do
            assert String.contains?(info, "redis_client_ex")
          end

        _ ->
          # Older versions may not support CLIENT INFO
          :ok
      end
    end
  end

  # -------------------------------------------------------------------
  # RESP3-specific behaviors
  # -------------------------------------------------------------------

  describe "RESP3 response types" do
    test "HGETALL returns map (RESP3) or flat list (RESP2)", %{conn: conn} do
      Connection.command(conn, ["HSET", "compat:hmap", "a", "1", "b", "2"])
      {:ok, result} = Connection.command(conn, ["HGETALL", "compat:hmap"])

      case result do
        %{} = map ->
          # RESP3
          assert map["a"] == "1"
          assert map["b"] == "2"

        list when is_list(list) ->
          # RESP2
          assert "a" in list
          assert "1" in list
      end
    end

    test "SMEMBERS returns MapSet (RESP3) or list (RESP2)", %{conn: conn} do
      Connection.command(conn, ["SADD", "compat:sset", "x", "y"])
      {:ok, result} = Connection.command(conn, ["SMEMBERS", "compat:sset"])

      members =
        case result do
          %MapSet{} -> MapSet.to_list(result)
          list when is_list(list) -> list
        end

      assert Enum.sort(members) == ["x", "y"]
    end
  end

  # -------------------------------------------------------------------
  # Version-specific features (graceful degradation)
  # -------------------------------------------------------------------

  describe "version-specific features" do
    test "CLUSTER SHARDS returns error on non-cluster mode", %{conn: conn} do
      result = Connection.command(conn, ["CLUSTER", "SHARDS"])
      # Should get an error, not crash
      assert {:error, %Redis.Error{}} = result
    end

    test "CLIENT SETINFO accepted or rejected gracefully", %{conn: conn} do
      result = Connection.command(conn, ["CLIENT", "SETINFO", "LIB-NAME", "test"])

      case result do
        {:ok, "OK"} -> :ok
        {:error, %Redis.Error{}} -> :ok
      end
    end
  end
end

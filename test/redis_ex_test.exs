defmodule RedisTest do
  use ExUnit.Case, async: false

  # Uses redis-server started in test_helper.exs on port 6398

  describe "top-level API" do
    setup do
      {:ok, conn} = Redis.start_link(port: 6398)
      Redis.command(conn, ["FLUSHDB"])
      {:ok, conn: conn}
    end

    test "command/2", %{conn: conn} do
      assert {:ok, "OK"} = Redis.command(conn, ["SET", "k", "v"])
      assert {:ok, "v"} = Redis.command(conn, ["GET", "k"])
    end

    test "command!/2", %{conn: conn} do
      assert "OK" = Redis.command!(conn, ["SET", "k", "v"])
      assert "v" = Redis.command!(conn, ["GET", "k"])
    end

    test "command!/2 raises on error", %{conn: conn} do
      Redis.command(conn, ["SET", "k", "notnum"])

      assert_raise RuntimeError, ~r/Redis error/, fn ->
        Redis.command!(conn, ["INCR", "k"])
      end
    end

    test "pipeline/2", %{conn: conn} do
      assert {:ok, ["OK", 1]} =
               Redis.pipeline(conn, [
                 ["SET", "a", "1"],
                 ["INCR", "b"]
               ])
    end

    test "transaction/2", %{conn: conn} do
      assert {:ok, [1, 2]} =
               Redis.transaction(conn, [
                 ["INCR", "c"],
                 ["INCR", "c"]
               ])
    end
  end
end

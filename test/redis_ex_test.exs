defmodule RedisExTest do
  use ExUnit.Case, async: false

  # Uses redis-server started in test_helper.exs on port 6398

  describe "top-level API" do
    setup do
      {:ok, conn} = RedisEx.start_link(port: 6398)
      RedisEx.command(conn, ["FLUSHDB"])
      {:ok, conn: conn}
    end

    test "command/2", %{conn: conn} do
      assert {:ok, "OK"} = RedisEx.command(conn, ["SET", "k", "v"])
      assert {:ok, "v"} = RedisEx.command(conn, ["GET", "k"])
    end

    test "command!/2", %{conn: conn} do
      assert "OK" = RedisEx.command!(conn, ["SET", "k", "v"])
      assert "v" = RedisEx.command!(conn, ["GET", "k"])
    end

    test "command!/2 raises on error", %{conn: conn} do
      RedisEx.command(conn, ["SET", "k", "notnum"])

      assert_raise RuntimeError, ~r/RedisEx error/, fn ->
        RedisEx.command!(conn, ["INCR", "k"])
      end
    end

    test "pipeline/2", %{conn: conn} do
      assert {:ok, ["OK", 1]} =
               RedisEx.pipeline(conn, [
                 ["SET", "a", "1"],
                 ["INCR", "b"]
               ])
    end

    test "transaction/2", %{conn: conn} do
      assert {:ok, [1, 2]} =
               RedisEx.transaction(conn, [
                 ["INCR", "c"],
                 ["INCR", "c"]
               ])
    end
  end
end

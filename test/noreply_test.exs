defmodule RedisEx.NoreplyTest do
  use ExUnit.Case, async: false

  alias RedisEx.Connection

  # Uses redis-server on port 6398 from test_helper.exs

  describe "noreply_command" do
    setup do
      {:ok, conn} = Connection.start_link(port: 6398)
      Connection.command(conn, ["FLUSHDB"])
      {:ok, conn: conn}
    end

    test "sends command without reply", %{conn: conn} do
      assert :ok = Connection.noreply_command(conn, ["SET", "noreply_key", "value"])

      # Verify the command actually executed
      assert {:ok, "value"} = Connection.command(conn, ["GET", "noreply_key"])
    end

    test "connection still works after noreply", %{conn: conn} do
      :ok = Connection.noreply_command(conn, ["INCR", "nr_counter"])
      :ok = Connection.noreply_command(conn, ["INCR", "nr_counter"])
      :ok = Connection.noreply_command(conn, ["INCR", "nr_counter"])

      # Regular commands still work
      assert {:ok, "PONG"} = Connection.command(conn, ["PING"])
      assert {:ok, "3"} = Connection.command(conn, ["GET", "nr_counter"])
    end
  end

  describe "noreply_pipeline" do
    setup do
      {:ok, conn} = Connection.start_link(port: 6398)
      Connection.command(conn, ["FLUSHDB"])
      {:ok, conn: conn}
    end

    test "sends multiple commands without replies", %{conn: conn} do
      assert :ok =
               Connection.noreply_pipeline(conn, [
                 ["SET", "np_a", "1"],
                 ["SET", "np_b", "2"],
                 ["INCR", "np_c"]
               ])

      assert {:ok, "1"} = Connection.command(conn, ["GET", "np_a"])
      assert {:ok, "2"} = Connection.command(conn, ["GET", "np_b"])
      assert {:ok, "1"} = Connection.command(conn, ["GET", "np_c"])
    end
  end
end

defmodule Redis.WatchTransactionTest do
  use ExUnit.Case, async: false

  alias Redis.Connection

  # Uses redis-server on port 6398 from test_helper.exs

  setup do
    {:ok, conn} = Connection.start_link(port: 6398)

    on_exit(fn ->
      case Connection.start_link(port: 6398) do
        {:ok, cleanup} ->
          Connection.command(cleanup, [
            "DEL",
            "watch:key",
            "watch:a",
            "watch:b",
            "watch:counter"
          ])

          Connection.stop(cleanup)

        _ ->
          :ok
      end
    end)

    {:ok, conn: conn}
  end

  describe "watch_transaction/4" do
    test "basic optimistic locking transaction succeeds", %{conn: conn} do
      Connection.command(conn, ["SET", "watch:key", "100"])

      result =
        Connection.watch_transaction(conn, ["watch:key"], fn c ->
          {:ok, val} = Connection.command(c, ["GET", "watch:key"])
          new_val = String.to_integer(val) + 50
          [["SET", "watch:key", to_string(new_val)]]
        end)

      assert {:ok, ["OK"]} = result
      assert {:ok, "150"} = Connection.command(conn, ["GET", "watch:key"])
    end

    test "multiple watched keys", %{conn: conn} do
      Connection.command(conn, ["SET", "watch:a", "10"])
      Connection.command(conn, ["SET", "watch:b", "20"])

      result =
        Connection.watch_transaction(conn, ["watch:a", "watch:b"], fn c ->
          {:ok, a} = Connection.command(c, ["GET", "watch:a"])
          {:ok, b} = Connection.command(c, ["GET", "watch:b"])
          sum = String.to_integer(a) + String.to_integer(b)
          [["SET", "watch:a", to_string(sum)]]
        end)

      assert {:ok, ["OK"]} = result
      assert {:ok, "30"} = Connection.command(conn, ["GET", "watch:a"])
    end

    test "retries on conflict from concurrent modification", %{conn: conn} do
      Connection.command(conn, ["SET", "watch:counter", "0"])

      # Start a second connection to cause a conflict
      {:ok, conn2} = Connection.start_link(port: 6398)

      attempt = :counters.new(1, [:atomics])

      result =
        Connection.watch_transaction(conn, ["watch:counter"], fn c ->
          :counters.add(attempt, 1, 1)
          {:ok, val} = Connection.command(c, ["GET", "watch:counter"])
          current = String.to_integer(val)

          # On the first attempt, have conn2 modify the key to trigger conflict
          if :counters.get(attempt, 1) == 1 do
            Connection.command(conn2, ["SET", "watch:counter", "999"])
          end

          [["SET", "watch:counter", to_string(current + 1)]]
        end)

      assert {:ok, ["OK"]} = result
      # After conflict, it retried and set to 999 + 1 = 1000
      assert {:ok, "1000"} = Connection.command(conn, ["GET", "watch:counter"])
      assert :counters.get(attempt, 1) == 2

      Connection.stop(conn2)
    end

    test "returns :watch_conflict after max retries exhausted", %{conn: conn} do
      Connection.command(conn, ["SET", "watch:key", "0"])
      {:ok, conn2} = Connection.start_link(port: 6398)

      result =
        Connection.watch_transaction(
          conn,
          ["watch:key"],
          fn c ->
            {:ok, _} = Connection.command(c, ["GET", "watch:key"])
            # Always cause a conflict
            Connection.command(conn2, ["INCR", "watch:key"])
            [["SET", "watch:key", "done"]]
          end,
          max_retries: 2
        )

      assert {:error, :watch_conflict} = result
      Connection.stop(conn2)
    end

    test "user function can abort the transaction", %{conn: conn} do
      Connection.command(conn, ["SET", "watch:key", "0"])

      result =
        Connection.watch_transaction(conn, ["watch:key"], fn c ->
          {:ok, val} = Connection.command(c, ["GET", "watch:key"])

          if String.to_integer(val) < 100 do
            {:abort, :insufficient_balance}
          else
            [["DECRBY", "watch:key", "100"]]
          end
        end)

      assert {:error, {:aborted, :insufficient_balance}} = result
      # Key should be unchanged
      assert {:ok, "0"} = Connection.command(conn, ["GET", "watch:key"])
    end

    test "works through the top-level Redis module", %{conn: conn} do
      Redis.command(conn, ["SET", "watch:key", "hello"])

      result =
        Redis.watch_transaction(conn, ["watch:key"], fn c ->
          {:ok, val} = Redis.command(c, ["GET", "watch:key"])
          [["SET", "watch:key", val <> " world"]]
        end)

      assert {:ok, ["OK"]} = result
      assert {:ok, "hello world"} = Redis.command(conn, ["GET", "watch:key"])
    end
  end
end

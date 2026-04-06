defmodule Redis.Integration.HookTest do
  use ExUnit.Case, async: false

  defmodule BlockAllHook do
    use Redis.Hook

    @impl Redis.Hook
    def before_command(_command, _ctx), do: {:error, :forbidden}

    @impl Redis.Hook
    def before_pipeline(_commands, _ctx), do: {:error, :forbidden}
  end

  defmodule CountingHook do
    @moduledoc false
    use Redis.Hook

    # Uses a persistent ETS table keyed by :hook_counter to count invocations.

    def reset do
      try do
        :ets.delete(:hook_counter)
      rescue
        ArgumentError -> :ok
      end

      :ets.new(:hook_counter, [:named_table, :public, :set])
      :ets.insert(:hook_counter, {:before_command, 0})
      :ets.insert(:hook_counter, {:after_command, 0})
      :ets.insert(:hook_counter, {:before_pipeline, 0})
      :ets.insert(:hook_counter, {:after_pipeline, 0})
      :ok
    end

    def cleanup do
      :ets.delete(:hook_counter)
    rescue
      ArgumentError -> :ok
    end

    def count(key) do
      [{^key, val}] = :ets.lookup(:hook_counter, key)
      val
    end

    @impl Redis.Hook
    def before_command(command, _ctx) do
      :ets.update_counter(:hook_counter, :before_command, 1)
      {:ok, command}
    end

    @impl Redis.Hook
    def after_command(_command, result, _ctx) do
      :ets.update_counter(:hook_counter, :after_command, 1)
      result
    end

    @impl Redis.Hook
    def before_pipeline(commands, _ctx) do
      :ets.update_counter(:hook_counter, :before_pipeline, 1)
      {:ok, commands}
    end

    @impl Redis.Hook
    def after_pipeline(_commands, result, _ctx) do
      :ets.update_counter(:hook_counter, :after_pipeline, 1)
      result
    end
  end

  describe "blocking hooks" do
    test "before_command hook blocks execution" do
      {:ok, conn} =
        Redis.Connection.start_link(port: 6398, hooks: [BlockAllHook])

      assert {:error, :forbidden} = Redis.Connection.command(conn, ["GET", "key"])
      Redis.Connection.stop(conn)
    end

    test "before_pipeline hook blocks execution" do
      {:ok, conn} =
        Redis.Connection.start_link(port: 6398, hooks: [BlockAllHook])

      assert {:error, :forbidden} =
               Redis.Connection.pipeline(conn, [["GET", "a"], ["GET", "b"]])

      Redis.Connection.stop(conn)
    end

    test "before_transaction hook blocks execution" do
      {:ok, conn} =
        Redis.Connection.start_link(port: 6398, hooks: [BlockAllHook])

      assert {:error, :forbidden} =
               Redis.Connection.transaction(conn, [["SET", "a", "1"], ["SET", "b", "2"]])

      Redis.Connection.stop(conn)
    end
  end

  describe "counting hooks on commands" do
    test "before and after hooks fire on command" do
      CountingHook.reset()

      {:ok, conn} =
        Redis.Connection.start_link(port: 6398, hooks: [CountingHook])

      assert {:ok, "PONG"} = Redis.Connection.command(conn, ["PING"])

      assert CountingHook.count(:before_command) >= 1
      assert CountingHook.count(:after_command) >= 1

      Redis.Connection.stop(conn)
      CountingHook.cleanup()
    end

    test "multiple commands accumulate counts" do
      CountingHook.reset()

      {:ok, conn} =
        Redis.Connection.start_link(port: 6398, hooks: [CountingHook])

      Redis.Connection.command(conn, ["PING"])
      Redis.Connection.command(conn, ["PING"])
      Redis.Connection.command(conn, ["PING"])

      assert CountingHook.count(:before_command) >= 3
      assert CountingHook.count(:after_command) >= 3

      Redis.Connection.stop(conn)
      CountingHook.cleanup()
    end
  end

  describe "counting hooks on pipelines" do
    test "before and after hooks fire on pipeline" do
      CountingHook.reset()

      {:ok, conn} =
        Redis.Connection.start_link(port: 6398, hooks: [CountingHook])

      assert {:ok, _} = Redis.Connection.pipeline(conn, [["PING"], ["PING"]])

      assert CountingHook.count(:before_pipeline) >= 1
      assert CountingHook.count(:after_pipeline) >= 1

      Redis.Connection.stop(conn)
      CountingHook.cleanup()
    end

    test "before and after hooks fire on transaction" do
      CountingHook.reset()

      {:ok, conn} =
        Redis.Connection.start_link(port: 6398, hooks: [CountingHook])

      assert {:ok, _} =
               Redis.Connection.transaction(conn, [["SET", "tx_a", "1"], ["SET", "tx_b", "2"]])

      # Transactions use pipeline hooks
      assert CountingHook.count(:before_pipeline) >= 1
      assert CountingHook.count(:after_pipeline) >= 1

      Redis.Connection.stop(conn)
      CountingHook.cleanup()
    end
  end

  describe "no hooks" do
    test "connection with no hooks works normally" do
      {:ok, conn} = Redis.Connection.start_link(port: 6398)

      assert {:ok, "OK"} = Redis.Connection.command(conn, ["SET", "hook_test", "val"])
      assert {:ok, "val"} = Redis.Connection.command(conn, ["GET", "hook_test"])
      Redis.Connection.command(conn, ["DEL", "hook_test"])

      Redis.Connection.stop(conn)
    end

    test "hooks option defaults to empty list" do
      {:ok, conn} = Redis.Connection.start_link(port: 6398)

      assert {:ok, "PONG"} = Redis.Connection.command(conn, ["PING"])

      Redis.Connection.stop(conn)
    end
  end
end

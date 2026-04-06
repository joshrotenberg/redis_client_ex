defmodule Redis.HookTest do
  use ExUnit.Case, async: true

  alias Redis.Hook

  # -- Test hook modules --------------------------------------------------

  defmodule PassthroughHook do
    use Redis.Hook
  end

  defmodule UpcaseHook do
    use Redis.Hook

    @impl Redis.Hook
    def before_command(command, _ctx) do
      {:ok, Enum.map(command, &String.upcase/1)}
    end
  end

  defmodule BlockingHook do
    use Redis.Hook

    @impl Redis.Hook
    def before_command(_command, _ctx) do
      {:error, :blocked}
    end
  end

  defmodule ResultRewriteHook do
    use Redis.Hook

    @impl Redis.Hook
    def after_command(_command, {:ok, value}, _ctx) when is_binary(value) do
      {:ok, String.upcase(value)}
    end

    def after_command(_command, result, _ctx), do: result
  end

  defmodule PipelineBlockHook do
    use Redis.Hook

    @impl Redis.Hook
    def before_pipeline(_commands, _ctx) do
      {:error, :pipeline_blocked}
    end
  end

  defmodule PipelineCountHook do
    use Redis.Hook

    @impl Redis.Hook
    def after_pipeline(_commands, {:ok, results}, _ctx) do
      {:ok, Enum.map(results, fn _ -> :counted end)}
    end

    def after_pipeline(_commands, result, _ctx), do: result
  end

  # -- Tests ---------------------------------------------------------------

  describe "use Redis.Hook defaults" do
    test "before_command passes through" do
      assert {:ok, ["GET", "key"]} = PassthroughHook.before_command(["GET", "key"], %{})
    end

    test "after_command passes through" do
      assert {:ok, "val"} = PassthroughHook.after_command(["GET", "key"], {:ok, "val"}, %{})
    end

    test "before_pipeline passes through" do
      cmds = [["GET", "a"], ["GET", "b"]]
      assert {:ok, ^cmds} = PassthroughHook.before_pipeline(cmds, %{})
    end

    test "after_pipeline passes through" do
      assert {:ok, ["a", "b"]} =
               PassthroughHook.after_pipeline([["GET", "a"]], {:ok, ["a", "b"]}, %{})
    end
  end

  describe "run_before_command/3" do
    test "empty hooks list passes command through" do
      assert {:ok, ["GET", "key"]} = Hook.run_before_command([], ["GET", "key"], %{})
    end

    test "single hook can transform command" do
      assert {:ok, ["GET", "KEY"]} =
               Hook.run_before_command([UpcaseHook], ["GET", "key"], %{})
    end

    test "hooks run in order" do
      # PassthroughHook first (no change), then UpcaseHook
      assert {:ok, ["GET", "KEY"]} =
               Hook.run_before_command([PassthroughHook, UpcaseHook], ["GET", "key"], %{})
    end

    test "short-circuits on error" do
      # BlockingHook returns error, UpcaseHook should never run
      assert {:error, :blocked} =
               Hook.run_before_command([BlockingHook, UpcaseHook], ["GET", "key"], %{})
    end
  end

  describe "run_after_command/4" do
    test "empty hooks list passes result through" do
      assert {:ok, "val"} = Hook.run_after_command([], ["GET", "key"], {:ok, "val"}, %{})
    end

    test "single hook transforms result" do
      assert {:ok, "VAL"} =
               Hook.run_after_command([ResultRewriteHook], ["GET", "key"], {:ok, "val"}, %{})
    end

    test "after hooks run in reverse order" do
      # ResultRewriteHook upcases, PassthroughHook is no-op
      # Reverse order: PassthroughHook runs first (no-op), then ResultRewriteHook upcases
      assert {:ok, "VAL"} =
               Hook.run_after_command(
                 [ResultRewriteHook, PassthroughHook],
                 ["GET", "key"],
                 {:ok, "val"},
                 %{}
               )
    end
  end

  describe "run_before_pipeline/3" do
    test "empty hooks passes through" do
      cmds = [["GET", "a"]]
      assert {:ok, ^cmds} = Hook.run_before_pipeline([], cmds, %{})
    end

    test "short-circuits on error" do
      assert {:error, :pipeline_blocked} =
               Hook.run_before_pipeline([PipelineBlockHook], [["GET", "a"]], %{})
    end
  end

  describe "run_after_pipeline/4" do
    test "empty hooks passes through" do
      assert {:ok, ["a"]} = Hook.run_after_pipeline([], [["GET", "a"]], {:ok, ["a"]}, %{})
    end

    test "transforms results" do
      assert {:ok, [:counted, :counted]} =
               Hook.run_after_pipeline(
                 [PipelineCountHook],
                 [["GET", "a"], ["GET", "b"]],
                 {:ok, ["a", "b"]},
                 %{}
               )
    end
  end

  describe "build_context/1" do
    test "builds context from state map" do
      state = %{host: "myhost", port: 6380, database: 2}
      assert %{host: "myhost", port: 6380, database: 2} = Hook.build_context(state)
    end

    test "uses defaults for missing fields" do
      assert %{host: "127.0.0.1", port: 6379, database: 0} = Hook.build_context(%{})
    end
  end
end

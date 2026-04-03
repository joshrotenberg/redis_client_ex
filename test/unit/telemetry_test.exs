defmodule Redis.TelemetryTest do
  use ExUnit.Case, async: false

  alias Redis.Telemetry

  setup do
    test_pid = self()
    handler_id = "test-telemetry-#{:erlang.unique_integer([:positive])}"

    on_exit(fn ->
      try do
        :telemetry.detach(handler_id)
      catch
        _, _ -> :ok
      end
    end)

    {:ok, test_pid: test_pid, handler_id: handler_id}
  end

  describe "execute/3" do
    test "emits a telemetry event", %{test_pid: test_pid, handler_id: handler_id} do
      :telemetry.attach(
        handler_id,
        [:redis_ex, :test, :event],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      Telemetry.execute([:redis_ex, :test, :event], %{value: 42}, %{key: "test"})

      assert_receive {:telemetry, [:redis_ex, :test, :event], %{value: 42}, %{key: "test"}}, 1000
    end

    test "does not crash if telemetry is not used" do
      # Just verify it doesn't raise
      assert Telemetry.execute([:redis_ex, :unused, :event], %{}, %{}) == :ok
    end
  end

  describe "span/3" do
    test "emits start and stop events around a function", %{
      test_pid: test_pid,
      handler_id: handler_id
    } do
      :telemetry.attach_many(
        handler_id,
        [
          [:redis_ex, :test, :start],
          [:redis_ex, :test, :stop]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      result = Telemetry.span([:redis_ex, :test], %{op: "ping"}, fn -> :pong end)

      assert result == :pong

      assert_receive {:telemetry, [:redis_ex, :test, :start], %{system_time: _}, %{op: "ping"}},
                     1000

      assert_receive {:telemetry, [:redis_ex, :test, :stop], %{duration: duration},
                      %{op: "ping"}},
                     1000

      assert is_integer(duration)
      assert duration >= 0
    end

    test "emits exception event on error", %{test_pid: test_pid, handler_id: handler_id} do
      :telemetry.attach_many(
        handler_id,
        [
          [:redis_ex, :test, :start],
          [:redis_ex, :test, :exception]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      assert_raise RuntimeError, "boom", fn ->
        Telemetry.span([:redis_ex, :test], %{op: "fail"}, fn ->
          raise "boom"
        end)
      end

      assert_receive {:telemetry, [:redis_ex, :test, :start], _, _}, 1000

      assert_receive {:telemetry, [:redis_ex, :test, :exception], %{duration: _},
                      %{kind: :error, reason: %RuntimeError{}}},
                     1000
    end

    test "returns the function result", %{handler_id: _handler_id} do
      result = Telemetry.span([:redis_ex, :noop], %{}, fn -> {:ok, 42} end)
      assert result == {:ok, 42}
    end
  end

  describe "attach_default_handler/0" do
    test "attaches without error" do
      # May already be attached from a previous test, detach first
      try do
        :telemetry.detach("redis-ex-default")
      catch
        _, _ -> :ok
      end

      assert Telemetry.attach_default_handler() == :ok
      :telemetry.detach("redis-ex-default")
    end
  end

  describe "format_duration (via default handler)" do
    test "default handler processes connect event without crash" do
      try do
        :telemetry.detach("redis-ex-default")
      catch
        _, _ -> :ok
      end

      Telemetry.attach_default_handler()

      # Emit a connect event to exercise the handler
      Telemetry.execute(
        [:redis_ex, :connection, :connect],
        %{duration: 1_000_000},
        %{host: "127.0.0.1", port: 6379}
      )

      # Emit a pipeline stop event
      Telemetry.execute(
        [:redis_ex, :pipeline, :stop],
        %{duration: 500_000},
        %{commands: [["PING"]]}
      )

      # Emit a disconnect event
      Telemetry.execute(
        [:redis_ex, :connection, :disconnect],
        %{},
        %{host: "127.0.0.1", port: 6379, reason: :econnrefused}
      )

      :telemetry.detach("redis-ex-default")
    end
  end
end

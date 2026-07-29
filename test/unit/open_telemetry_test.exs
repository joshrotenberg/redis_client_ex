defmodule Redis.OpenTelemetryTest do
  use ExUnit.Case, async: false

  alias Redis.OpenTelemetry

  setup do
    # Ensure clean state
    try do
      OpenTelemetry.detach()
    catch
      _, _ -> :ok
    end

    on_exit(fn ->
      try do
        OpenTelemetry.detach()
      catch
        _, _ -> :ok
      end
    end)

    :ok
  end

  describe "attach/0" do
    test "attaches telemetry handlers" do
      assert OpenTelemetry.attach() == :ok
    end

    test "returns error when already attached" do
      assert OpenTelemetry.attach() == :ok
      assert {:error, :already_exists} = OpenTelemetry.attach()
    end
  end

  describe "detach/0" do
    test "detaches telemetry handlers after attach" do
      :ok = OpenTelemetry.attach()
      assert OpenTelemetry.detach() == :ok
    end

    test "returns error when not attached" do
      assert {:error, :not_found} = OpenTelemetry.detach()
    end
  end

  describe "handle_event/4" do
    setup do
      :ok = OpenTelemetry.attach()
      :ok
    end

    test "handles pipeline start event without error" do
      Redis.Telemetry.execute(
        [:redis_ex, :pipeline, :start],
        %{system_time: System.system_time()},
        %{commands: [["GET", "mykey"]]}
      )
    end

    test "handles pipeline stop event without error" do
      # Start then stop
      Redis.Telemetry.execute(
        [:redis_ex, :pipeline, :start],
        %{system_time: System.system_time()},
        %{commands: [["SET", "mykey", "value"]]}
      )

      Redis.Telemetry.execute(
        [:redis_ex, :pipeline, :stop],
        %{duration: 1000},
        %{commands: [["SET", "mykey", "value"]]}
      )
    end

    test "handles pipeline exception event without error" do
      Redis.Telemetry.execute(
        [:redis_ex, :pipeline, :start],
        %{system_time: System.system_time()},
        %{commands: [["GET", "mykey"]]}
      )

      Redis.Telemetry.execute(
        [:redis_ex, :pipeline, :exception],
        %{duration: 500},
        %{commands: [["GET", "mykey"]], kind: :error, reason: :timeout}
      )
    end

    test "handles multi-command pipeline" do
      commands = [["GET", "key1"], ["SET", "key2", "val"], ["DEL", "key3"]]

      Redis.Telemetry.execute(
        [:redis_ex, :pipeline, :start],
        %{system_time: System.system_time()},
        %{commands: commands}
      )

      Redis.Telemetry.execute(
        [:redis_ex, :pipeline, :stop],
        %{duration: 2000},
        %{commands: commands}
      )
    end
  end

  describe "span creation with OTel test setup" do
    setup do
      # Configure OTel with simple processor for testing
      :application.set_env(:opentelemetry, :tracer, :otel_tracer_default)

      :application.set_env(
        :opentelemetry,
        :processors,
        [{:otel_simple_processor, %{exporter: {:otel_exporter_pid, self()}}}]
      )

      # Restart the OTel tracer provider to pick up config
      if Process.whereis(:opentelemetry_app) ||
           Application.started_applications()
           |> Enum.any?(fn {app, _, _} -> app == :opentelemetry end) do
        Application.stop(:opentelemetry)
        Application.start(:opentelemetry)
      end

      :ok = OpenTelemetry.attach()
      :ok
    end

    test "creates a span for a single command" do
      operation_id = make_ref()
      span_key = {{Redis.OpenTelemetry, :span}, operation_id}

      Redis.Telemetry.execute(
        [:redis_ex, :pipeline, :start],
        %{system_time: System.system_time()},
        %{operation_id: operation_id, commands: [["GET", "mykey"]]}
      )

      refute is_nil(Process.get(span_key))

      Redis.Telemetry.execute(
        [:redis_ex, :pipeline, :stop],
        %{duration: 1000},
        %{operation_id: operation_id, commands: [["GET", "mykey"]]}
      )

      assert is_nil(Process.get(span_key))
    end

    test "correlates overlapping operations with their own spans" do
      first = make_ref()
      second = make_ref()
      first_key = {{Redis.OpenTelemetry, :span}, first}
      second_key = {{Redis.OpenTelemetry, :span}, second}

      Redis.Telemetry.execute(
        [:redis_ex, :pipeline, :start],
        %{system_time: System.system_time()},
        %{operation_id: first, commands: [["GET", "first"]]}
      )

      Redis.Telemetry.execute(
        [:redis_ex, :pipeline, :start],
        %{system_time: System.system_time()},
        %{operation_id: second, commands: [["GET", "second"]]}
      )

      first_span = Process.get(first_key)
      second_span = Process.get(second_key)
      refute is_nil(first_span)
      refute is_nil(second_span)
      refute first_span == second_span

      Redis.Telemetry.execute(
        [:redis_ex, :pipeline, :stop],
        %{duration: 1000},
        %{operation_id: first, commands: [["GET", "first"]]}
      )

      assert is_nil(Process.get(first_key))
      refute is_nil(Process.get(second_key))

      Redis.Telemetry.execute(
        [:redis_ex, :pipeline, :exception],
        %{duration: 1000},
        %{operation_id: second, commands: [["GET", "second"]], reason: :closed}
      )

      assert is_nil(Process.get(second_key))
    end
  end
end

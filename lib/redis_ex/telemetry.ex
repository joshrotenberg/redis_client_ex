defmodule RedisEx.Telemetry do
  @moduledoc """
  Telemetry events emitted by RedisEx.

  ## Events

    * `[:redis_ex, :connection, :connect]` - successful connection
      * Measurements: `%{duration: native_time}`
      * Metadata: `%{host: host, port: port}`

    * `[:redis_ex, :connection, :disconnect]` - connection lost
      * Measurements: `%{}`
      * Metadata: `%{host: host, port: port, reason: reason}`

    * `[:redis_ex, :pipeline, :start]` - pipeline/command started
      * Measurements: `%{system_time: native_time}`
      * Metadata: `%{commands: commands}`

    * `[:redis_ex, :pipeline, :stop]` - pipeline/command completed
      * Measurements: `%{duration: native_time}`
      * Metadata: `%{commands: commands}`

    * `[:redis_ex, :pipeline, :exception]` - pipeline/command failed
      * Measurements: `%{duration: native_time}`
      * Metadata: `%{commands: commands, kind: kind, reason: reason}`

  ## Usage

  Attach a handler:

      :telemetry.attach("redis-logger", [:redis_ex, :pipeline, :stop], fn name, measurements, metadata, _config ->
        Logger.info("Redis \#{inspect(name)} took \#{measurements.duration}ns for \#{length(metadata.commands)} commands")
      end, nil)

  Or use the built-in default handler for logging:

      RedisEx.Telemetry.attach_default_handler()
  """

  require Logger

  @doc """
  Emits a telemetry event. Wraps `:telemetry.execute/3` with a no-op
  fallback if telemetry is not available.
  """
  def execute(event, measurements, metadata \\ %{}) do
    :telemetry.execute(event, measurements, metadata)
  rescue
    UndefinedFunctionError -> :ok
  end

  @doc """
  Spans a telemetry event around a function call.
  """
  def span(event_prefix, metadata, fun) do
    start_time = System.monotonic_time()
    execute(event_prefix ++ [:start], %{system_time: System.system_time()}, metadata)

    try do
      result = fun.()
      duration = System.monotonic_time() - start_time
      execute(event_prefix ++ [:stop], %{duration: duration}, metadata)
      result
    rescue
      e ->
        duration = System.monotonic_time() - start_time

        execute(
          event_prefix ++ [:exception],
          %{duration: duration},
          Map.merge(metadata, %{kind: :error, reason: e})
        )

        reraise e, __STACKTRACE__
    end
  end

  @doc """
  Attaches a default log handler for all RedisEx telemetry events.
  """
  def attach_default_handler do
    events = [
      [:redis_ex, :connection, :connect],
      [:redis_ex, :connection, :disconnect],
      [:redis_ex, :pipeline, :stop]
    ]

    :telemetry.attach_many("redis-ex-default", events, &handle_event/4, nil)
  rescue
    UndefinedFunctionError ->
      Logger.warning("RedisEx.Telemetry: :telemetry not available")
      :ok
  end

  defp handle_event([:redis_ex, :connection, :connect], measurements, metadata, _config) do
    Logger.info("RedisEx connected to #{metadata.host}:#{metadata.port} in #{format_duration(measurements.duration)}")
  end

  defp handle_event([:redis_ex, :connection, :disconnect], _measurements, metadata, _config) do
    Logger.warning("RedisEx disconnected from #{metadata.host}:#{metadata.port}: #{inspect(metadata.reason)}")
  end

  defp handle_event([:redis_ex, :pipeline, :stop], measurements, metadata, _config) do
    count = length(Map.get(metadata, :commands, []))
    Logger.debug("RedisEx pipeline (#{count} commands) completed in #{format_duration(measurements.duration)}")
  end

  defp format_duration(duration) do
    us = System.convert_time_unit(duration, :native, :microsecond)

    cond do
      us < 1000 -> "#{us}µs"
      us < 1_000_000 -> "#{Float.round(us / 1000, 1)}ms"
      true -> "#{Float.round(us / 1_000_000, 2)}s"
    end
  end
end

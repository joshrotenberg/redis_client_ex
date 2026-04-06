if Code.ensure_loaded?(OpenTelemetry) do
  defmodule Redis.OpenTelemetry do
    @moduledoc """
    Optional OpenTelemetry integration for Redis.

    Creates OTel spans for Redis commands by attaching to the existing
    `:telemetry` events emitted by `Redis.Telemetry`. Requires the
    `:opentelemetry_api` dependency.

    ## Setup

        # In your application startup:
        Redis.OpenTelemetry.attach()

    ## Span Attributes

    Follows the OpenTelemetry semantic conventions for databases:

      * `db.system` - always `"redis"`
      * `db.operation.name` - the Redis command name (e.g. `"GET"`, `"SET"`)
      * `db.statement` - the full command with arguments sanitized
      * `db.redis.database_index` - database index if present in metadata
      * `server.address` - Redis server host if present
      * `server.port` - Redis server port if present

    ## Teardown

        Redis.OpenTelemetry.detach()
    """

    require OpenTelemetry.Tracer, as: Tracer

    @handler_id "redis-ex-opentelemetry"

    @doc """
    Attaches telemetry handlers that create OpenTelemetry spans for Redis commands.
    """
    @spec attach() :: :ok | {:error, :already_exists}
    def attach do
      events = [
        [:redis_ex, :pipeline, :start],
        [:redis_ex, :pipeline, :stop],
        [:redis_ex, :pipeline, :exception]
      ]

      :telemetry.attach_many(@handler_id, events, &handle_event/4, nil)
    rescue
      UndefinedFunctionError -> :ok
    end

    @doc """
    Detaches the OpenTelemetry telemetry handlers.
    """
    @spec detach() :: :ok | {:error, :not_found}
    def detach do
      :telemetry.detach(@handler_id)
    rescue
      UndefinedFunctionError -> :ok
    end

    @doc false
    def handle_event([:redis_ex, :pipeline, :start], _measurements, metadata, _config) do
      commands = Map.get(metadata, :commands, [])
      span_name = span_name(commands)
      attributes = build_attributes(commands, metadata)

      Tracer.start_span(span_name, %{attributes: attributes})
    end

    def handle_event([:redis_ex, :pipeline, :stop], _measurements, _metadata, _config) do
      Tracer.end_span()
    end

    def handle_event([:redis_ex, :pipeline, :exception], _measurements, metadata, _config) do
      reason = Map.get(metadata, :reason)

      Tracer.set_status(:error, inspect(reason))
      Tracer.end_span()
    end

    defp span_name(commands) do
      case commands do
        [single] -> "redis #{operation_name(single)}"
        commands when is_list(commands) -> "redis pipeline (#{length(commands)} commands)"
        _ -> "redis"
      end
    end

    defp operation_name([cmd | _]) when is_binary(cmd), do: String.upcase(cmd)
    defp operation_name(_), do: "UNKNOWN"

    defp build_attributes(commands, metadata) do
      attrs = %{
        "db.system": "redis",
        "db.operation.name": extract_operation(commands),
        "db.statement": sanitize_statement(commands)
      }

      attrs = maybe_put(attrs, :"server.address", Map.get(metadata, :host))
      attrs = maybe_put(attrs, :"server.port", Map.get(metadata, :port))
      maybe_put(attrs, :"db.redis.database_index", Map.get(metadata, :database))
    end

    defp extract_operation(commands) do
      case commands do
        [single] -> operation_name(single)
        commands when is_list(commands) -> "PIPELINE"
        _ -> "UNKNOWN"
      end
    end

    defp sanitize_statement(commands) do
      Enum.map_join(commands, "; ", &sanitize_command/1)
    end

    defp sanitize_command([cmd | args]) when is_binary(cmd) do
      sanitized_args =
        args
        |> Enum.with_index()
        |> Enum.map(fn
          {arg, 0} -> arg
          {_arg, _idx} -> "?"
        end)

      Enum.join([String.upcase(cmd) | sanitized_args], " ")
    end

    defp sanitize_command(other), do: inspect(other)

    defp maybe_put(attrs, _key, nil), do: attrs
    defp maybe_put(attrs, key, value), do: Map.put(attrs, key, value)
  end
end

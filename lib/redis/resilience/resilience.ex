defmodule Redis.Resilience do
  @moduledoc """
  Composable resilience wrapper for Redis connections.

  Stacks circuit breaker, retry, coalescing, and bulkhead patterns
  around a Redis connection. All patterns are optional -- include only
  what you need.

  Requires `{:ex_resilience, "~> 0.4"}` in your dependencies.

  ## Usage

      # Full resilience stack
      {:ok, r} = Redis.Resilience.start_link(
        port: 6379,
        retry: [max_attempts: 3, backoff: :exponential],
        circuit_breaker: [failure_threshold: 5, reset_timeout: 5_000],
        coalesce: true,
        bulkhead: [max_concurrent: 50]
      )

      # Same API as a regular connection
      Redis.Resilience.command(r, ["GET", "key"])
      Redis.Resilience.pipeline(r, [["GET", "a"], ["GET", "b"]])

      # Inspect the stack
      Redis.Resilience.info(r)

  ## Composition Order (inside -> outside)

      Connection -> Retry -> CircuitBreaker -> Coalesce -> Bulkhead
                   ^ retries transient errors
                          ^ fails fast when unhealthy
                                       ^ deduplicates concurrent requests
                                                    ^ limits concurrency

  ## Options

    * All `Redis.Connection` options (host, port, password, etc.)
    * `:retry` - keyword opts for `ExResilience.Retry`, or `false`
    * `:circuit_breaker` - keyword opts for `ExResilience.CircuitBreaker`, or `false`
    * `:coalesce` - `true` or keyword opts, or `false`
    * `:bulkhead` - keyword opts for `ExResilience.Bulkhead`, or `false`
    * `:chaos` - keyword opts for `ExResilience.Chaos` (test only), or `false`
  """

  @ex_resilience_available Code.ensure_loaded?(ExResilience)

  use GenServer

  alias Redis.Connection

  require Logger

  defstruct [:conn, :pipeline, :pipeline_name, :layers]

  # -------------------------------------------------------------------
  # Public API
  # -------------------------------------------------------------------

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Executes a Redis command through the resilience stack.

  Pipeline calls run in the caller's process so that concurrency-limiting
  layers (bulkhead) work correctly across concurrent callers.
  """
  def command(r, args, opts \\ []) do
    case get_state(r) do
      %{pipeline: nil, conn: conn} ->
        Connection.command(conn, args, opts)

      %{pipeline: pipeline, conn: conn} ->
        call_through_pipeline(pipeline, fn -> Connection.command(conn, args, opts) end, args)
    end
  end

  def pipeline(r, commands, opts \\ []) do
    case get_state(r) do
      %{pipeline: nil, conn: conn} ->
        Connection.pipeline(conn, commands, opts)

      %{pipeline: pipeline, conn: conn} ->
        call_through_pipeline(
          pipeline,
          fn -> Connection.pipeline(conn, commands, opts) end,
          commands
        )
    end
  end

  def transaction(r, commands, opts \\ []) do
    case get_state(r) do
      %{pipeline: nil, conn: conn} ->
        Connection.transaction(conn, commands, opts)

      %{pipeline: pipeline, conn: conn} ->
        call_through_pipeline(
          pipeline,
          fn -> Connection.transaction(conn, commands, opts) end,
          commands
        )
    end
  end

  @doc "Returns info about the resilience stack."
  def info(r), do: GenServer.call(r, :info)

  def stop(r), do: GenServer.stop(r, :normal)

  # -------------------------------------------------------------------
  # GenServer (lifecycle management and state queries only)
  # -------------------------------------------------------------------

  @resilience_keys [:retry, :circuit_breaker, :coalesce, :bulkhead, :chaos]

  @impl true
  def init(opts) do
    {resilience_opts, conn_opts} = split_opts(opts)

    if has_resilience_opts?(resilience_opts) do
      init_with_resilience(conn_opts, resilience_opts)
    else
      init_plain(conn_opts)
    end
  end

  defp split_opts(opts) do
    Enum.reduce(@resilience_keys, {%{}, opts}, fn key, {res, remaining} ->
      {val, remaining} = Keyword.pop(remaining, key, false)
      {Map.put(res, key, val), remaining}
    end)
  end

  defp has_resilience_opts?(res) do
    Enum.any?(@resilience_keys, fn key -> Map.get(res, key) != false end)
  end

  defp init_plain(opts) do
    with {:ok, conn} <- Connection.start_link(opts) do
      {:ok, %__MODULE__{conn: conn, pipeline: nil, pipeline_name: nil, layers: []}}
    end
  end

  defp init_with_resilience(opts, res) do
    with {:ok, conn} <- Connection.start_link(opts) do
      init_with_pipeline(
        conn,
        res.retry,
        res.circuit_breaker,
        res.coalesce,
        res.bulkhead,
        res.chaos
      )
    end
  end

  @impl true
  def handle_call(:info, _from, %{pipeline: nil} = state) do
    {:reply, %{layers: [], circuit_breaker: nil, bulkhead: nil}, state}
  end

  if @ex_resilience_available do
    def handle_call(:info, _from, state) do
      layer_names = Enum.map(state.layers, fn {layer, _} -> layer end)

      cb_info =
        if :circuit_breaker in layer_names do
          cb_name = ExResilience.Pipeline.child_name(state.pipeline_name, :circuit_breaker)
          ExResilience.CircuitBreaker.get_info(cb_name)
        end

      bh_info =
        if :bulkhead in layer_names do
          bh_name = ExResilience.Pipeline.child_name(state.pipeline_name, :bulkhead)

          %{
            active: ExResilience.Bulkhead.active_count(bh_name),
            queued: ExResilience.Bulkhead.queue_length(bh_name)
          }
        end

      {:reply, %{layers: layer_names, circuit_breaker: cb_info, bulkhead: bh_info}, state}
    end
  end

  @impl true
  def terminate(_reason, state) do
    if state.pipeline do
      stop_pipeline(state)
    end

    safe_stop(state.conn)
    :ok
  end

  # -------------------------------------------------------------------
  # State access (for caller-process pipeline execution)
  # -------------------------------------------------------------------

  defp get_state(r), do: :sys.get_state(r)

  # -------------------------------------------------------------------
  # Pipeline construction (only compiled when ex_resilience is available)
  # -------------------------------------------------------------------

  if @ex_resilience_available do
    defp init_with_pipeline(conn, retry_opts, cb_opts, coalesce_opts, bulkhead_opts, chaos_opts) do
      pipeline_name = :"redis_resilience_#{:erlang.unique_integer([:positive])}"

      pipeline = ExResilience.new(pipeline_name)

      # Build layers outside-in: Bulkhead -> Coalesce -> CircuitBreaker -> Retry -> Chaos
      pipeline = maybe_add_layer(pipeline, :bulkhead, bulkhead_opts)
      pipeline = maybe_add_layer(pipeline, :coalesce, coalesce_opts)
      pipeline = maybe_add_layer(pipeline, :circuit_breaker, cb_opts)
      pipeline = maybe_add_layer(pipeline, :retry, retry_opts)
      pipeline = maybe_add_layer(pipeline, :chaos, chaos_opts)

      pipeline = ExResilience.Pipeline.with_classifier(pipeline, Redis.Resilience.ErrorClassifier)

      {:ok, _pids} = ExResilience.start(pipeline)

      {:ok,
       %__MODULE__{
         conn: conn,
         pipeline: pipeline,
         pipeline_name: pipeline_name,
         layers: pipeline.layers
       }}
    end

    defp maybe_add_layer(pipeline, _layer, false), do: pipeline

    defp maybe_add_layer(pipeline, :coalesce, true) do
      maybe_add_layer(pipeline, :coalesce, [])
    end

    defp maybe_add_layer(pipeline, :coalesce, opts) when is_list(opts) do
      key_fn = fn -> :erlang.phash2(Process.get(:redis_resilience_args)) end
      ExResilience.add(pipeline, :coalesce, Keyword.put_new(opts, :key, key_fn))
    end

    defp maybe_add_layer(pipeline, :circuit_breaker, opts) when is_list(opts) do
      # Sync half_open_max_calls with success_threshold so enough probes are allowed
      opts =
        case Keyword.get(opts, :success_threshold) do
          nil -> opts
          n -> Keyword.put_new(opts, :half_open_max_calls, n)
        end

      ExResilience.add(pipeline, :circuit_breaker, opts)
    end

    defp maybe_add_layer(pipeline, :retry, opts) when is_list(opts) do
      opts = translate_jitter(opts)
      ExResilience.add(pipeline, :retry, opts)
    end

    defp maybe_add_layer(pipeline, layer, opts) when is_list(opts) do
      ExResilience.add(pipeline, layer, opts)
    end

    defp translate_jitter(opts) do
      case Keyword.get(opts, :jitter) do
        nil -> opts
        j when is_float(j) and j == 0.0 -> Keyword.put(opts, :jitter, false)
        j when is_float(j) -> opts
        _ -> opts
      end
    end

    defp call_through_pipeline(pipeline, fun, args) do
      Process.put(:redis_resilience_args, args)
      result = ExResilience.call(pipeline, fun)
      Process.delete(:redis_resilience_args)
      unwrap_result(result)
    end

    defp unwrap_result({:ok, {:ok, _} = inner}), do: inner
    defp unwrap_result({:ok, {:error, _} = inner}), do: inner
    defp unwrap_result({:ok, result}), do: {:ok, result}
    defp unwrap_result({:error, _} = err), do: err
    defp unwrap_result(other), do: other

    defp stop_pipeline(state) do
      for {layer, _opts} <- state.layers do
        name = ExResilience.Pipeline.child_name(state.pipeline_name, layer)

        if Process.whereis(name) do
          GenServer.stop(name, :normal)
        end
      end
    catch
      :exit, _ -> :ok
    end
  else
    defp init_with_pipeline(_, _, _, _, _, _) do
      {:stop,
       {:missing_dependency,
        "Resilience options require {:ex_resilience, \"~> 0.4\"} in your deps"}}
    end

    defp call_through_pipeline(_, _, _), do: {:error, :ex_resilience_not_available}
  end

  defp safe_stop(pid) do
    GenServer.stop(pid, :normal)
  catch
    :exit, _ -> :ok
  end
end

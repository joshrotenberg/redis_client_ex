defmodule Redis.Resilience do
  @moduledoc """
  Composable resilience wrapper for Redis connections.

  Stacks circuit breaker, retry, coalescing, and bulkhead patterns
  around a Redis connection. All patterns are optional — include only
  what you need.

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

  ## Composition Order (inside → outside)

      Connection → Retry → CircuitBreaker → Coalesce → Bulkhead
                   ↑ retries transient errors
                          ↑ fails fast when unhealthy
                                       ↑ deduplicates concurrent requests
                                                    ↑ limits concurrency

  ## Options

    * All `Redis.Connection` options (host, port, password, etc.)
    * `:retry` - keyword opts for `Redis.Resilience.Retry`, or `false`
    * `:circuit_breaker` - keyword opts for `Redis.Resilience.CircuitBreaker`, or `false`
    * `:coalesce` - `true` or keyword opts for `Redis.Resilience.Coalesce`, or `false`
    * `:bulkhead` - keyword opts for `Redis.Resilience.Bulkhead`, or `false`
  """

  use GenServer

  alias Redis.Connection
  alias Redis.Resilience.{CircuitBreaker, Retry, Coalesce, Bulkhead}

  require Logger

  defstruct [:conn, :retry, :circuit_breaker, :coalesce, :bulkhead, :outer]

  # -------------------------------------------------------------------
  # Public API
  # -------------------------------------------------------------------

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  def command(r, args, opts \\ []), do: GenServer.call(r, {:command, args, opts}, 30_000)

  def pipeline(r, commands, opts \\ []),
    do: GenServer.call(r, {:pipeline, commands, opts}, 30_000)

  def transaction(r, commands, opts \\ []),
    do: GenServer.call(r, {:transaction, commands, opts}, 30_000)

  @doc "Returns info about the resilience stack."
  def info(r), do: GenServer.call(r, :info)

  def stop(r), do: GenServer.stop(r, :normal)

  # -------------------------------------------------------------------
  # GenServer
  # -------------------------------------------------------------------

  @impl true
  def init(opts) do
    # Separate resilience opts from connection opts
    {retry_opts, opts} = Keyword.pop(opts, :retry, false)
    {cb_opts, opts} = Keyword.pop(opts, :circuit_breaker, false)
    {coalesce_opts, opts} = Keyword.pop(opts, :coalesce, false)
    {bulkhead_opts, opts} = Keyword.pop(opts, :bulkhead, false)

    # Start the base connection
    with {:ok, conn} <- Connection.start_link(opts) do
      # Build the wrapper chain: Connection → Retry → CircuitBreaker → Coalesce → Bulkhead
      current = conn
      layers = %{conn: conn}

      {current, layers} = maybe_add_retry(current, layers, retry_opts)
      {current, layers} = maybe_add_circuit_breaker(current, layers, cb_opts)
      {current, layers} = maybe_add_coalesce(current, layers, coalesce_opts)
      {current, layers} = maybe_add_bulkhead(current, layers, bulkhead_opts)

      state = %__MODULE__{
        conn: conn,
        retry: layers[:retry],
        circuit_breaker: layers[:circuit_breaker],
        coalesce: layers[:coalesce],
        bulkhead: layers[:bulkhead],
        outer: current
      }

      {:ok, state}
    end
  end

  @impl true
  def handle_call({:command, args, opts}, _from, state) do
    result = dispatch(state.outer, :command, [args, opts])
    {:reply, result, state}
  end

  def handle_call({:pipeline, commands, opts}, _from, state) do
    result = dispatch(state.outer, :pipeline, [commands, opts])
    {:reply, result, state}
  end

  def handle_call({:transaction, commands, opts}, _from, state) do
    result = dispatch(state.outer, :transaction, [commands, opts])
    {:reply, result, state}
  end

  def handle_call(:info, _from, state) do
    layers = []
    layers = if state.bulkhead, do: [:bulkhead | layers], else: layers
    layers = if state.coalesce, do: [:coalesce | layers], else: layers
    layers = if state.circuit_breaker, do: [:circuit_breaker | layers], else: layers
    layers = if state.retry, do: [:retry | layers], else: layers

    cb_state =
      if state.circuit_breaker do
        CircuitBreaker.state(state.circuit_breaker)
      end

    bh_state =
      if state.bulkhead do
        Bulkhead.state(state.bulkhead)
      end

    info = %{
      layers: Enum.reverse(layers),
      circuit_breaker: cb_state,
      bulkhead: bh_state
    }

    {:reply, info, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Stop layers in reverse order
    if state.bulkhead, do: safe_stop(state.bulkhead)
    if state.coalesce, do: safe_stop(state.coalesce)
    if state.circuit_breaker, do: safe_stop(state.circuit_breaker)
    if state.retry, do: safe_stop(state.retry)
    safe_stop(state.conn)
    :ok
  end

  # -------------------------------------------------------------------
  # Layer construction
  # -------------------------------------------------------------------

  defp maybe_add_retry(current, layers, false), do: {current, layers}

  defp maybe_add_retry(current, layers, opts) when is_list(opts) do
    {:ok, pid} = Retry.start_link(Keyword.put(opts, :conn, current))
    {pid, Map.put(layers, :retry, pid)}
  end

  defp maybe_add_circuit_breaker(current, layers, false), do: {current, layers}

  defp maybe_add_circuit_breaker(current, layers, opts) when is_list(opts) do
    {:ok, pid} = CircuitBreaker.start_link(Keyword.put(opts, :conn, current))
    {pid, Map.put(layers, :circuit_breaker, pid)}
  end

  defp maybe_add_coalesce(current, layers, false), do: {current, layers}

  defp maybe_add_coalesce(current, layers, true) do
    maybe_add_coalesce(current, layers, [])
  end

  defp maybe_add_coalesce(current, layers, opts) when is_list(opts) do
    {:ok, pid} = Coalesce.start_link(Keyword.put(opts, :conn, current))
    {pid, Map.put(layers, :coalesce, pid)}
  end

  defp maybe_add_bulkhead(current, layers, false), do: {current, layers}

  defp maybe_add_bulkhead(current, layers, opts) when is_list(opts) do
    {:ok, pid} = Bulkhead.start_link(Keyword.put(opts, :conn, current))
    {pid, Map.put(layers, :bulkhead, pid)}
  end

  # -------------------------------------------------------------------
  # Dispatch
  # -------------------------------------------------------------------

  # Dispatch to the outermost layer — could be Connection, Retry, CB, Coalesce, or Bulkhead
  defp dispatch(pid, :command, [args, opts]) do
    # Determine what module the pid belongs to by trying each API
    # Since they all use GenServer.call with the same message format,
    # we can just use the module that matches the pid
    GenServer.call(pid, {:command, args, opts}, 30_000)
  end

  defp dispatch(pid, :pipeline, [commands, opts]) do
    GenServer.call(pid, {:pipeline, commands, opts}, 30_000)
  end

  defp dispatch(pid, :transaction, [commands, opts]) do
    GenServer.call(pid, {:transaction, commands, opts}, 30_000)
  end

  defp safe_stop(pid) do
    try do
      GenServer.stop(pid, :normal)
    catch
      :exit, _ -> :ok
    end
  end
end

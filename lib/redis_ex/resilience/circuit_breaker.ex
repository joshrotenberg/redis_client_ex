defmodule RedisEx.Resilience.CircuitBreaker do
  @moduledoc """
  Circuit breaker for Redis connections.

  Monitors failure rates and trips open when Redis becomes unhealthy,
  failing fast instead of piling up timeouts.

  ## States

      closed → open → half_open → closed
                ↑         │
                └─────────┘ (on failure)

  - **Closed**: Normal operation. Failures are counted.
  - **Open**: All requests fail immediately with `{:error, :circuit_open}`.
  - **Half-open**: A single probe request is allowed through. Success → closed, failure → open.

  ## Usage

      {:ok, cb} = CircuitBreaker.start_link(
        conn: conn,
        failure_threshold: 5,
        reset_timeout: 5_000
      )

      CircuitBreaker.command(cb, ["GET", "key"])

  ## Options

    * `:conn` - underlying RedisEx.Connection (required)
    * `:failure_threshold` - failures before opening (default: 5)
    * `:reset_timeout` - ms to wait before half-open probe (default: 5_000)
    * `:success_threshold` - successes in half-open to close (default: 1)
    * `:name` - GenServer name
  """

  use GenServer

  require Logger

  defstruct [
    :conn,
    :failure_threshold,
    :reset_timeout,
    :success_threshold,
    :reset_timer,
    state: :closed,
    failure_count: 0,
    success_count: 0
  ]

  # -------------------------------------------------------------------
  # Public API
  # -------------------------------------------------------------------

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  def command(cb, args, opts \\ []), do: GenServer.call(cb, {:command, args, opts})
  def pipeline(cb, commands, opts \\ []), do: GenServer.call(cb, {:pipeline, commands, opts})
  def transaction(cb, commands, opts \\ []), do: GenServer.call(cb, {:transaction, commands, opts})

  @doc "Returns the current circuit state."
  def state(cb), do: GenServer.call(cb, :state)

  @doc "Manually resets the circuit to closed."
  def reset(cb), do: GenServer.call(cb, :reset)

  def stop(cb), do: GenServer.stop(cb, :normal)

  # -------------------------------------------------------------------
  # GenServer
  # -------------------------------------------------------------------

  @impl true
  def init(opts) do
    conn = Keyword.fetch!(opts, :conn)

    state = %__MODULE__{
      conn: conn,
      failure_threshold: Keyword.get(opts, :failure_threshold, 5),
      reset_timeout: Keyword.get(opts, :reset_timeout, 5_000),
      success_threshold: Keyword.get(opts, :success_threshold, 1)
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:command, _args, _opts} = msg, _from, state) do
    execute(state, fn -> GenServer.call(state.conn, msg, 30_000) end)
  end

  def handle_call({:pipeline, _commands, _opts} = msg, _from, state) do
    execute(state, fn -> GenServer.call(state.conn, msg, 30_000) end)
  end

  def handle_call({:transaction, _commands, _opts} = msg, _from, state) do
    execute(state, fn -> GenServer.call(state.conn, msg, 30_000) end)
  end

  def handle_call(:state, _from, state) do
    info = %{
      state: state.state,
      failure_count: state.failure_count,
      success_count: state.success_count
    }

    {:reply, info, state}
  end

  def handle_call(:reset, _from, state) do
    {:reply, :ok, %{state | state: :closed, failure_count: 0, success_count: 0}}
  end

  @impl true
  def handle_info(:half_open, state) do
    Logger.debug("RedisEx.CircuitBreaker: transitioning to half_open")
    {:noreply, %{state | state: :half_open, reset_timer: nil}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # -------------------------------------------------------------------
  # State machine
  # -------------------------------------------------------------------

  defp execute(%{state: :open} = state, _fun) do
    {:reply, {:error, :circuit_open}, state}
  end

  defp execute(state, fun) do
    case fun.() do
      {:ok, _} = result ->
        {:reply, result, record_success(state)}

      {:error, %RedisEx.ConnectionError{}} = result ->
        {:reply, result, record_failure(state)}

      # Redis errors (WRONGTYPE, etc.) are not connection failures
      other ->
        {:reply, other, record_success(state)}
    end
  end

  defp record_success(%{state: :half_open} = state) do
    new_count = state.success_count + 1

    if new_count >= state.success_threshold do
      Logger.debug("RedisEx.CircuitBreaker: closing circuit")
      %{state | state: :closed, failure_count: 0, success_count: 0}
    else
      %{state | success_count: new_count}
    end
  end

  defp record_success(%{state: :closed} = state) do
    %{state | failure_count: 0}
  end

  defp record_failure(%{state: :closed} = state) do
    new_count = state.failure_count + 1

    if new_count >= state.failure_threshold do
      Logger.warning("RedisEx.CircuitBreaker: opening circuit after #{new_count} failures")
      trip_open(state)
    else
      %{state | failure_count: new_count}
    end
  end

  defp record_failure(%{state: :half_open} = state) do
    Logger.debug("RedisEx.CircuitBreaker: half_open probe failed, re-opening")
    trip_open(state)
  end

  defp trip_open(state) do
    if state.reset_timer, do: Process.cancel_timer(state.reset_timer)
    timer = Process.send_after(self(), :half_open, state.reset_timeout)
    %{state | state: :open, failure_count: 0, success_count: 0, reset_timer: timer}
  end
end

defmodule RedisEx.Resilience.Retry do
  @moduledoc """
  Retry wrapper for Redis commands with configurable backoff.

  Automatically retries commands that fail with connection errors.
  Redis application errors (WRONGTYPE, etc.) are NOT retried.

  ## Usage

      {:ok, retried} = Retry.start_link(
        conn: conn,
        max_attempts: 3,
        backoff: :exponential,
        base_delay: 100
      )

      Retry.command(retried, ["GET", "key"])

  ## Options

    * `:conn` - underlying connection (required)
    * `:max_attempts` - total attempts including first (default: 3)
    * `:backoff` - `:exponential`, `:linear`, `:fixed` (default: `:exponential`)
    * `:base_delay` - base delay in ms (default: 100)
    * `:max_delay` - cap on delay ms (default: 5_000)
    * `:jitter` - add randomization, 0.0-1.0 (default: 0.1)
    * `:retry_on` - custom predicate `(error -> boolean)` for retryable errors
  """

  use GenServer

  require Logger

  defstruct [:conn, :max_attempts, :backoff, :base_delay, :max_delay, :jitter, :retry_on]

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  def command(retry, args, opts \\ []), do: GenServer.call(retry, {:command, args, opts}, 30_000)
  def pipeline(retry, commands, opts \\ []), do: GenServer.call(retry, {:pipeline, commands, opts}, 30_000)
  def transaction(retry, commands, opts \\ []), do: GenServer.call(retry, {:transaction, commands, opts}, 30_000)
  def stop(retry), do: GenServer.stop(retry, :normal)

  @impl true
  def init(opts) do
    state = %__MODULE__{
      conn: Keyword.fetch!(opts, :conn),
      max_attempts: Keyword.get(opts, :max_attempts, 3),
      backoff: Keyword.get(opts, :backoff, :exponential),
      base_delay: Keyword.get(opts, :base_delay, 100),
      max_delay: Keyword.get(opts, :max_delay, 5_000),
      jitter: Keyword.get(opts, :jitter, 0.1),
      retry_on: Keyword.get(opts, :retry_on, &default_retry_on/1)
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:command, args, opts}, _from, state) do
    result = with_retry(state, fn -> call_inner(state.conn, {:command, args, opts}) end)
    {:reply, result, state}
  end

  def handle_call({:pipeline, commands, opts}, _from, state) do
    result = with_retry(state, fn -> call_inner(state.conn, {:pipeline, commands, opts}) end)
    {:reply, result, state}
  end

  def handle_call({:transaction, commands, opts}, _from, state) do
    result = with_retry(state, fn -> call_inner(state.conn, {:transaction, commands, opts}) end)
    {:reply, result, state}
  end

  # -------------------------------------------------------------------
  # Retry logic
  # -------------------------------------------------------------------

  defp with_retry(state, fun), do: attempt(state, fun, 1)

  defp attempt(state, fun, attempt_num) do
    case fun.() do
      {:error, error} = result ->
        if attempt_num < state.max_attempts and state.retry_on.(error) do
          delay = compute_delay(state, attempt_num)
          Logger.debug("RedisEx.Retry: attempt #{attempt_num} failed, retrying in #{delay}ms")
          Process.sleep(delay)
          attempt(state, fun, attempt_num + 1)
        else
          result
        end

      result ->
        result
    end
  end

  defp compute_delay(state, attempt) do
    base =
      case state.backoff do
        :exponential -> state.base_delay * :math.pow(2, attempt - 1)
        :linear -> state.base_delay * attempt
        :fixed -> state.base_delay
      end

    base = min(base, state.max_delay)

    # Add jitter
    if state.jitter > 0 do
      jitter_range = base * state.jitter
      base + :rand.uniform() * jitter_range * 2 - jitter_range
    else
      base
    end
    |> round()
    |> max(1)
  end

  defp call_inner(pid, msg), do: GenServer.call(pid, msg, 30_000)

  defp default_retry_on(%RedisEx.ConnectionError{}), do: true
  defp default_retry_on(_), do: false
end

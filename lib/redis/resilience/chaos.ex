defmodule Redis.Resilience.Chaos do
  @moduledoc """
  Fault injection wrapper for testing resilience patterns. **Test only.**

  Injects random errors and latency to simulate Redis failures.

  ## Usage

      {:ok, conn} = Redis.Connection.start_link(port: 6379)
      {:ok, chaos} = Redis.Resilience.Chaos.start_link(
        conn: conn,
        error_rate: 0.3,           # 30% of requests fail
        latency_rate: 0.2,         # 20% of requests get delayed
        min_latency: 100,          # 100-500ms delay
        max_latency: 500
      )

      # Use like a normal connection — some will fail randomly
      Redis.Resilience.Chaos.command(chaos, ["GET", "key"])

  ## Options

    * `:conn` - underlying connection (required)
    * `:error_rate` - fraction of requests to fail, 0.0-1.0 (default: 0.1)
    * `:latency_rate` - fraction of requests to delay, 0.0-1.0 (default: 0.0)
    * `:min_latency` - minimum injected delay ms (default: 50)
    * `:max_latency` - maximum injected delay ms (default: 500)
    * `:error_fn` - custom error generator `(-> error)` (default: connection error)
    * `:seed` - random seed for deterministic chaos (default: random)
  """

  use GenServer

  defstruct [:conn, :error_rate, :latency_rate, :min_latency, :max_latency, :error_fn]

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  def command(chaos, args, opts \\ []), do: GenServer.call(chaos, {:command, args, opts}, 30_000)
  def pipeline(chaos, cmds, opts \\ []), do: GenServer.call(chaos, {:pipeline, cmds, opts}, 30_000)
  def stop(chaos), do: GenServer.stop(chaos, :normal)

  @impl true
  def init(opts) do
    seed = Keyword.get(opts, :seed)
    if seed, do: :rand.seed(:exsss, {seed, seed, seed})

    state = %__MODULE__{
      conn: Keyword.fetch!(opts, :conn),
      error_rate: Keyword.get(opts, :error_rate, 0.1),
      latency_rate: Keyword.get(opts, :latency_rate, 0.0),
      min_latency: Keyword.get(opts, :min_latency, 50),
      max_latency: Keyword.get(opts, :max_latency, 500),
      error_fn: Keyword.get(opts, :error_fn, fn ->
        {:error, %Redis.ConnectionError{reason: :chaos_injected}}
      end)
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:command, args, opts}, _from, state) do
    result = maybe_inject(state, fn -> GenServer.call(state.conn, {:command, args, opts}, 30_000) end)
    {:reply, result, state}
  end

  def handle_call({:pipeline, cmds, opts}, _from, state) do
    result = maybe_inject(state, fn -> GenServer.call(state.conn, {:pipeline, cmds, opts}, 30_000) end)
    {:reply, result, state}
  end

  defp maybe_inject(state, fun) do
    # Inject latency
    if :rand.uniform() < state.latency_rate do
      delay = state.min_latency + :rand.uniform(max(state.max_latency - state.min_latency, 1))
      Process.sleep(delay)
    end

    # Inject error
    if :rand.uniform() < state.error_rate do
      state.error_fn.()
    else
      fun.()
    end
  end
end

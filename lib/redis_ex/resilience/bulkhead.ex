defmodule RedisEx.Resilience.Bulkhead do
  @moduledoc """
  Concurrency limiter (bulkhead) for Redis connections.

  Limits the maximum number of concurrent Redis commands to prevent
  resource exhaustion.

  ## Usage

      {:ok, bh} = Bulkhead.start_link(conn: conn, max_concurrent: 50)
      Bulkhead.command(bh, ["GET", "key"])

  ## Options

    * `:conn` - underlying connection (required)
    * `:max_concurrent` - max concurrent commands (default: 50)
    * `:max_wait` - ms to wait for a slot (default: 5_000). 0 = reject immediately.
  """

  use GenServer

  defstruct [:conn, :max_concurrent, :max_wait, active: 0, queue: :queue.new()]

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  def command(bh, args, opts \\ []), do: GenServer.call(bh, {:command, args, opts}, 30_000)
  def pipeline(bh, commands, opts \\ []), do: GenServer.call(bh, {:pipeline, commands, opts}, 30_000)

  @doc "Returns current bulkhead state."
  def state(bh), do: GenServer.call(bh, :state)

  def stop(bh), do: GenServer.stop(bh, :normal)

  @impl true
  def init(opts) do
    {:ok, %__MODULE__{
      conn: Keyword.fetch!(opts, :conn),
      max_concurrent: Keyword.get(opts, :max_concurrent, 50),
      max_wait: Keyword.get(opts, :max_wait, 5_000)
    }}
  end

  @impl true
  def handle_call({:command, args, opts}, from, state) do
    execute_or_queue(state, from, {:command, args, opts})
  end

  def handle_call({:pipeline, commands, opts}, from, state) do
    execute_or_queue(state, from, {:pipeline, commands, opts})
  end

  def handle_call(:state, _from, state) do
    info = %{
      active: state.active,
      max_concurrent: state.max_concurrent,
      queued: :queue.len(state.queue)
    }

    {:reply, info, state}
  end

  @impl true
  def handle_info({:completed, result, from}, state) do
    GenServer.reply(from, result)
    state = %{state | active: state.active - 1}
    state = drain_queue(state)
    {:noreply, state}
  end

  def handle_info({:wait_timeout, from}, state) do
    # Remove from queue if still there
    queue =
      state.queue
      |> :queue.to_list()
      |> Enum.reject(fn {f, _} -> f == from end)
      |> :queue.from_list()

    GenServer.reply(from, {:error, :bulkhead_full})
    {:noreply, %{state | queue: queue}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # -------------------------------------------------------------------
  # Execution
  # -------------------------------------------------------------------

  defp execute_or_queue(state, from, operation) do
    if state.active < state.max_concurrent do
      state = %{state | active: state.active + 1}
      spawn_execution(state.conn, from, operation)
      {:noreply, state}
    else
      if state.max_wait == 0 do
        {:reply, {:error, :bulkhead_full}, state}
      else
        timer = Process.send_after(self(), {:wait_timeout, from}, state.max_wait)
        queue = :queue.in({from, operation, timer}, state.queue)
        {:noreply, %{state | queue: queue}}
      end
    end
  end

  defp drain_queue(state) do
    if state.active < state.max_concurrent and not :queue.is_empty(state.queue) do
      {{:value, {from, operation, timer}}, queue} = :queue.out(state.queue)
      Process.cancel_timer(timer)
      state = %{state | active: state.active + 1, queue: queue}
      spawn_execution(state.conn, from, operation)
      drain_queue(state)
    else
      state
    end
  end

  defp spawn_execution(conn, from, operation) do
    parent = self()

    spawn(fn ->
      result = GenServer.call(conn, operation, 30_000)
      send(parent, {:completed, result, from})
    end)
  end
end

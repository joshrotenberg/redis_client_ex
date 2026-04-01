defmodule Redis.Resilience.Coalesce do
  @moduledoc """
  Request coalescing (singleflight) for Redis commands.

  When multiple callers request the same key simultaneously, only ONE
  request goes to Redis. All other callers wait and receive the same result.
  Prevents cache stampede / thundering herd.

  ## Usage

      {:ok, coal} = Coalesce.start_link(conn: conn)

      # These three concurrent calls result in ONE Redis GET:
      Task.async(fn -> Coalesce.command(coal, ["GET", "hot_key"]) end)
      Task.async(fn -> Coalesce.command(coal, ["GET", "hot_key"]) end)
      Task.async(fn -> Coalesce.command(coal, ["GET", "hot_key"]) end)

  ## Options

    * `:conn` - underlying connection (required)
    * `:ttl` - ms to keep coalesced result before allowing new request (default: 0)
  """

  use GenServer

  alias Redis.Connection

  defstruct [:conn, :ttl, inflight: %{}]

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  def command(coal, args, opts \\ []), do: GenServer.call(coal, {:command, args, opts}, 30_000)
  def stop(coal), do: GenServer.stop(coal, :normal)

  @impl true
  def init(opts) do
    {:ok,
     %__MODULE__{
       conn: Keyword.fetch!(opts, :conn),
       ttl: Keyword.get(opts, :ttl, 0)
     }}
  end

  @impl true
  def handle_call({:command, args, _opts}, from, state) do
    key = :erlang.phash2(args)

    case Map.get(state.inflight, key) do
      nil ->
        # First caller for this key — we'll execute and notify all waiters
        state = %{state | inflight: Map.put(state.inflight, key, [from])}
        send(self(), {:execute, key, args})
        {:noreply, state}

      waiters ->
        # Already inflight — join the waiters list
        state = %{state | inflight: Map.put(state.inflight, key, [from | waiters])}
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:execute, key, args}, state) do
    result = Connection.command(state.conn, args)

    # Reply to all waiting callers
    case Map.get(state.inflight, key) do
      nil ->
        :ok

      waiters ->
        Enum.each(waiters, fn from -> GenServer.reply(from, result) end)
    end

    state = %{state | inflight: Map.delete(state.inflight, key)}
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end

defmodule RedisEx.Connection.Pool do
  @moduledoc """
  Connection pool for RedisEx.

  Manages N `RedisEx.Connection` processes with round-robin dispatch.
  Dead connections are automatically replaced. Same API as a single connection.

  ## Usage

      {:ok, pool} = RedisEx.Connection.Pool.start_link(
        pool_size: 5,
        host: "localhost",
        port: 6379
      )

      {:ok, "OK"} = RedisEx.Connection.Pool.command(pool, ["SET", "key", "val"])
      {:ok, "val"} = RedisEx.Connection.Pool.command(pool, ["GET", "key"])

  ## Options

    * `:pool_size` - number of connections (default: 5)
    * `:strategy` - `:round_robin` or `:random` (default: `:round_robin`)
    * `:name` - GenServer name
    * All other options are passed to each `RedisEx.Connection`

  ## Supervision

      children = [
        {RedisEx.Connection.Pool, pool_size: 10, port: 6379, name: :redis_pool}
      ]
  """

  use GenServer

  alias RedisEx.Connection

  require Logger

  defstruct [
    :pool_size,
    :strategy,
    :conn_opts,
    conns: [],
    index: 0,
    monitors: %{}
  ]

  # -------------------------------------------------------------------
  # Public API
  # -------------------------------------------------------------------

  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @spec command(GenServer.server(), [String.t()], keyword()) ::
          {:ok, term()} | {:error, term()}
  def command(pool, args, opts \\ []) do
    conn = GenServer.call(pool, :checkout)
    Connection.command(conn, args, opts)
  end

  @spec pipeline(GenServer.server(), [[String.t()]], keyword()) ::
          {:ok, [term()]} | {:error, term()}
  def pipeline(pool, commands, opts \\ []) do
    conn = GenServer.call(pool, :checkout)
    Connection.pipeline(conn, commands, opts)
  end

  @spec transaction(GenServer.server(), [[String.t()]], keyword()) ::
          {:ok, [term()]} | {:error, term()}
  def transaction(pool, commands, opts \\ []) do
    conn = GenServer.call(pool, :checkout)
    Connection.transaction(conn, commands, opts)
  end

  @spec noreply_command(GenServer.server(), [String.t()], keyword()) :: :ok | {:error, term()}
  def noreply_command(pool, args, opts \\ []) do
    conn = GenServer.call(pool, :checkout)
    Connection.noreply_command(conn, args, opts)
  end

  @spec noreply_pipeline(GenServer.server(), [[String.t()]], keyword()) :: :ok | {:error, term()}
  def noreply_pipeline(pool, commands, opts \\ []) do
    conn = GenServer.call(pool, :checkout)
    Connection.noreply_pipeline(conn, commands, opts)
  end

  @doc "Returns pool info: size, active connections, strategy."
  @spec info(GenServer.server()) :: map()
  def info(pool), do: GenServer.call(pool, :info)

  @spec stop(GenServer.server()) :: :ok
  def stop(pool), do: GenServer.stop(pool, :normal)

  # -------------------------------------------------------------------
  # GenServer
  # -------------------------------------------------------------------

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    {pool_size, opts} = Keyword.pop(opts, :pool_size, 5)
    {strategy, opts} = Keyword.pop(opts, :strategy, :round_robin)

    state = %__MODULE__{
      pool_size: pool_size,
      strategy: strategy,
      conn_opts: opts
    }

    case start_connections(state) do
      {:ok, state} -> {:ok, state}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:checkout, _from, state) do
    {conn, state} = pick_connection(state)
    {:reply, conn, state}
  end

  def handle_call(:info, _from, state) do
    info = %{
      pool_size: state.pool_size,
      active: length(state.conns),
      strategy: state.strategy
    }

    {:reply, info, state}
  end

  # Also support direct command/pipeline/transaction calls (for resilience wrapper compat)
  def handle_call({:command, args, opts}, _from, state) do
    {conn, state} = pick_connection(state)
    {:reply, Connection.command(conn, args, opts), state}
  end

  def handle_call({:command, args}, _from, state) do
    {conn, state} = pick_connection(state)
    {:reply, Connection.command(conn, args), state}
  end

  def handle_call({:pipeline, commands, opts}, _from, state) do
    {conn, state} = pick_connection(state)
    {:reply, Connection.pipeline(conn, commands, opts), state}
  end

  def handle_call({:pipeline, commands}, _from, state) do
    {conn, state} = pick_connection(state)
    {:reply, Connection.pipeline(conn, commands), state}
  end

  def handle_call({:transaction, commands, opts}, _from, state) do
    {conn, state} = pick_connection(state)
    {:reply, Connection.transaction(conn, commands, opts), state}
  end

  def handle_call({:transaction, commands}, _from, state) do
    {conn, state} = pick_connection(state)
    {:reply, Connection.transaction(conn, commands), state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    Logger.warning("RedisEx.Pool: connection #{inspect(pid)} died: #{inspect(reason)}")

    # Remove dead connection
    state = %{state | conns: List.delete(state.conns, pid)}
    {_, monitors} = Map.pop(state.monitors, ref)
    state = %{state | monitors: monitors}

    # Replace it
    state = replace_connection(state)
    {:noreply, state}
  end

  def handle_info({:EXIT, _pid, _reason}, state), do: {:noreply, state}
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.conns, fn conn ->
      try do
        Connection.stop(conn)
      catch
        :exit, _ -> :ok
      end
    end)
  end

  # -------------------------------------------------------------------
  # Pool management
  # -------------------------------------------------------------------

  defp start_connections(state) do
    results =
      Enum.reduce_while(1..state.pool_size, {:ok, state}, fn _i, {:ok, s} ->
        case start_and_monitor(s) do
          {:ok, s} -> {:cont, {:ok, s}}
          {:error, reason} ->
            # Clean up already-started connections
            Enum.each(s.conns, fn c ->
              try do
                Connection.stop(c)
              catch
                :exit, _ -> :ok
              end
            end)

            {:halt, {:error, reason}}
        end
      end)

    results
  end

  defp start_and_monitor(state) do
    case Connection.start_link(state.conn_opts) do
      {:ok, conn} ->
        ref = Process.monitor(conn)
        state = %{state | conns: state.conns ++ [conn], monitors: Map.put(state.monitors, ref, conn)}
        {:ok, state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp replace_connection(state) do
    case Connection.start_link(state.conn_opts) do
      {:ok, conn} ->
        ref = Process.monitor(conn)
        Logger.debug("RedisEx.Pool: replaced dead connection with #{inspect(conn)}")
        %{state | conns: state.conns ++ [conn], monitors: Map.put(state.monitors, ref, conn)}

      {:error, reason} ->
        Logger.warning("RedisEx.Pool: failed to replace connection: #{inspect(reason)}")
        # Schedule retry
        Process.send_after(self(), :replace_retry, 1_000)
        state
    end
  end

  defp pick_connection(%{strategy: :round_robin} = state) do
    index = rem(state.index, length(state.conns))
    conn = Enum.at(state.conns, index)
    {conn, %{state | index: index + 1}}
  end

  defp pick_connection(%{strategy: :random} = state) do
    conn = Enum.random(state.conns)
    {conn, state}
  end
end

defmodule Redis.Cache do
  @moduledoc """
  Client-side caching using RESP3 server-assisted invalidation.

  Wraps a `Redis.Connection` and caches read command results in an ETS table.
  The Redis server tracks which keys this client has read and pushes invalidation
  messages when those keys are modified by any client.

  ## How It Works

  1. On start, sends `CLIENT TRACKING ON` to enable server-assisted tracking
  2. Read commands (GET, MGET, HGETALL, etc.) check ETS first
  3. Cache misses go to Redis — response is cached before returning
  4. When any client modifies a cached key, Redis pushes an `invalidate` message
  5. The push arrives as `{:redis_push, :invalidate, keys}` from Connection
  6. Cache evicts those keys from ETS
  7. Next read goes to Redis again

  ## Usage

      {:ok, cache} = Redis.Cache.start_link(port: 6379)

      # First call: cache miss → hits Redis
      {:ok, "bar"} = Redis.Cache.get(cache, "foo")

      # Second call: cache hit → served from ETS
      {:ok, "bar"} = Redis.Cache.get(cache, "foo")

      # Another client does SET foo newval → invalidation push → ETS evicted
      # Next call: cache miss again
      {:ok, "newval"} = Redis.Cache.get(cache, "foo")

      # Stats
      Redis.Cache.stats(cache)
      #=> %{hits: 1, misses: 2, evictions: 1, ...}

  ## Options

    * All `Redis.Connection` options (host, port, password, etc.)
    * `:ttl` - local TTL in ms for cached entries (default: nil, rely on server invalidation)
    * `:optin` - if true, only cache commands prefixed with CACHING YES (default: false)
    * `:name` - GenServer name
  """

  use GenServer

  alias Redis.Connection
  alias Redis.Cache.Store

  require Logger

  defstruct [
    :conn,
    :store,
    :ttl,
    optin: false
  ]

  # -------------------------------------------------------------------
  # Public API
  # -------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc "GET with caching. Returns `{:ok, value}` or `{:ok, nil}`."
  @spec get(GenServer.server(), String.t()) :: {:ok, term()} | {:error, term()}
  def get(cache, key), do: GenServer.call(cache, {:cached_get, key})

  @doc "MGET with caching."
  @spec mget(GenServer.server(), [String.t()]) :: {:ok, [term()]} | {:error, term()}
  def mget(cache, keys), do: GenServer.call(cache, {:cached_mget, keys})

  @doc "HGETALL with caching."
  @spec hgetall(GenServer.server(), String.t()) :: {:ok, term()} | {:error, term()}
  def hgetall(cache, key), do: GenServer.call(cache, {:cached_hgetall, key})

  @doc "Sends a command through the underlying connection (not cached)."
  @spec command(GenServer.server(), [String.t()]) :: {:ok, term()} | {:error, term()}
  def command(cache, args), do: GenServer.call(cache, {:command, args})

  @doc "Returns cache statistics."
  @spec stats(GenServer.server()) :: map()
  def stats(cache), do: GenServer.call(cache, :stats)

  @doc "Flushes the local cache."
  @spec flush(GenServer.server()) :: :ok
  def flush(cache), do: GenServer.call(cache, :flush)

  @doc "Disables tracking and stops."
  @spec stop(GenServer.server()) :: :ok
  def stop(cache), do: GenServer.stop(cache, :normal)

  # -------------------------------------------------------------------
  # GenServer callbacks
  # -------------------------------------------------------------------

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    {ttl, opts} = Keyword.pop(opts, :ttl)
    {optin, opts} = Keyword.pop(opts, :optin, false)

    # Tell the connection to forward push messages to us
    conn_opts = Keyword.put(opts, :push_receiver, self())

    case Connection.start_link(conn_opts) do
      {:ok, conn} ->
        # Enable client tracking
        tracking_args = ["CLIENT", "TRACKING", "ON"]
        tracking_args = if optin, do: tracking_args ++ ["OPTIN"], else: tracking_args

        case Connection.command(conn, tracking_args) do
          {:ok, "OK"} ->
            store = Store.new()

            state = %__MODULE__{
              conn: conn,
              store: store,
              ttl: ttl,
              optin: optin
            }

            {:ok, state}

          {:error, reason} ->
            Connection.stop(conn)
            {:stop, {:tracking_failed, reason}}
        end

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:cached_get, key}, _from, state) do
    case Store.get(state.store, key) do
      {:hit, value, store} ->
        {:reply, {:ok, value}, %{state | store: store}}

      {:miss, store} ->
        # Maybe send CACHING YES in optin mode
        result =
          if state.optin do
            Connection.pipeline(state.conn, [["CLIENT", "CACHING", "YES"], ["GET", key]])
          else
            Connection.command(state.conn, ["GET", key])
          end

        case normalize_optin_result(result, state.optin) do
          {:ok, value} ->
            store = Store.put(store, key, value, state.ttl)
            {:reply, {:ok, value}, %{state | store: store}}

          error ->
            {:reply, error, %{state | store: store}}
        end
    end
  end

  def handle_call({:cached_mget, keys}, _from, state) do
    # Check cache for each key
    {cached, missed_keys, missed_indices, store} =
      keys
      |> Enum.with_index()
      |> Enum.reduce({%{}, [], [], state.store}, fn {key, idx},
                                                    {cached, missed_k, missed_i, st} ->
        case Store.get(st, key) do
          {:hit, value, st} -> {Map.put(cached, idx, value), missed_k, missed_i, st}
          {:miss, st} -> {cached, [key | missed_k], [idx | missed_i], st}
        end
      end)

    if missed_keys == [] do
      # All cached
      values = Enum.map(0..(length(keys) - 1), &Map.get(cached, &1))
      {:reply, {:ok, values}, %{state | store: store}}
    else
      # Fetch missing from Redis
      missed_keys = Enum.reverse(missed_keys)
      missed_indices = Enum.reverse(missed_indices)

      case Connection.command(state.conn, ["MGET" | missed_keys]) do
        {:ok, fetched} when is_list(fetched) ->
          # Cache the fetched values
          store =
            Enum.zip(missed_keys, fetched)
            |> Enum.reduce(store, fn {key, value}, st ->
              Store.put(st, key, value, state.ttl)
            end)

          # Merge cached and fetched
          fetched_map =
            Enum.zip(missed_indices, fetched) |> Map.new()

          all = Map.merge(cached, fetched_map)
          values = Enum.map(0..(length(keys) - 1), &Map.get(all, &1))

          {:reply, {:ok, values}, %{state | store: store}}

        error ->
          {:reply, error, %{state | store: store}}
      end
    end
  end

  def handle_call({:cached_hgetall, key}, _from, state) do
    cache_key = {:hgetall, key}

    case Store.get(state.store, cache_key) do
      {:hit, value, store} ->
        {:reply, {:ok, value}, %{state | store: store}}

      {:miss, store} ->
        case Connection.command(state.conn, ["HGETALL", key]) do
          {:ok, value} ->
            store = Store.put(store, cache_key, value, state.ttl)
            # Also track by the raw key for invalidation
            store = Store.put(store, key, {:hgetall_ref, cache_key}, state.ttl)
            {:reply, {:ok, value}, %{state | store: store}}

          error ->
            {:reply, error, %{state | store: store}}
        end
    end
  end

  def handle_call({:command, args}, _from, state) do
    {:reply, Connection.command(state.conn, args), state}
  end

  def handle_call(:stats, _from, state) do
    {:reply, Store.stats(state.store), state}
  end

  def handle_call(:flush, _from, state) do
    {:reply, :ok, %{state | store: Store.flush(state.store)}}
  end

  @impl true
  def handle_info({:redis_push, :invalidate, keys}, state) do
    store = Store.invalidate(state.store, keys)

    # If any invalidated key was a hgetall ref, also invalidate that
    store =
      if keys do
        Enum.reduce(keys, store, fn key, st ->
          case :ets.lookup(st.table, key) do
            [{^key, {:hgetall_ref, cache_key}, _}] ->
              Store.invalidate(st, [cache_key])

            _ ->
              st
          end
        end)
      else
        store
      end

    {:noreply, %{state | store: store}}
  end

  def handle_info({:EXIT, _pid, _reason}, state) do
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{conn: nil}), do: :ok

  def terminate(_reason, state) do
    # Disable tracking before closing
    try do
      Connection.command(state.conn, ["CLIENT", "TRACKING", "OFF"])
    catch
      :exit, _ -> :ok
    end

    Store.destroy(state.store)

    try do
      Connection.stop(state.conn)
    catch
      :exit, _ -> :ok
    end
  end

  # -------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------

  # In OPTIN mode, pipeline returns [caching_ok, actual_result]
  defp normalize_optin_result({:ok, [_caching, value]}, true), do: {:ok, value}
  defp normalize_optin_result(result, false), do: result
  defp normalize_optin_result(error, _), do: error
end

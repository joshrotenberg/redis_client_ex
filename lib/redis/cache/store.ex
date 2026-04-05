defmodule Redis.Cache.Store do
  @moduledoc """
  ETS-backed cache store for client-side caching.

  This is the default implementation of `Redis.Cache.Backend`. Stores
  key -> value mappings with optional TTL, bounded size, and configurable
  eviction policy. Tracks hits, misses, and evictions for observability.

  ## Options

    * `:max_entries` - maximum number of entries (default: `10_000`, `0` for unlimited)
    * `:eviction_policy` - `:lru` or `:fifo` (default: `:lru`)
  """

  @behaviour Redis.Cache.Backend

  defstruct [
    :table,
    :index_table,
    :refs_table,
    max_entries: 10_000,
    eviction_policy: :lru,
    hits: 0,
    misses: 0,
    evictions: 0,
    stores: 0
  ]

  @type eviction_policy :: :lru | :fifo

  @type t :: %__MODULE__{
          table: :ets.tid(),
          index_table: :ets.tid(),
          refs_table: :ets.tid(),
          max_entries: non_neg_integer(),
          eviction_policy: eviction_policy(),
          hits: non_neg_integer(),
          misses: non_neg_integer(),
          evictions: non_neg_integer(),
          stores: non_neg_integer()
        }

  @doc "Initializes the store from options. Implements `Redis.Cache.Backend.init/1`."
  @impl true
  @spec init(keyword()) :: {:ok, t()}
  def init(opts) do
    name = Keyword.get(opts, :name, :redis_ex_cache)
    {:ok, new(name, opts)}
  end

  @doc "Creates a new cache store backed by ETS tables."
  @spec new(atom(), keyword()) :: t()
  def new(name \\ :redis_ex_cache, opts \\ []) do
    max_entries = Keyword.get(opts, :max_entries, 10_000)
    eviction_policy = Keyword.get(opts, :eviction_policy, :lru)

    table = :ets.new(name, [:set, :public, read_concurrency: true])
    index_name = :"#{name}_index"
    index_table = :ets.new(index_name, [:ordered_set, :public])
    refs_name = :"#{name}_refs"
    refs_table = :ets.new(refs_name, [:bag, :public])

    %__MODULE__{
      table: table,
      index_table: index_table,
      refs_table: refs_table,
      max_entries: max_entries,
      eviction_policy: eviction_policy
    }
  end

  @doc "Gets a value from the cache. Returns `{:hit, value, store}` or `{:miss, store}`."
  @impl true
  @spec get(t(), term()) :: {:hit, term(), t()} | {:miss, t()}
  def get(%__MODULE__{} = store, key) do
    case :ets.lookup(store.table, key) do
      [{^key, value, expires_at, timestamp}] ->
        if expired?(expires_at) do
          delete_entry(store, key, timestamp)
          {:miss, %{store | misses: store.misses + 1, evictions: store.evictions + 1}}
        else
          store = maybe_touch_lru(store, key, timestamp)
          {:hit, value, %{store | hits: store.hits + 1}}
        end

      [] ->
        {:miss, %{store | misses: store.misses + 1}}
    end
  end

  @doc "Puts a value in the cache with optional TTL in milliseconds."
  @impl true
  @spec put(t(), term(), term(), non_neg_integer() | nil) :: t()
  def put(%__MODULE__{} = store, key, value, ttl_ms \\ nil) do
    expires_at =
      if ttl_ms do
        System.monotonic_time(:millisecond) + ttl_ms
      end

    # Remove old index entry if key already exists
    store = remove_old_index(store, key)

    # Evict if at capacity
    store = maybe_evict(store)

    timestamp = System.unique_integer([:monotonic])
    :ets.insert(store.table, {key, value, expires_at, timestamp})
    :ets.insert(store.index_table, {timestamp, key})

    %{store | stores: store.stores + 1}
  end

  @doc """
  Puts a value in the cache and records a ref from `redis_key` to `cache_key`.

  When `redis_key` is later invalidated via `invalidate_refs/2`, all cache
  entries that reference it are removed.
  """
  @impl true
  @spec put_with_ref(t(), term(), String.t(), term(), non_neg_integer() | nil) :: t()
  def put_with_ref(%__MODULE__{} = store, cache_key, redis_key, value, ttl_ms \\ nil) do
    store = put(store, cache_key, value, ttl_ms)
    :ets.insert(store.refs_table, {redis_key, cache_key})
    store
  end

  @doc """
  Invalidates all cache entries that reference the given Redis key(s).

  Looks up the refs table to find cache keys that depend on each Redis key,
  invalidates them, and cleans up the ref entries.
  """
  @impl true
  @spec invalidate_refs(t(), [String.t()] | nil) :: t()
  def invalidate_refs(%__MODULE__{} = store, nil), do: store

  def invalidate_refs(%__MODULE__{} = store, keys) when is_list(keys) do
    Enum.reduce(keys, store, fn redis_key, st ->
      refs = :ets.lookup(st.refs_table, redis_key)
      st = invalidate_cache_keys(st, refs)
      :ets.delete(st.refs_table, redis_key)
      st
    end)
  end

  @doc "Invalidates one or more keys. Called when Redis pushes invalidation."
  @impl true
  @spec invalidate(t(), [String.t()] | nil) :: t()
  def invalidate(%__MODULE__{} = store, nil) do
    count = :ets.info(store.table, :size)
    :ets.delete_all_objects(store.table)
    :ets.delete_all_objects(store.index_table)
    :ets.delete_all_objects(store.refs_table)
    %{store | evictions: store.evictions + count}
  end

  def invalidate(%__MODULE__{} = store, keys) when is_list(keys) do
    evicted =
      Enum.count(keys, fn key ->
        case :ets.lookup(store.table, key) do
          [{^key, _, _, timestamp}] ->
            delete_entry(store, key, timestamp)
            true

          [] ->
            false
        end
      end)

    %{store | evictions: store.evictions + evicted}
  end

  @doc "Returns cache statistics."
  @impl true
  @spec stats(t()) :: map()
  def stats(%__MODULE__{} = store) do
    total = store.hits + store.misses
    hit_rate = if total > 0, do: Float.round(store.hits / total * 100, 1), else: 0.0

    %{
      hits: store.hits,
      misses: store.misses,
      evictions: store.evictions,
      stores: store.stores,
      size: :ets.info(store.table, :size),
      hit_rate: hit_rate,
      max_entries: store.max_entries,
      eviction_policy: store.eviction_policy
    }
  end

  @doc "Removes expired entries from the cache."
  @impl true
  @spec sweep_expired(t()) :: t()
  def sweep_expired(%__MODULE__{} = store) do
    now = System.monotonic_time(:millisecond)

    expired =
      :ets.select(store.table, [
        {{:"$1", :_, :"$2", :"$3"}, [{:"/=", :"$2", nil}, {:<, :"$2", now}], [{{:"$1", :"$3"}}]}
      ])

    Enum.each(expired, fn {key, timestamp} ->
      delete_entry(store, key, timestamp)
    end)

    evicted = length(expired)
    %{store | evictions: store.evictions + evicted}
  end

  @doc "Clears the entire cache."
  @impl true
  @spec flush(t()) :: t()
  def flush(%__MODULE__{} = store) do
    :ets.delete_all_objects(store.table)
    :ets.delete_all_objects(store.index_table)
    :ets.delete_all_objects(store.refs_table)
    store
  end

  @doc "Destroys the cache store (deletes the ETS tables)."
  @impl true
  @spec destroy(t()) :: :ok
  def destroy(%__MODULE__{table: table, index_table: index_table, refs_table: refs_table}) do
    :ets.delete(table)
    :ets.delete(index_table)
    :ets.delete(refs_table)
    :ok
  end

  # -------------------------------------------------------------------
  # Private helpers
  # -------------------------------------------------------------------

  defp invalidate_cache_keys(store, refs) do
    Enum.reduce(refs, store, fn {_redis_key, cache_key}, st ->
      case :ets.lookup(st.table, cache_key) do
        [{^cache_key, _, _, timestamp}] ->
          delete_entry(st, cache_key, timestamp)
          %{st | evictions: st.evictions + 1}

        [] ->
          st
      end
    end)
  end

  defp expired?(nil), do: false
  defp expired?(expires_at), do: System.monotonic_time(:millisecond) > expires_at

  defp delete_entry(store, key, timestamp) do
    :ets.delete(store.table, key)
    :ets.delete(store.index_table, timestamp)
  end

  defp remove_old_index(store, key) do
    case :ets.lookup(store.table, key) do
      [{^key, _, _, old_timestamp}] ->
        :ets.delete(store.index_table, old_timestamp)
        store

      [] ->
        store
    end
  end

  defp maybe_touch_lru(%{eviction_policy: :lru} = store, key, old_timestamp) do
    :ets.delete(store.index_table, old_timestamp)
    new_timestamp = System.unique_integer([:monotonic])
    :ets.insert(store.index_table, {new_timestamp, key})
    :ets.update_element(store.table, key, {4, new_timestamp})
    store
  end

  defp maybe_touch_lru(store, _key, _timestamp), do: store

  defp maybe_evict(%{max_entries: 0} = store), do: store

  defp maybe_evict(%{max_entries: max} = store) do
    if :ets.info(store.table, :size) >= max do
      evict_one(store)
    else
      store
    end
  end

  defp evict_one(store) do
    case :ets.first(store.index_table) do
      :"$end_of_table" ->
        store

      timestamp ->
        [{^timestamp, key}] = :ets.lookup(store.index_table, timestamp)
        delete_entry(store, key, timestamp)
        %{store | evictions: store.evictions + 1}
    end
  end
end

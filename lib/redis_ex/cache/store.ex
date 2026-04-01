defmodule RedisEx.Cache.Store do
  @moduledoc """
  ETS-backed cache store for client-side caching.

  Stores key → value mappings with optional TTL. Tracks hits, misses,
  and evictions for observability.
  """

  defstruct [:table, hits: 0, misses: 0, evictions: 0, stores: 0]

  @type t :: %__MODULE__{
          table: :ets.tid(),
          hits: non_neg_integer(),
          misses: non_neg_integer(),
          evictions: non_neg_integer(),
          stores: non_neg_integer()
        }

  @doc "Creates a new cache store backed by an ETS table."
  @spec new(atom()) :: t()
  def new(name \\ :redis_ex_cache) do
    table = :ets.new(name, [:set, :public, read_concurrency: true])
    %__MODULE__{table: table}
  end

  @doc "Gets a value from the cache. Returns `{:hit, value, store}` or `{:miss, store}`."
  @spec get(t(), String.t()) :: {:hit, term(), t()} | {:miss, t()}
  def get(%__MODULE__{} = store, key) do
    case :ets.lookup(store.table, key) do
      [{^key, value, expires_at}] ->
        if expired?(expires_at) do
          :ets.delete(store.table, key)
          {:miss, %{store | misses: store.misses + 1, evictions: store.evictions + 1}}
        else
          {:hit, value, %{store | hits: store.hits + 1}}
        end

      [] ->
        {:miss, %{store | misses: store.misses + 1}}
    end
  end

  @doc "Puts a value in the cache with optional TTL in milliseconds."
  @spec put(t(), String.t(), term(), non_neg_integer() | nil) :: t()
  def put(%__MODULE__{} = store, key, value, ttl_ms \\ nil) do
    expires_at =
      if ttl_ms do
        System.monotonic_time(:millisecond) + ttl_ms
      else
        nil
      end

    :ets.insert(store.table, {key, value, expires_at})
    %{store | stores: store.stores + 1}
  end

  @doc "Invalidates one or more keys. Called when Redis pushes invalidation."
  @spec invalidate(t(), [String.t()] | nil) :: t()
  def invalidate(%__MODULE__{} = store, nil) do
    # nil means flush all (server sent invalidate with nil key list)
    count = :ets.info(store.table, :size)
    :ets.delete_all_objects(store.table)
    %{store | evictions: store.evictions + count}
  end

  def invalidate(%__MODULE__{} = store, keys) when is_list(keys) do
    evicted =
      Enum.count(keys, fn key ->
        case :ets.lookup(store.table, key) do
          [{^key, _, _}] ->
            :ets.delete(store.table, key)
            true

          [] ->
            false
        end
      end)

    %{store | evictions: store.evictions + evicted}
  end

  @doc "Returns cache statistics."
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
      hit_rate: hit_rate
    }
  end

  @doc "Clears the entire cache."
  @spec flush(t()) :: t()
  def flush(%__MODULE__{} = store) do
    :ets.delete_all_objects(store.table)
    store
  end

  @doc "Destroys the cache store (deletes the ETS table)."
  @spec destroy(t()) :: :ok
  def destroy(%__MODULE__{table: table}) do
    :ets.delete(table)
    :ok
  end

  defp expired?(nil), do: false
  defp expired?(expires_at), do: System.monotonic_time(:millisecond) > expires_at
end

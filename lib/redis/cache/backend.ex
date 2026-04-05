defmodule Redis.Cache.Backend do
  @moduledoc """
  Behaviour for pluggable client-side cache backends.

  The default implementation is `Redis.Cache.Store`, which uses ETS tables
  with bounded size, LRU/FIFO eviction, and TTL support.

  Implement this behaviour to use an alternative cache backend (e.g., Cachex,
  ConCache, or a custom store).

  ## Example

      defmodule MyApp.CachexBackend do
        @behaviour Redis.Cache.Backend

        @impl true
        def init(opts) do
          name = Keyword.get(opts, :name, :my_cache)
          {:ok, _pid} = Cachex.start_link(name)
          {:ok, %{name: name}}
        end

        @impl true
        def get(state, key) do
          case Cachex.get(state.name, key) do
            {:ok, nil} -> {:miss, state}
            {:ok, value} -> {:hit, value, state}
          end
        end

        # ... implement remaining callbacks
      end

  Then pass it when starting the cache:

      Redis.Cache.start_link(
        port: 6379,
        backend: MyApp.CachexBackend,
        backend_opts: [name: :my_redis_cache]
      )
  """

  @type state :: term()

  @doc "Initializes the backend. Returns `{:ok, state}` or `{:error, reason}`."
  @callback init(opts :: keyword()) :: {:ok, state()} | {:error, term()}

  @doc """
  Gets a value from the cache.

  Returns `{:hit, value, state}` on cache hit or `{:miss, state}` on miss.
  """
  @callback get(state(), key :: term()) ::
              {:hit, value :: term(), state()} | {:miss, state()}

  @doc "Puts a value in the cache with optional TTL in milliseconds."
  @callback put(state(), key :: term(), value :: term(), ttl_ms :: non_neg_integer() | nil) ::
              state()

  @doc """
  Puts a value and records a ref from `redis_key` to `cache_key`.

  When `redis_key` is later invalidated via `invalidate_refs/2`, all cache
  entries that reference it should be removed.
  """
  @callback put_with_ref(
              state(),
              cache_key :: term(),
              redis_key :: String.t(),
              value :: term(),
              ttl_ms :: non_neg_integer() | nil
            ) :: state()

  @doc """
  Invalidates all cache entries that reference the given Redis key(s).

  Called when Redis pushes invalidation for keys that were cached via
  `put_with_ref/5`. A `nil` keys argument is a no-op.
  """
  @callback invalidate_refs(state(), keys :: [String.t()] | nil) :: state()

  @doc """
  Invalidates one or more keys directly.

  Called when Redis pushes invalidation. A `nil` keys argument means
  flush all entries.
  """
  @callback invalidate(state(), keys :: [String.t()] | nil) :: state()

  @doc "Returns cache statistics as a map."
  @callback stats(state()) :: map()

  @doc "Removes expired entries from the cache."
  @callback sweep_expired(state()) :: state()

  @doc "Clears the entire cache."
  @callback flush(state()) :: state()

  @doc "Destroys the cache backend and releases resources."
  @callback destroy(state()) :: :ok
end

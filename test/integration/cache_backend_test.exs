defmodule Redis.Cache.MapBackend do
  @moduledoc false
  @behaviour Redis.Cache.Backend

  defstruct [:data, :refs, hits: 0, misses: 0, evictions: 0, stores: 0]

  @impl true
  def init(_opts) do
    {:ok, %__MODULE__{data: %{}, refs: %{}}}
  end

  @impl true
  def get(%__MODULE__{} = state, key) do
    case Map.fetch(state.data, key) do
      {:ok, {value, expires_at}} ->
        if expired?(expires_at) do
          state = %{state | data: Map.delete(state.data, key), misses: state.misses + 1}
          {:miss, state}
        else
          {:hit, value, %{state | hits: state.hits + 1}}
        end

      :error ->
        {:miss, %{state | misses: state.misses + 1}}
    end
  end

  @impl true
  def put(%__MODULE__{} = state, key, value, ttl_ms) do
    expires_at = if ttl_ms, do: System.monotonic_time(:millisecond) + ttl_ms
    %{state | data: Map.put(state.data, key, {value, expires_at}), stores: state.stores + 1}
  end

  @impl true
  def put_with_ref(%__MODULE__{} = state, cache_key, redis_key, value, ttl_ms) do
    state = put(state, cache_key, value, ttl_ms)
    existing = Map.get(state.refs, redis_key, MapSet.new())
    %{state | refs: Map.put(state.refs, redis_key, MapSet.put(existing, cache_key))}
  end

  @impl true
  def invalidate_refs(%__MODULE__{} = state, nil), do: state

  def invalidate_refs(%__MODULE__{} = state, keys) do
    Enum.reduce(keys, state, fn redis_key, st ->
      cache_keys = Map.get(st.refs, redis_key, MapSet.new())
      st = evict_cache_keys(st, cache_keys)
      %{st | refs: Map.delete(st.refs, redis_key)}
    end)
  end

  defp evict_cache_keys(state, cache_keys) do
    Enum.reduce(cache_keys, state, fn ck, inner ->
      if Map.has_key?(inner.data, ck) do
        %{inner | data: Map.delete(inner.data, ck), evictions: inner.evictions + 1}
      else
        inner
      end
    end)
  end

  @impl true
  def invalidate(%__MODULE__{} = state, nil) do
    count = map_size(state.data)
    %{state | data: %{}, refs: %{}, evictions: state.evictions + count}
  end

  def invalidate(%__MODULE__{} = state, keys) do
    Enum.reduce(keys, state, fn key, st ->
      if Map.has_key?(st.data, key) do
        %{st | data: Map.delete(st.data, key), evictions: st.evictions + 1}
      else
        st
      end
    end)
  end

  @impl true
  def stats(%__MODULE__{} = state) do
    total = state.hits + state.misses
    hit_rate = if total > 0, do: Float.round(state.hits / total * 100, 1), else: 0.0

    %{
      hits: state.hits,
      misses: state.misses,
      evictions: state.evictions,
      stores: state.stores,
      size: map_size(state.data),
      hit_rate: hit_rate
    }
  end

  @impl true
  def sweep_expired(%__MODULE__{} = state) do
    now = System.monotonic_time(:millisecond)

    {kept, evicted_count} =
      Enum.reduce(state.data, {%{}, 0}, fn {key, {_val, exp} = entry}, {acc, count} ->
        if exp != nil and exp < now do
          {acc, count + 1}
        else
          {Map.put(acc, key, entry), count}
        end
      end)

    %{state | data: kept, evictions: state.evictions + evicted_count}
  end

  @impl true
  def flush(%__MODULE__{} = state) do
    %{state | data: %{}, refs: %{}}
  end

  @impl true
  def destroy(%__MODULE__{}), do: :ok

  defp expired?(nil), do: false
  defp expired?(exp), do: System.monotonic_time(:millisecond) > exp
end

defmodule Redis.Cache.BackendIntegrationTest do
  use ExUnit.Case, async: false

  alias Redis.Cache
  alias Redis.Connection

  describe "custom backend" do
    test "caches GET results using MapBackend" do
      {:ok, cache} = Cache.start_link(port: 6398, backend: Redis.Cache.MapBackend)

      Cache.command(cache, ["SET", "be_test", "hello"])

      # Miss
      assert {:ok, "hello"} = Cache.get(cache, "be_test")
      stats = Cache.stats(cache)
      assert stats.misses == 1

      # Hit
      assert {:ok, "hello"} = Cache.get(cache, "be_test")
      stats = Cache.stats(cache)
      assert stats.hits == 1

      Cache.command(cache, ["DEL", "be_test"])
      Cache.stop(cache)
    end

    test "invalidation works with MapBackend" do
      {:ok, cache} = Cache.start_link(port: 6398, backend: Redis.Cache.MapBackend)

      Cache.command(cache, ["SET", "be_inv", "original"])
      Cache.get(cache, "be_inv")
      Cache.get(cache, "be_inv")

      # Modify via separate connection
      {:ok, other} = Connection.start_link(port: 6398)
      Connection.command(other, ["SET", "be_inv", "modified"])
      Process.sleep(200)

      assert {:ok, "modified"} = Cache.get(cache, "be_inv")

      stats = Cache.stats(cache)
      assert stats.evictions >= 1

      Connection.stop(other)
      Cache.command(cache, ["DEL", "be_inv"])
      Cache.stop(cache)
    end

    test "cached_command works with MapBackend" do
      {:ok, cache} = Cache.start_link(port: 6398, backend: Redis.Cache.MapBackend)

      Cache.command(cache, ["RPUSH", "be_list", "a", "b", "c"])

      assert {:ok, 3} = Cache.cached_command(cache, ["LLEN", "be_list"])
      assert {:ok, 3} = Cache.cached_command(cache, ["LLEN", "be_list"])

      stats = Cache.stats(cache)
      assert stats.hits >= 1

      Cache.command(cache, ["DEL", "be_list"])
      Cache.stop(cache)
    end

    test "MGET works with MapBackend" do
      {:ok, cache} = Cache.start_link(port: 6398, backend: Redis.Cache.MapBackend)

      Cache.command(cache, ["SET", "be_m1", "x"])
      Cache.command(cache, ["SET", "be_m2", "y"])

      Cache.get(cache, "be_m1")
      assert {:ok, ["x", "y"]} = Cache.mget(cache, ["be_m1", "be_m2"])

      stats = Cache.stats(cache)
      assert stats.hits >= 1

      Cache.command(cache, ["DEL", "be_m1", "be_m2"])
      Cache.stop(cache)
    end

    test "flush works with MapBackend" do
      {:ok, cache} = Cache.start_link(port: 6398, backend: Redis.Cache.MapBackend)

      Cache.command(cache, ["SET", "be_flush", "val"])
      Cache.get(cache, "be_flush")

      stats = Cache.stats(cache)
      assert stats.size == 1

      Cache.flush(cache)

      stats = Cache.stats(cache)
      assert stats.size == 0

      Cache.command(cache, ["DEL", "be_flush"])
      Cache.stop(cache)
    end

    test "stats works with MapBackend" do
      {:ok, cache} = Cache.start_link(port: 6398, backend: Redis.Cache.MapBackend)

      Cache.command(cache, ["SET", "be_st", "val"])
      Cache.get(cache, "be_st")
      Cache.get(cache, "be_st")
      Cache.get(cache, "be_st")

      stats = Cache.stats(cache)
      assert stats.misses >= 1
      assert stats.hits >= 2
      assert stats.hit_rate > 50.0

      Cache.command(cache, ["DEL", "be_st"])
      Cache.stop(cache)
    end
  end
end

defmodule RedisEx.CacheTest do
  use ExUnit.Case, async: false

  alias RedisEx.Cache
  alias RedisEx.Cache.Store
  alias RedisEx.Connection

  # Uses redis-server on port 6398 (no auth) from test_helper.exs

  describe "Store (unit)" do
    test "put and get" do
      store = Store.new(:test_store_1)
      store = Store.put(store, "key", "value")
      assert {:hit, "value", _store} = Store.get(store, "key")
      Store.destroy(store)
    end

    test "miss on unknown key" do
      store = Store.new(:test_store_2)
      assert {:miss, _store} = Store.get(store, "nonexistent")
      Store.destroy(store)
    end

    test "TTL expiration" do
      store = Store.new(:test_store_3)
      store = Store.put(store, "key", "value", 50)
      assert {:hit, "value", _} = Store.get(store, "key")
      Process.sleep(100)
      assert {:miss, _} = Store.get(store, "key")
      Store.destroy(store)
    end

    test "invalidate keys" do
      store = Store.new(:test_store_4)
      store = Store.put(store, "a", "1")
      store = Store.put(store, "b", "2")
      store = Store.put(store, "c", "3")
      store = Store.invalidate(store, ["a", "b"])
      assert {:miss, _} = Store.get(store, "a")
      assert {:miss, _} = Store.get(store, "b")
      assert {:hit, "3", _} = Store.get(store, "c")
      Store.destroy(store)
    end

    test "invalidate nil flushes all" do
      store = Store.new(:test_store_5)
      store = Store.put(store, "a", "1")
      store = Store.put(store, "b", "2")
      store = Store.invalidate(store, nil)
      assert {:miss, _} = Store.get(store, "a")
      assert {:miss, _} = Store.get(store, "b")
      Store.destroy(store)
    end

    test "stats" do
      store = Store.new(:test_store_6)
      store = Store.put(store, "key", "value")
      {:hit, _, store} = Store.get(store, "key")
      {:miss, store} = Store.get(store, "other")
      stats = Store.stats(store)
      assert stats.hits == 1
      assert stats.misses == 1
      assert stats.stores == 1
      assert stats.size == 1
      Store.destroy(store)
    end
  end

  describe "Cache integration" do
    test "caches GET results" do
      {:ok, cache} = Cache.start_link(port: 6398)

      # Set a value via direct command
      Cache.command(cache, ["SET", "cache_test", "hello"])

      # First get: miss
      assert {:ok, "hello"} = Cache.get(cache, "cache_test")
      stats = Cache.stats(cache)
      assert stats.misses == 1
      assert stats.hits == 0

      # Second get: hit
      assert {:ok, "hello"} = Cache.get(cache, "cache_test")
      stats = Cache.stats(cache)
      assert stats.hits == 1

      Cache.stop(cache)
    end

    test "invalidation evicts cache" do
      {:ok, cache} = Cache.start_link(port: 6398)

      # Set and cache
      Cache.command(cache, ["SET", "inv_test", "original"])
      assert {:ok, "original"} = Cache.get(cache, "inv_test")
      assert {:ok, "original"} = Cache.get(cache, "inv_test")  # hit

      # Modify via a separate connection (triggers invalidation)
      {:ok, other} = Connection.start_link(port: 6398)
      Connection.command(other, ["SET", "inv_test", "modified"])

      # Give the push invalidation a moment to arrive
      Process.sleep(200)

      # Next get should be a miss and fetch the new value
      assert {:ok, "modified"} = Cache.get(cache, "inv_test")

      stats = Cache.stats(cache)
      assert stats.evictions >= 1

      Connection.stop(other)
      Cache.stop(cache)
    end

    test "MGET with partial cache" do
      {:ok, cache} = Cache.start_link(port: 6398)

      Cache.command(cache, ["SET", "mg_a", "1"])
      Cache.command(cache, ["SET", "mg_b", "2"])
      Cache.command(cache, ["SET", "mg_c", "3"])

      # Cache one key
      Cache.get(cache, "mg_a")

      # MGET: a is cached, b and c are misses
      assert {:ok, ["1", "2", "3"]} = Cache.mget(cache, ["mg_a", "mg_b", "mg_c"])

      # Now all should be cached
      assert {:ok, ["1", "2", "3"]} = Cache.mget(cache, ["mg_a", "mg_b", "mg_c"])
      stats = Cache.stats(cache)
      assert stats.hits >= 3

      Cache.stop(cache)
    end

    test "flush clears cache" do
      {:ok, cache} = Cache.start_link(port: 6398)

      Cache.command(cache, ["SET", "flush_test", "val"])
      Cache.get(cache, "flush_test")

      stats = Cache.stats(cache)
      assert stats.size == 1

      Cache.flush(cache)

      stats = Cache.stats(cache)
      assert stats.size == 0

      Cache.stop(cache)
    end

    test "stats returns correct values" do
      {:ok, cache} = Cache.start_link(port: 6398)

      Cache.command(cache, ["SET", "st_key", "val"])
      Cache.get(cache, "st_key")   # miss
      Cache.get(cache, "st_key")   # hit
      Cache.get(cache, "st_key")   # hit

      stats = Cache.stats(cache)
      assert stats.misses >= 1
      assert stats.hits >= 2
      assert stats.hit_rate > 50.0

      Cache.stop(cache)
    end

    test "local TTL expiration" do
      {:ok, cache} = Cache.start_link(port: 6398, ttl: 100)

      Cache.command(cache, ["SET", "ttl_test", "val"])
      Cache.get(cache, "ttl_test")   # miss, cached with TTL
      Cache.get(cache, "ttl_test")   # hit

      Process.sleep(200)

      # TTL expired — should miss
      Cache.get(cache, "ttl_test")
      stats = Cache.stats(cache)
      assert stats.evictions >= 1

      Cache.stop(cache)
    end
  end
end

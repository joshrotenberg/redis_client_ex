defmodule Redis.Cache.StoreTest do
  use ExUnit.Case, async: true

  alias Redis.Cache.Store

  describe "max_entries with LRU eviction" do
    test "evicts least recently used entry when at capacity" do
      store = Store.new(:lru_evict_1, max_entries: 3, eviction_policy: :lru)

      store = Store.put(store, "a", "1")
      store = Store.put(store, "b", "2")
      store = Store.put(store, "c", "3")

      # Access "a" to make it recently used
      {:hit, "1", store} = Store.get(store, "a")

      # Insert "d" — should evict "b" (least recently used)
      store = Store.put(store, "d", "4")

      assert {:miss, _} = Store.get(store, "b")
      assert {:hit, "1", _} = Store.get(store, "a")
      assert {:hit, "3", _} = Store.get(store, "c")
      assert {:hit, "4", _} = Store.get(store, "d")

      stats = Store.stats(store)
      assert stats.size == 3
      assert stats.evictions >= 1

      Store.destroy(store)
    end

    test "evicts oldest entry when no reads have occurred" do
      store = Store.new(:lru_evict_2, max_entries: 2, eviction_policy: :lru)

      store = Store.put(store, "first", "1")
      store = Store.put(store, "second", "2")
      store = Store.put(store, "third", "3")

      assert {:miss, _} = Store.get(store, "first")
      assert {:hit, "2", _} = Store.get(store, "second")
      assert {:hit, "3", _} = Store.get(store, "third")

      Store.destroy(store)
    end
  end

  describe "max_entries with FIFO eviction" do
    test "evicts first inserted entry regardless of access" do
      store = Store.new(:fifo_evict_1, max_entries: 3, eviction_policy: :fifo)

      store = Store.put(store, "a", "1")
      store = Store.put(store, "b", "2")
      store = Store.put(store, "c", "3")

      # Access "a" — should NOT affect eviction order under FIFO
      {:hit, "1", store} = Store.get(store, "a")

      # Insert "d" — should evict "a" (first in)
      store = Store.put(store, "d", "4")

      assert {:miss, _} = Store.get(store, "a")
      assert {:hit, "2", _} = Store.get(store, "b")
      assert {:hit, "3", _} = Store.get(store, "c")
      assert {:hit, "4", _} = Store.get(store, "d")

      Store.destroy(store)
    end
  end

  describe "unlimited cache (max_entries: 0)" do
    test "does not evict entries" do
      store = Store.new(:unlimited_1, max_entries: 0)

      store =
        Enum.reduce(1..100, store, fn i, st ->
          Store.put(st, "key_#{i}", "val_#{i}")
        end)

      stats = Store.stats(store)
      assert stats.size == 100
      assert stats.evictions == 0

      Store.destroy(store)
    end
  end

  describe "overwrite existing key" do
    test "does not increase size" do
      store = Store.new(:overwrite_1, max_entries: 10)

      store = Store.put(store, "key", "v1")
      store = Store.put(store, "key", "v2")

      assert {:hit, "v2", _} = Store.get(store, "key")

      stats = Store.stats(store)
      assert stats.size == 1

      Store.destroy(store)
    end
  end

  describe "sweep_expired" do
    test "removes expired entries" do
      store = Store.new(:sweep_1, max_entries: 0)

      store = Store.put(store, "short", "val", 50)
      store = Store.put(store, "long", "val", 10_000)
      store = Store.put(store, "forever", "val")

      Process.sleep(100)

      store = Store.sweep_expired(store)

      assert {:miss, _} = Store.get(store, "short")
      assert {:hit, "val", _} = Store.get(store, "long")
      assert {:hit, "val", _} = Store.get(store, "forever")

      stats = Store.stats(store)
      assert stats.evictions == 1

      Store.destroy(store)
    end

    test "no-op when nothing is expired" do
      store = Store.new(:sweep_2, max_entries: 0)

      store = Store.put(store, "a", "1", 10_000)
      store = Store.put(store, "b", "2")

      store = Store.sweep_expired(store)

      stats = Store.stats(store)
      assert stats.evictions == 0
      assert stats.size == 2

      Store.destroy(store)
    end
  end

  describe "stats include new fields" do
    test "reports max_entries and eviction_policy" do
      store = Store.new(:stats_1, max_entries: 500, eviction_policy: :fifo)

      stats = Store.stats(store)
      assert stats.max_entries == 500
      assert stats.eviction_policy == :fifo

      Store.destroy(store)
    end
  end
end

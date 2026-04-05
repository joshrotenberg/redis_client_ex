defmodule Redis.Cache.BackendTest do
  use ExUnit.Case, async: true

  alias Redis.Cache.Store

  describe "Store implements Backend behaviour" do
    test "init/1 returns {:ok, store}" do
      {:ok, store} = Store.init(max_entries: 100, eviction_policy: :fifo)

      assert %Store{} = store
      assert store.max_entries == 100
      assert store.eviction_policy == :fifo

      Store.destroy(store)
    end

    test "init/1 with custom name" do
      {:ok, store} = Store.init(name: :custom_backend_test)

      assert %Store{} = store

      Store.destroy(store)
    end

    test "full lifecycle through behaviour callbacks" do
      {:ok, store} = Store.init(max_entries: 5)

      # put and get
      store = Store.put(store, "k1", "v1", nil)
      assert {:hit, "v1", store} = Store.get(store, "k1")

      # put_with_ref and invalidate_refs
      store = Store.put_with_ref(store, {:cmd, "k2"}, "k2", "v2", nil)
      assert {:hit, "v2", store} = Store.get(store, {:cmd, "k2"})
      store = Store.invalidate_refs(store, ["k2"])
      assert {:miss, store} = Store.get(store, {:cmd, "k2"})

      # invalidate
      store = Store.put(store, "k3", "v3", nil)
      store = Store.invalidate(store, ["k3"])
      assert {:miss, store} = Store.get(store, "k3")

      # stats
      stats = Store.stats(store)
      assert is_map(stats)
      assert Map.has_key?(stats, :hits)
      assert Map.has_key?(stats, :misses)

      # sweep_expired
      store = Store.put(store, "exp", "val", 1)
      Process.sleep(10)
      store = Store.sweep_expired(store)
      assert {:miss, store} = Store.get(store, "exp")

      # flush
      store = Store.put(store, "f1", "v1", nil)
      store = Store.flush(store)
      assert {:miss, _store} = Store.get(store, "f1")

      # destroy
      assert :ok = Store.destroy(store)
    end
  end
end

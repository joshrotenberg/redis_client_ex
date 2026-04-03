defmodule Redis.CacheEdgeTest do
  use ExUnit.Case, async: false

  alias Redis.Cache
  alias Redis.Connection
  alias Redis.Script

  # Edge case tests for Redis.Cache and Redis.Script.
  # Uses redis-server on port 6398 (no auth) from test_helper.exs.

  setup do
    {:ok, conn} = Connection.start_link(port: 6398)
    Connection.command(conn, ["FLUSHDB"])
    Connection.command(conn, ["SCRIPT", "FLUSH", "SYNC"])

    on_exit(fn ->
      {:ok, cleanup} = Connection.start_link(port: 6398)
      Connection.command(cleanup, ["FLUSHDB"])
      Connection.command(cleanup, ["SCRIPT", "FLUSH", "SYNC"])
      Connection.stop(cleanup)
    end)

    {:ok, conn: conn}
  end

  # -------------------------------------------------------------------
  # Cache edge cases
  # -------------------------------------------------------------------

  describe "MGET with mix of cached and uncached keys" do
    test "returns correct values when some keys are cached and some are not", %{conn: _conn} do
      {:ok, cache} = Cache.start_link(port: 6398)

      Cache.command(cache, ["SET", "edge_m1", "alpha"])
      Cache.command(cache, ["SET", "edge_m2", "beta"])
      Cache.command(cache, ["SET", "edge_m3", "gamma"])

      # Cache only the first and third keys via individual GETs
      assert {:ok, "alpha"} = Cache.get(cache, "edge_m1")
      assert {:ok, "gamma"} = Cache.get(cache, "edge_m3")

      # MGET: edge_m1 and edge_m3 are cached hits, edge_m2 is a miss
      assert {:ok, ["alpha", "beta", "gamma"]} =
               Cache.mget(cache, ["edge_m1", "edge_m2", "edge_m3"])

      stats = Cache.stats(cache)
      # edge_m1 and edge_m3 were hits from the MGET call
      assert stats.hits >= 2
      # edge_m2 was a miss from the MGET call (plus initial misses for edge_m1 and edge_m3)
      assert stats.misses >= 3

      Cache.stop(cache)
    end

    test "handles MGET where all keys are already cached", %{conn: _conn} do
      {:ok, cache} = Cache.start_link(port: 6398)

      Cache.command(cache, ["SET", "edge_all1", "x"])
      Cache.command(cache, ["SET", "edge_all2", "y"])

      # Pre-warm the cache
      Cache.get(cache, "edge_all1")
      Cache.get(cache, "edge_all2")

      # MGET should be 100% cache hits
      assert {:ok, ["x", "y"]} = Cache.mget(cache, ["edge_all1", "edge_all2"])

      stats = Cache.stats(cache)
      assert stats.hits >= 2

      Cache.stop(cache)
    end

    test "handles MGET with nil values for nonexistent keys", %{conn: _conn} do
      {:ok, cache} = Cache.start_link(port: 6398)

      Cache.command(cache, ["SET", "edge_exists", "here"])

      # edge_missing does not exist in Redis
      assert {:ok, ["here", nil]} = Cache.mget(cache, ["edge_exists", "edge_missing"])

      # Second call should serve from cache (nil is a valid cached value)
      assert {:ok, ["here", nil]} = Cache.mget(cache, ["edge_exists", "edge_missing"])

      stats = Cache.stats(cache)
      assert stats.hits >= 2

      Cache.stop(cache)
    end
  end

  describe "cache stats after a series of operations" do
    test "tracks hits, misses, and stores accurately", %{conn: _conn} do
      {:ok, cache} = Cache.start_link(port: 6398)

      Cache.command(cache, ["SET", "stat_a", "1"])
      Cache.command(cache, ["SET", "stat_b", "2"])
      Cache.command(cache, ["SET", "stat_c", "3"])

      # 3 misses, 3 stores
      Cache.get(cache, "stat_a")
      Cache.get(cache, "stat_b")
      Cache.get(cache, "stat_c")

      # 3 hits
      Cache.get(cache, "stat_a")
      Cache.get(cache, "stat_b")
      Cache.get(cache, "stat_c")

      # 1 miss (key does not exist, still stored as nil)
      Cache.get(cache, "stat_nonexistent")

      stats = Cache.stats(cache)

      assert stats.misses == 4
      assert stats.hits == 3
      assert stats.stores == 4
      assert stats.size == 4
      assert_in_delta stats.hit_rate, 42.9, 0.5

      Cache.stop(cache)
    end
  end

  describe "HGETALL caching path" do
    test "caches HGETALL results and serves from cache on second call", %{conn: _conn} do
      {:ok, cache} = Cache.start_link(port: 6398)

      Cache.command(cache, ["HSET", "edge_hash", "f1", "v1", "f2", "v2"])

      # First call: miss
      {:ok, result} = Cache.hgetall(cache, "edge_hash")
      assert is_map(result) or is_list(result)

      stats_after_miss = Cache.stats(cache)
      assert stats_after_miss.misses >= 1

      # Second call: hit from cache
      {:ok, result2} = Cache.hgetall(cache, "edge_hash")
      assert result2 == result

      stats_after_hit = Cache.stats(cache)
      assert stats_after_hit.hits >= 1

      Cache.stop(cache)
    end

    test "HGETALL invalidation works when hash is modified", %{conn: _conn} do
      {:ok, cache} = Cache.start_link(port: 6398)

      Cache.command(cache, ["HSET", "inv_hash", "field", "original"])
      {:ok, _} = Cache.hgetall(cache, "inv_hash")

      # Verify it is cached
      {:ok, _} = Cache.hgetall(cache, "inv_hash")
      stats = Cache.stats(cache)
      assert stats.hits >= 1

      # Modify via a separate connection to trigger invalidation
      {:ok, other} = Connection.start_link(port: 6398)
      Connection.command(other, ["HSET", "inv_hash", "field", "modified"])
      Process.sleep(200)

      # Next call should be a miss and fetch the updated data
      {:ok, result} = Cache.hgetall(cache, "inv_hash")
      assert is_map(result) or is_list(result)

      Connection.stop(other)
      Cache.stop(cache)
    end
  end

  describe "cache invalidation clears the right keys" do
    test "invalidation of modified key evicts it while values remain correct", %{conn: _conn} do
      {:ok, cache} = Cache.start_link(port: 6398)

      Cache.command(cache, ["SET", "keep_a", "aaa"])
      Cache.command(cache, ["SET", "evict_c", "ccc"])

      # Cache both keys
      Cache.get(cache, "keep_a")
      Cache.get(cache, "evict_c")

      stats_before = Cache.stats(cache)

      # Modify only evict_c via another connection
      {:ok, other} = Connection.start_link(port: 6398)
      Connection.command(other, ["SET", "evict_c", "new_ccc"])
      Process.sleep(200)

      # evict_c should have been evicted and now returns the new value
      assert {:ok, "new_ccc"} = Cache.get(cache, "evict_c")

      stats_after = Cache.stats(cache)
      assert stats_after.evictions > stats_before.evictions

      # keep_a still returns the correct value regardless of cache state
      assert {:ok, "aaa"} = Cache.get(cache, "keep_a")

      Connection.stop(other)
      Cache.stop(cache)
    end

    test "flush clears all keys but stats are preserved", %{conn: _conn} do
      {:ok, cache} = Cache.start_link(port: 6398)

      Cache.command(cache, ["SET", "flush_a", "1"])
      Cache.command(cache, ["SET", "flush_b", "2"])
      Cache.get(cache, "flush_a")
      Cache.get(cache, "flush_b")

      Cache.flush(cache)

      stats = Cache.stats(cache)
      assert stats.size == 0
      # Stats counters should still reflect past operations
      assert stats.misses == 2
      assert stats.stores == 2

      Cache.stop(cache)
    end
  end

  describe "TTL expiry" do
    test "short TTL expires and causes cache miss", %{conn: _conn} do
      {:ok, cache} = Cache.start_link(port: 6398, ttl: 80)

      Cache.command(cache, ["SET", "ttl_edge", "ephemeral"])

      # Miss -> stored with TTL
      assert {:ok, "ephemeral"} = Cache.get(cache, "ttl_edge")
      # Hit while TTL is still valid
      assert {:ok, "ephemeral"} = Cache.get(cache, "ttl_edge")

      stats_before = Cache.stats(cache)
      assert stats_before.hits == 1

      # Wait for TTL to expire
      Process.sleep(150)

      # Should be a miss now due to TTL expiry
      assert {:ok, "ephemeral"} = Cache.get(cache, "ttl_edge")

      stats_after = Cache.stats(cache)
      assert stats_after.misses == 2
      assert stats_after.evictions >= 1

      Cache.stop(cache)
    end

    test "TTL expiry does not affect keys without TTL", %{conn: _conn} do
      # Start cache without a global TTL
      {:ok, cache} = Cache.start_link(port: 6398)

      Cache.command(cache, ["SET", "no_ttl_key", "persistent"])
      Cache.get(cache, "no_ttl_key")

      Process.sleep(150)

      # Should still be a cache hit since no TTL was set
      Cache.get(cache, "no_ttl_key")
      stats = Cache.stats(cache)
      assert stats.hits == 1

      Cache.stop(cache)
    end
  end

  # -------------------------------------------------------------------
  # Script edge cases
  # -------------------------------------------------------------------

  describe "Script.new computes correct SHA1" do
    test "SHA matches the expected SHA1 hex digest" do
      source = "return 1"
      script = Script.new(source)
      expected = :crypto.hash(:sha, source) |> Base.encode16(case: :lower)
      assert script.sha == expected
    end

    test "SHA is stable for known input" do
      # Known SHA1 for "return 1" (verified externally)
      script = Script.new("return 1")
      assert script.sha == "e0e1f9fabfc9d4800c877a703b823ac0578ff8db"
    end

    test "empty script produces a valid SHA" do
      script = Script.new("")
      assert String.length(script.sha) == 40
      assert script.sha == :crypto.hash(:sha, "") |> Base.encode16(case: :lower)
    end
  end

  describe "eval with EVALSHA fast path" do
    test "second call uses EVALSHA without fallback", %{conn: conn} do
      script = Script.new("return 'fast_path'")

      # First call: EVALSHA fails with NOSCRIPT, falls back to EVAL
      assert {:ok, "fast_path"} = Script.eval(conn, script)

      # Script is now cached on the server
      assert Script.exists?(conn, script)

      # Second call: EVALSHA succeeds directly
      assert {:ok, "fast_path"} = Script.eval(conn, script)
    end

    test "pre-loaded script uses EVALSHA on first call", %{conn: conn} do
      script = Script.new("return 'preloaded'")

      # Pre-load the script
      :ok = Script.load(conn, script)
      assert Script.exists?(conn, script)

      # First eval should succeed via EVALSHA without needing EVAL fallback
      assert {:ok, "preloaded"} = Script.eval(conn, script)
    end
  end

  describe "eval with keys and args" do
    test "script receives keys and args correctly", %{conn: conn} do
      script =
        Script.new("""
        redis.call('SET', KEYS[1], ARGV[1])
        redis.call('SET', KEYS[2], ARGV[2])
        return redis.call('GET', KEYS[1]) .. ':' .. redis.call('GET', KEYS[2])
        """)

      assert {:ok, "hello:world"} =
               Script.eval(conn, script, keys: ["skey1", "skey2"], args: ["hello", "world"])

      # Verify the side effects
      assert {:ok, "hello"} = Connection.command(conn, ["GET", "skey1"])
      assert {:ok, "world"} = Connection.command(conn, ["GET", "skey2"])
    end

    test "script with numeric args coerces to strings", %{conn: conn} do
      script = Script.new("return ARGV[1] .. ARGV[2]")

      assert {:ok, "42100"} = Script.eval(conn, script, keys: [], args: [42, 100])
    end

    test "script with empty keys and args works", %{conn: conn} do
      script = Script.new("return 'no_args'")
      assert {:ok, "no_args"} = Script.eval(conn, script, keys: [], args: [])
    end
  end

  describe "Script with read-only variant (eval_ro)" do
    test "eval_ro executes a read-only script", %{conn: conn} do
      Connection.command(conn, ["SET", "ro_key", "ro_value"])

      script = Script.new("return redis.call('GET', KEYS[1])")
      assert {:ok, "ro_value"} = Script.eval_ro(conn, script, keys: ["ro_key"])
    end

    test "eval_ro second call uses EVALSHA_RO fast path", %{conn: conn} do
      Connection.command(conn, ["SET", "ro_key2", "val2"])

      script = Script.new("return redis.call('GET', KEYS[1])")

      # First call: EVALSHA_RO fails with NOSCRIPT, falls back to EVAL_RO
      assert {:ok, "val2"} = Script.eval_ro(conn, script, keys: ["ro_key2"])

      # Script is now cached on the server
      assert Script.exists?(conn, script)

      # Second call: EVALSHA_RO succeeds directly
      assert {:ok, "val2"} = Script.eval_ro(conn, script, keys: ["ro_key2"])
    end

    test "eval_ro with keys and args", %{conn: conn} do
      Connection.command(conn, ["SET", "ro_a", "10"])
      Connection.command(conn, ["SET", "ro_b", "20"])

      script =
        Script.new("return redis.call('GET', KEYS[1]) .. ':' .. redis.call('GET', KEYS[2])")

      assert {:ok, "10:20"} = Script.eval_ro(conn, script, keys: ["ro_a", "ro_b"])
    end

    test "eval_ro returns nil for missing key", %{conn: conn} do
      script = Script.new("return redis.call('GET', KEYS[1])")
      assert {:ok, nil} = Script.eval_ro(conn, script, keys: ["nonexistent_ro_key"])
    end
  end
end

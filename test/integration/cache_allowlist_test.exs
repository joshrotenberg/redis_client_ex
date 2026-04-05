defmodule Redis.Cache.AllowlistIntegrationTest do
  use ExUnit.Case, async: false

  alias Redis.Cache
  alias Redis.Connection

  describe "cached_command with default allowlist" do
    test "caches LLEN results" do
      {:ok, cache} = Cache.start_link(port: 6398)

      Cache.command(cache, ["RPUSH", "al_list", "a", "b", "c"])

      # First call: miss
      assert {:ok, 3} = Cache.cached_command(cache, ["LLEN", "al_list"])
      stats = Cache.stats(cache)
      assert stats.misses >= 1

      # Second call: hit
      assert {:ok, 3} = Cache.cached_command(cache, ["LLEN", "al_list"])
      stats = Cache.stats(cache)
      assert stats.hits >= 1

      Cache.command(cache, ["DEL", "al_list"])
      Cache.stop(cache)
    end

    test "caches LRANGE results" do
      {:ok, cache} = Cache.start_link(port: 6398)

      Cache.command(cache, ["RPUSH", "al_lrange", "a", "b", "c"])

      assert {:ok, ["a", "b", "c"]} =
               Cache.cached_command(cache, ["LRANGE", "al_lrange", "0", "-1"])

      # Same args -> cache hit
      assert {:ok, ["a", "b", "c"]} =
               Cache.cached_command(cache, ["LRANGE", "al_lrange", "0", "-1"])

      stats = Cache.stats(cache)
      assert stats.hits >= 1

      # Different args -> cache miss (different range)
      assert {:ok, ["a"]} = Cache.cached_command(cache, ["LRANGE", "al_lrange", "0", "0"])
      stats = Cache.stats(cache)
      assert stats.misses >= 2

      Cache.command(cache, ["DEL", "al_lrange"])
      Cache.stop(cache)
    end

    test "caches SCARD results" do
      {:ok, cache} = Cache.start_link(port: 6398)

      Cache.command(cache, ["SADD", "al_set", "a", "b", "c"])

      assert {:ok, 3} = Cache.cached_command(cache, ["SCARD", "al_set"])
      assert {:ok, 3} = Cache.cached_command(cache, ["SCARD", "al_set"])

      stats = Cache.stats(cache)
      assert stats.hits >= 1

      Cache.command(cache, ["DEL", "al_set"])
      Cache.stop(cache)
    end

    test "invalidation clears generic cached entries" do
      {:ok, cache} = Cache.start_link(port: 6398)

      Cache.command(cache, ["RPUSH", "al_inv", "x", "y"])

      # Cache it
      assert {:ok, 2} = Cache.cached_command(cache, ["LLEN", "al_inv"])
      assert {:ok, 2} = Cache.cached_command(cache, ["LLEN", "al_inv"])

      # Modify via separate connection to trigger invalidation
      {:ok, other} = Connection.start_link(port: 6398)
      Connection.command(other, ["RPUSH", "al_inv", "z"])
      Process.sleep(200)

      # Should be a miss now, returning updated value
      assert {:ok, 3} = Cache.cached_command(cache, ["LLEN", "al_inv"])

      stats = Cache.stats(cache)
      assert stats.evictions >= 1

      Connection.stop(other)
      Cache.command(cache, ["DEL", "al_inv"])
      Cache.stop(cache)
    end

    test "non-allowlisted commands pass through without caching" do
      {:ok, cache} = Cache.start_link(port: 6398)

      Cache.command(cache, ["SET", "al_passthrough", "val"])

      # SET is not in the allowlist — should pass through
      assert {:ok, "OK"} = Cache.cached_command(cache, ["SET", "al_passthrough", "newval"])

      stats = Cache.stats(cache)
      assert stats.stores == 0
      assert stats.hits == 0

      Cache.command(cache, ["DEL", "al_passthrough"])
      Cache.stop(cache)
    end
  end

  describe "per-command TTL override" do
    test "command-specific TTL expires independently of global TTL" do
      {:ok, cache} = Cache.start_link(port: 6398, ttl: 10_000, cacheable: [{"LLEN", ttl: 80}])

      Cache.command(cache, ["RPUSH", "al_ttl", "a"])

      # Cache with command-specific 80ms TTL
      assert {:ok, 1} = Cache.cached_command(cache, ["LLEN", "al_ttl"])
      assert {:ok, 1} = Cache.cached_command(cache, ["LLEN", "al_ttl"])

      stats = Cache.stats(cache)
      assert stats.hits >= 1

      # Wait for command TTL to expire
      Process.sleep(150)

      # Should be a miss now
      assert {:ok, 1} = Cache.cached_command(cache, ["LLEN", "al_ttl"])
      stats = Cache.stats(cache)
      assert stats.misses >= 2

      Cache.command(cache, ["DEL", "al_ttl"])
      Cache.stop(cache)
    end
  end

  describe "custom cacheable function" do
    test "function controls which commands are cached" do
      cacheable = fn
        ["LLEN" | _] -> true
        ["SCARD" | _] -> {:ok, 5_000}
        _ -> false
      end

      {:ok, cache} = Cache.start_link(port: 6398, cacheable: cacheable)

      Cache.command(cache, ["RPUSH", "al_fn_list", "a"])
      Cache.command(cache, ["SET", "al_fn_str", "val"])

      # LLEN is cacheable
      assert {:ok, 1} = Cache.cached_command(cache, ["LLEN", "al_fn_list"])
      assert {:ok, 1} = Cache.cached_command(cache, ["LLEN", "al_fn_list"])
      stats = Cache.stats(cache)
      assert stats.hits >= 1

      # GET is not cacheable via this function
      assert {:ok, "val"} = Cache.cached_command(cache, ["GET", "al_fn_str"])
      assert {:ok, "val"} = Cache.cached_command(cache, ["GET", "al_fn_str"])
      stats = Cache.stats(cache)
      # No new cache hits for GET
      assert stats.hits == 1

      Cache.command(cache, ["DEL", "al_fn_list", "al_fn_str"])
      Cache.stop(cache)
    end
  end

  describe "multiple cached commands for same key" do
    test "different commands on same key are cached independently" do
      {:ok, cache} = Cache.start_link(port: 6398)

      Cache.command(cache, ["RPUSH", "al_multi", "a", "b", "c"])

      # Cache LLEN and LRANGE for the same key
      assert {:ok, 3} = Cache.cached_command(cache, ["LLEN", "al_multi"])

      assert {:ok, ["a", "b", "c"]} =
               Cache.cached_command(cache, ["LRANGE", "al_multi", "0", "-1"])

      # Both should be cache hits
      assert {:ok, 3} = Cache.cached_command(cache, ["LLEN", "al_multi"])

      assert {:ok, ["a", "b", "c"]} =
               Cache.cached_command(cache, ["LRANGE", "al_multi", "0", "-1"])

      stats = Cache.stats(cache)
      assert stats.hits >= 2

      # Invalidation should clear both
      {:ok, other} = Connection.start_link(port: 6398)
      Connection.command(other, ["RPUSH", "al_multi", "d"])
      Process.sleep(200)

      # Both should miss now
      assert {:ok, 4} = Cache.cached_command(cache, ["LLEN", "al_multi"])

      assert {:ok, ["a", "b", "c", "d"]} =
               Cache.cached_command(cache, ["LRANGE", "al_multi", "0", "-1"])

      Connection.stop(other)
      Cache.command(cache, ["DEL", "al_multi"])
      Cache.stop(cache)
    end
  end
end

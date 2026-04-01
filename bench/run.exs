# Redis vs Redix Benchmark Suite
#
# Run with: MIX_ENV=bench mix run bench/run.exs
#
# Requires redis-server on port 6399 (started automatically via redis_server_wrapper)

alias Redis.Connection, as: RConn
alias Redis.Connection.Pool, as: RPool
alias Redis.Cache

IO.puts("\n=== Redis vs Redix Benchmark Suite ===\n")

# Start a redis-server for benchmarking
{:ok, _srv} = RedisServerWrapper.Server.start_link(port: 6390, password: nil)
Process.sleep(500)

# --- Setup connections ---

{:ok, redis_ex} = RConn.start_link(port: 6390)
{:ok, redis_ex_resp2} = RConn.start_link(port: 6390, protocol: :resp2)
{:ok, redix} = Redix.start_link(host: "127.0.0.1", port: 6390)

# Pre-populate test data
RConn.command(redis_ex, ["SET", "bench:key", "bench:value"])
RConn.command(redis_ex, ["HSET", "bench:hash", "f1", "v1", "f2", "v2", "f3", "v3"])
for i <- 1..100, do: RConn.command(redis_ex, ["SET", "bench:key:#{i}", "value:#{i}"])

# ============================================================
# 1. Single Command Throughput
# ============================================================

IO.puts("--- 1. Single Command: GET ---\n")

Benchee.run(
  %{
    "Redis (RESP3)" => fn -> RConn.command(redis_ex, ["GET", "bench:key"]) end,
    "Redis (RESP2)" => fn -> RConn.command(redis_ex_resp2, ["GET", "bench:key"]) end,
    "Redix" => fn -> Redix.command(redix, ["GET", "bench:key"]) end
  },
  time: 5,
  warmup: 1,
  print: [configuration: false]
)

IO.puts("\n--- 2. Single Command: SET ---\n")

Benchee.run(
  %{
    "Redis (RESP3)" => fn -> RConn.command(redis_ex, ["SET", "bench:set", "val"]) end,
    "Redis (RESP2)" => fn -> RConn.command(redis_ex_resp2, ["SET", "bench:set", "val"]) end,
    "Redix" => fn -> Redix.command(redix, ["SET", "bench:set", "val"]) end
  },
  time: 5,
  warmup: 1,
  print: [configuration: false]
)

# ============================================================
# 2. Pipeline Throughput
# ============================================================

pipeline_10 = for i <- 1..10, do: ["SET", "pipe:#{i}", "v#{i}"]
pipeline_100 = for i <- 1..100, do: ["SET", "pipe:#{i}", "v#{i}"]

IO.puts("\n--- 3. Pipeline: 10 commands ---\n")

Benchee.run(
  %{
    "Redis" => fn -> RConn.pipeline(redis_ex, pipeline_10) end,
    "Redix" => fn -> Redix.pipeline(redix, pipeline_10) end
  },
  time: 5,
  warmup: 1,
  print: [configuration: false]
)

IO.puts("\n--- 4. Pipeline: 100 commands ---\n")

Benchee.run(
  %{
    "Redis" => fn -> RConn.pipeline(redis_ex, pipeline_100) end,
    "Redix" => fn -> Redix.pipeline(redix, pipeline_100) end
  },
  time: 5,
  warmup: 1,
  print: [configuration: false]
)

# ============================================================
# 3. Protocol Decode Performance
# ============================================================

IO.puts("\n--- 5. HGETALL (map decode, RESP3 vs RESP2) ---\n")

Benchee.run(
  %{
    "Redis RESP3 (native map)" => fn -> RConn.command(redis_ex, ["HGETALL", "bench:hash"]) end,
    "Redis RESP2 (flat list)" => fn -> RConn.command(redis_ex_resp2, ["HGETALL", "bench:hash"]) end,
    "Redix (flat list)" => fn -> Redix.command(redix, ["HGETALL", "bench:hash"]) end
  },
  time: 5,
  warmup: 1,
  print: [configuration: false]
)

# ============================================================
# 4. Connection Pool
# ============================================================

{:ok, pool_3} = RPool.start_link(pool_size: 3, port: 6390)
{:ok, pool_10} = RPool.start_link(pool_size: 10, port: 6390)

IO.puts("\n--- 6. Pool: 50 concurrent GETs (pool=3 vs pool=10 vs single) ---\n")

run_concurrent = fn conn_or_pool, n, mod ->
  tasks = for _ <- 1..n, do: Task.async(fn -> mod.command(conn_or_pool, ["GET", "bench:key"]) end)
  Task.await_many(tasks, 10_000)
end

Benchee.run(
  %{
    "Single connection" => fn -> run_concurrent.(redis_ex, 50, RConn) end,
    "Pool (3 conns)" => fn -> run_concurrent.(pool_3, 50, RPool) end,
    "Pool (10 conns)" => fn -> run_concurrent.(pool_10, 50, RPool) end,
    "Redix (single)" => fn -> run_concurrent.(redix, 50, Redix) end
  },
  time: 5,
  warmup: 1,
  print: [configuration: false]
)

# ============================================================
# 5. Client-Side Cache
# ============================================================

{:ok, cache} = Cache.start_link(port: 6390)
# Prime the cache
Cache.get(cache, "bench:key")

IO.puts("\n--- 7. Client-Side Cache: hit vs miss vs Redix ---\n")

Benchee.run(
  %{
    "Cache HIT (ETS)" => fn -> Cache.get(cache, "bench:key") end,
    "Cache MISS (Redis)" => fn ->
      Cache.flush(cache)
      Cache.get(cache, "bench:key")
    end,
    "Redix GET" => fn -> Redix.command(redix, ["GET", "bench:key"]) end
  },
  time: 5,
  warmup: 1,
  print: [configuration: false]
)

# ============================================================
# 6. Pure Protocol Encode/Decode
# ============================================================

alias Redis.Protocol.RESP3
alias Redis.Protocol.RESP2

simple_resp3 = "+OK\r\n"
bulk_resp3 = "$11\r\nhello world\r\n"
array_resp3 = "*3\r\n$3\r\nfoo\r\n$3\r\nbar\r\n$3\r\nbaz\r\n"
map_resp3 = "%2\r\n+key1\r\n:1\r\n+key2\r\n:2\r\n"

large_array = "*100\r\n" <> String.duplicate("$5\r\nhello\r\n", 100)

IO.puts("\n--- 8. Protocol Decode: RESP3 vs RESP2 ---\n")

Benchee.run(
  %{
    "RESP3 simple string" => fn -> RESP3.decode(simple_resp3) end,
    "RESP2 simple string" => fn -> RESP2.decode(simple_resp3) end,
    "RESP3 bulk string" => fn -> RESP3.decode(bulk_resp3) end,
    "RESP3 array (3)" => fn -> RESP3.decode(array_resp3) end,
    "RESP3 map (2 pairs)" => fn -> RESP3.decode(map_resp3) end,
    "RESP3 array (100)" => fn -> RESP3.decode(large_array) end,
    "RESP2 array (100)" => fn -> RESP2.decode(large_array) end
  },
  time: 3,
  warmup: 1,
  print: [configuration: false]
)

IO.puts("\n--- 9. Protocol Encode ---\n")

cmd_small = ["GET", "key"]
cmd_large = ["MSET"] ++ Enum.flat_map(1..50, &["key:#{&1}", "val:#{&1}"])

Benchee.run(
  %{
    "RESP3 encode (small)" => fn -> RESP3.encode(cmd_small) end,
    "RESP3 encode (large 101 args)" => fn -> RESP3.encode(cmd_large) end
  },
  time: 3,
  warmup: 1,
  print: [configuration: false]
)

# ============================================================
# Cleanup
# ============================================================

RConn.stop(redis_ex)
RConn.stop(redis_ex_resp2)
Redix.stop(redix)
RPool.stop(pool_3)
RPool.stop(pool_10)
Cache.stop(cache)

IO.puts("\n=== Benchmark Complete ===\n")

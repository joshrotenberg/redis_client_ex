# Redis

Modern, full-featured Redis client for Elixir built on OTP.

RESP3 native. Cluster-aware. Client-side caching. Resilience built in. Zero required dependencies.

## Features

- **RESP3 native** with RESP2 fallback for older servers
- **Cluster** with topology discovery, hash slot routing, MOVED/ASK redirects, cross-slot pipeline splitting
- **Sentinel** with master resolution, role verification, proactive failover via `+switch-master`
- **Pub/Sub** with pattern subscriptions, subscriber process monitoring, sharded pub/sub (Redis 7+)
- **Client-side caching** via RESP3 server-assisted invalidation + ETS (197x faster than network)
- **Connection pool** with round-robin/random dispatch and dead connection replacement
- **Resilience** patterns: circuit breaker, retry with backoff, request coalescing, bulkhead, chaos testing
- **341 command builders** across 21 modules covering all Redis data types, JSON, Search, TimeSeries, Bloom, and more
- **Telemetry** events for connection lifecycle and command pipeline
- **URI parsing**, MFA dynamic passwords, TLS, unix sockets

## Quick Start

```elixir
# Single connection
{:ok, conn} = Redis.start_link(port: 6379)
{:ok, "OK"} = Redis.command(conn, ["SET", "hello", "world"])
{:ok, "world"} = Redis.command(conn, ["GET", "hello"])

# URI-based connection
{:ok, conn} = Redis.start_link("redis://:secret@myhost:6380/2")

# Pipeline
{:ok, ["OK", "OK", "1"]} = Redis.pipeline(conn, [
  ["SET", "a", "1"],
  ["SET", "b", "2"],
  ["GET", "a"]
])

# Transaction
{:ok, [1, 2, 3]} = Redis.transaction(conn, [
  ["INCR", "counter"],
  ["INCR", "counter"],
  ["INCR", "counter"]
])
```

## Cluster

```elixir
{:ok, cluster} = Redis.Cluster.start_link(
  nodes: [{"127.0.0.1", 7000}]
)

# Commands are routed to the correct node automatically
Redis.Cluster.command(cluster, ["SET", "mykey", "myvalue"])
Redis.Cluster.command(cluster, ["GET", "mykey"])

# Cross-slot pipelines are split, fanned out, and reassembled
Redis.Cluster.pipeline(cluster, [
  ["SET", "key1", "a"],    # slot X → node A
  ["SET", "key2", "b"],    # slot Y → node B
  ["GET", "key1"],         # slot X → node A
])
# => {:ok, ["OK", "OK", "a"]}
```

## Sentinel

```elixir
{:ok, conn} = Redis.Sentinel.start_link(
  sentinels: [{"sentinel1", 26379}, {"sentinel2", 26379}],
  group: "mymaster",
  role: :primary,
  password: "secret"
)

# Transparently resolves master, reconnects on failover
Redis.Sentinel.command(conn, ["SET", "key", "value"])
```

## Pub/Sub

```elixir
{:ok, ps} = Redis.PubSub.start_link(port: 6379)
Redis.PubSub.subscribe(ps, "events", self())

receive do
  {:redis_pubsub, :message, "events", payload} ->
    IO.puts("Got: #{payload}")
end
```

## Client-Side Caching

```elixir
{:ok, cache} = Redis.Cache.start_link(port: 6379)

Redis.Cache.command(cache, ["SET", "key", "value"])

# First call: cache miss, fetches from Redis (~300us)
{:ok, "value"} = Redis.Cache.get(cache, "key")

# Second call: cache hit, served from ETS (~1.5us, 197x faster)
{:ok, "value"} = Redis.Cache.get(cache, "key")

# Another client modifies "key" -> Redis pushes invalidation -> ETS evicted
# Next call fetches the new value automatically
```

## Connection Pool

```elixir
{:ok, pool} = Redis.Connection.Pool.start_link(
  pool_size: 10,
  port: 6379
)

Redis.Connection.Pool.command(pool, ["GET", "key"])
```

## Resilience

```elixir
{:ok, conn} = Redis.Resilience.start_link(
  port: 6379,
  retry: [max_attempts: 3, backoff: :exponential],
  circuit_breaker: [failure_threshold: 5, reset_timeout: 5_000],
  coalesce: true,
  bulkhead: [max_concurrent: 50]
)

# Same API, with retry + circuit breaker + deduplication + concurrency limiting
Redis.Resilience.command(conn, ["GET", "key"])
```

## Command Builders

Pure functions that return command lists. Use them with any connection type.

```elixir
alias Redis.Commands.{String, Hash, JSON, Search}

# String
String.set("key", "value", ex: 60, nx: true)
#=> ["SET", "key", "value", "EX", "60", "NX"]

# Hash
Hash.hset("user:1", [{"name", "Alice"}, {"age", "30"}])
#=> ["HSET", "user:1", "name", "Alice", "age", "30"]

# JSON (Redis 8+)
JSON.set("doc", %{name: "Alice", scores: [1, 2, 3]})
#=> ["JSON.SET", "doc", "$", "{\"name\":\"Alice\",\"scores\":[1,2,3]}"]

# Search (Redis 8+)
Search.create("idx:users", :json,
  prefix: "user:",
  schema: [
    {"$.name", :text, as: "name"},
    {"$.age", :numeric, as: "age", sortable: true}
  ]
)

Search.search("idx:users", "@name:Alice", sortby: {"age", :desc}, limit: {0, 10})
```

### Available Command Modules

| Module | Commands | Coverage |
|--------|----------|----------|
| `String` | GET, SET, MGET, INCR, APPEND, GETEX, ... | 22 |
| `Hash` | HSET, HGET, HGETALL, HINCRBY, HSCAN, ... | 16 |
| `List` | LPUSH, RPUSH, LPOP, BLPOP, LMOVE, ... | 22 |
| `Set` | SADD, SMEMBERS, SINTER, SUNION, SSCAN, ... | 17 |
| `SortedSet` | ZADD, ZRANGE, ZINCRBY, ZUNION, BZPOPMAX, ... | 35 |
| `Stream` | XADD, XREAD, XREADGROUP, XACK, XINFO, ... | 21 |
| `Key` | DEL, EXPIRE, SCAN, COPY, SORT, MIGRATE, ... | 29 |
| `Server` | PING, INFO, CONFIG, CLIENT, ACL, SLOWLOG, ... | 46 |
| `JSON` | JSON.SET, JSON.GET, JSON.ARRAPPEND, ... | 20 |
| `Search` | FT.CREATE, FT.SEARCH, FT.AGGREGATE, ... | 12 |
| `Script` | EVAL, EVALSHA, FCALL, FUNCTION, ... | 16 |
| `Geo` | GEOADD, GEOSEARCH, GEOSEARCHSTORE, ... | 8 |
| `Bitmap` | SETBIT, GETBIT, BITCOUNT, BITFIELD, ... | 7 |
| `HyperLogLog` | PFADD, PFCOUNT, PFMERGE | 3 |
| `Bloom` | BF.ADD, BF.EXISTS, BF.RESERVE, ... | 9 |
| `Cuckoo` | CF.ADD, CF.EXISTS, CF.RESERVE, ... | 9 |
| `TopK` | TOPK.ADD, TOPK.QUERY, TOPK.RESERVE, ... | 7 |
| `CMS` | CMS.INITBYDIM, CMS.INCRBY, CMS.QUERY, ... | 6 |
| `TDigest` | TDIGEST.ADD, TDIGEST.QUANTILE, ... | 14 |
| `TimeSeries` | TS.ADD, TS.RANGE, TS.MRANGE, ... | 15 |
| `PubSub` | PUBLISH, PUBSUB CHANNELS/NUMSUB, ... | 7 |
| **Total** | | **341** |

## Lua Scripts

```elixir
script = Redis.Script.new("return redis.call('GET', KEYS[1])")

# First call: EVALSHA fails, falls back to EVAL (caches the script)
{:ok, "value"} = Redis.Script.eval(conn, script, keys: ["mykey"])

# Second call: EVALSHA succeeds (cached on server)
{:ok, "value"} = Redis.Script.eval(conn, script, keys: ["mykey"])
```

## Supervision

```elixir
children = [
  {Redis.Connection, port: 6379, name: :redis},
  {Redis.Connection.Pool, pool_size: 10, port: 6379, name: :redis_pool}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

## Installation

```elixir
def deps do
  [
    {:redis, "~> 0.1.0"}
  ]
end
```

## Benchmarks

Compared against Redix (the current standard Elixir Redis client):

| Benchmark | Redis | Redix | Notes |
|-----------|-------|-------|-------|
| GET | 3,280/s | 3,250/s | Parity |
| SET | 3,290/s | 3,210/s | Parity |
| Pipeline (10) | 3,250/s | 3,170/s | Parity |
| Pipeline (100) | 2,490/s | 2,540/s | Parity |
| Cache HIT | **638,850/s** | N/A | 197x faster than network |
| 50 concurrent GETs | **1,490/s** | 940/s | 1.6x faster |

Network latency dominates — both clients perform equally on I/O-bound operations.
The cache hit path (ETS) is 197x faster than any network round-trip.

## License

MIT

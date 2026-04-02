# Redis

[![CI](https://github.com/joshrotenberg/redis_ex/actions/workflows/ci.yml/badge.svg)](https://github.com/joshrotenberg/redis_ex/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/redis_client_ex.svg)](https://hex.pm/packages/redis_client_ex)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/redis_client_ex)
[![License](https://img.shields.io/hexpm/l/redis_client_ex.svg)](LICENSE)

Modern, full-featured Redis client for Elixir built on OTP.

RESP3 native. Cluster-aware. Client-side caching. Resilience built in. Zero required dependencies.

## Features

- **RESP3 native** with RESP2 fallback for older servers
- **Cluster** with topology discovery, hash slot routing, MOVED/ASK redirects, cross-slot pipeline splitting
- **Sentinel** with master resolution, role verification, proactive failover via `+switch-master`
- **Pub/Sub** with pattern subscriptions, sharded pub/sub (Redis 7+)
- **Client-side caching** via RESP3 server-assisted invalidation + ETS
- **Connection pool** with round-robin/random dispatch
- **Resilience** patterns: circuit breaker, retry with backoff, request coalescing, bulkhead
- **341 command builders** across 21 modules (strings, hashes, lists, sets, sorted sets, streams, JSON, search, time series, probabilistic data structures, and more)
- **Lua scripting** with automatic EVALSHA/EVAL fallback
- **Telemetry** events for connection lifecycle and command pipeline

## Installation

```elixir
def deps do
  [
    {:redis_client_ex, "~> 0.1"}
  ]
end
```

The Hex package is `redis_client_ex`, but the application and all modules use the `Redis` namespace.

## Quick Start

```elixir
{:ok, conn} = Redis.start_link(port: 6379)

# Commands
{:ok, "OK"} = Redis.command(conn, ["SET", "hello", "world"])
{:ok, "world"} = Redis.command(conn, ["GET", "hello"])

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

Connections also accept URIs:

```elixir
{:ok, conn} = Redis.start_link("redis://:secret@myhost:6380/2")
```

## Command Builders

Pure functions that return command lists. Use them with any connection type.

```elixir
alias Redis.Commands.{String, Hash, JSON, Search}

String.set("key", "value", ex: 60, nx: true)
#=> ["SET", "key", "value", "EX", "60", "NX"]

Hash.hset("user:1", [{"name", "Alice"}, {"age", "30"}])
#=> ["HSET", "user:1", "name", "Alice", "age", "30"]

JSON.set("doc", %{name: "Alice", scores: [1, 2, 3]})
#=> ["JSON.SET", "doc", "$", "{\"name\":\"Alice\",\"scores\":[1,2,3]}"]

Search.create("idx:users", :json,
  prefix: "user:",
  schema: [
    {"$.name", :text, as: "name"},
    {"$.age", :numeric, as: "age", sortable: true}
  ]
)
```

21 command modules are available: `String`, `Hash`, `List`, `Set`, `SortedSet`, `Stream`, `Key`, `Server`, `JSON`, `Search`, `Script`, `Geo`, `Bitmap`, `HyperLogLog`, `Bloom`, `Cuckoo`, `TopK`, `CMS`, `TDigest`, `TimeSeries`, and `PubSub`. See the [docs](https://hexdocs.pm/redis_client_ex) for full coverage.

## Cluster

```elixir
{:ok, cluster} = Redis.Cluster.start_link(
  nodes: [{"127.0.0.1", 7000}]
)

Redis.Cluster.command(cluster, ["SET", "mykey", "myvalue"])
Redis.Cluster.command(cluster, ["GET", "mykey"])

# Cross-slot pipelines are split, fanned out, and reassembled
Redis.Cluster.pipeline(cluster, [
  ["SET", "key1", "a"],
  ["SET", "key2", "b"],
  ["GET", "key1"],
])
#=> {:ok, ["OK", "OK", "a"]}
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

# Cache miss -- fetches from Redis
{:ok, "value"} = Redis.Cache.get(cache, "key")

# Cache hit -- served from ETS, 197x faster than network
{:ok, "value"} = Redis.Cache.get(cache, "key")

# When another client modifies "key", Redis pushes invalidation
# and the next call fetches the new value automatically
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

# Same API, with all resilience patterns composed
Redis.Resilience.command(conn, ["GET", "key"])
```

## Supervision

```elixir
children = [
  {Redis.Connection, port: 6379, name: :redis},
  {Redis.Connection.Pool, pool_size: 10, port: 6379, name: :redis_pool}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

## Benchmarks

Compared against [Redix](https://hex.pm/packages/redix):

| Benchmark | Redis | Redix | Notes |
|-----------|-------|-------|-------|
| GET | 3,280/s | 3,250/s | Parity |
| SET | 3,290/s | 3,210/s | Parity |
| Pipeline (10) | 3,250/s | 3,170/s | Parity |
| Cache HIT | **638,850/s** | N/A | 197x faster than network |
| 50 concurrent GETs | **1,490/s** | 940/s | 1.6x faster |

## License

MIT

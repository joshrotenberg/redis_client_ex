# Redis

[![CI](https://github.com/joshrotenberg/redis_ex/actions/workflows/ci.yml/badge.svg)](https://github.com/joshrotenberg/redis_ex/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/redis_client_ex.svg)](https://hex.pm/packages/redis_client_ex)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/redis_client_ex)
[![License](https://img.shields.io/hexpm/l/redis_client_ex.svg)](LICENSE)

Modern, full-featured Redis client for Elixir built on OTP.

RESP3 native. Cluster-aware. Client-side caching. Resilience built in. Zero required dependencies.

## Installation

```elixir
def deps do
  [
    {:redis_client_ex, "~> 0.6"}
  ]
end
```

The Hex package is `redis_client_ex`, but the application and all modules use the `Redis` namespace.

## Connecting

```elixir
# Basic
{:ok, conn} = Redis.start_link(port: 6379)

# URI
{:ok, conn} = Redis.start_link("redis://:secret@myhost:6380/2")

# With authentication
{:ok, conn} = Redis.start_link(host: "myhost", password: "secret")

# TLS
{:ok, conn} = Redis.start_link(host: "myhost", ssl: true)
```

## Supervision

```elixir
children = [
  {Redis.Connection, port: 6379, name: :redis},
  {Redis.Connection.Pool, pool_size: 10, port: 6379, name: :redis_pool}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

## Connection Pool

```elixir
{:ok, pool} = Redis.Connection.Pool.start_link(
  pool_size: 10,
  port: 6379
)

Redis.Connection.Pool.command(pool, ["GET", "key"])
```

## Commands, Pipelines, and Transactions

```elixir
{:ok, "OK"} = Redis.command(conn, ["SET", "hello", "world"])
{:ok, "world"} = Redis.command(conn, ["GET", "hello"])

# Pipeline -- multiple commands in a single round-trip
{:ok, ["OK", "OK", "1"]} = Redis.pipeline(conn, [
  ["SET", "a", "1"],
  ["SET", "b", "2"],
  ["GET", "a"]
])

# Transaction -- atomic MULTI/EXEC
{:ok, [1, 2, 3]} = Redis.transaction(conn, [
  ["INCR", "counter"],
  ["INCR", "counter"],
  ["INCR", "counter"]
])
```

## Optimistic Locking (WATCH)

```elixir
Redis.watch_transaction(conn, ["balance"], fn conn ->
  {:ok, bal} = Redis.command(conn, ["GET", "balance"])
  new_bal = String.to_integer(bal) + 100
  [["SET", "balance", to_string(new_bal)]]
end)
```

Watches keys, calls your function to read and compute commands, then
executes in MULTI/EXEC. Automatically retries on conflict (default 3 attempts).

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

# Transactions require same-slot keys (use hash tags)
Redis.Cluster.transaction(cluster, [
  ["SET", "{user:1}.name", "Alice"],
  ["SET", "{user:1}.email", "alice@example.com"]
])
#=> {:ok, ["OK", "OK"]}
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

## Phoenix.PubSub Adapter

Drop-in Redis adapter for Phoenix.PubSub. Enables cross-node broadcasting
for Phoenix, LiveView, and any PubSub-based feature.

```elixir
children = [
  {Phoenix.PubSub,
   name: MyApp.PubSub,
   adapter: Redis.PhoenixPubSub,
   redis_opts: [host: "localhost", port: 6379]}
]
```

Requires `phoenix_pubsub` (optional dependency).

## Streams Consumer

High-level consumer group abstraction over Redis Streams. Define a handler,
start the consumer, and messages are delivered with automatic acknowledgement
and recovery of pending messages from crashed consumers.

```elixir
defmodule MyApp.OrderHandler do
  @behaviour Redis.Consumer.Handler

  @impl true
  def handle_messages(messages, _metadata) do
    for [stream, entries] <- messages, [id, fields] <- entries do
      IO.puts("#{stream} #{id}: #{inspect(fields)}")
    end

    :ok
  end
end

children = [
  {Redis.Connection, port: 6379, name: :redis},
  {Redis.Consumer,
   conn: :redis,
   stream: "orders",
   group: "processors",
   consumer: "proc-1",
   handler: MyApp.OrderHandler}
]
```

Produce messages from anywhere:

```elixir
Redis.command(conn, ["XADD", "orders", "*", "item", "widget", "qty", "5"])
```

Scale by adding more consumers with different `:consumer` names --
Redis distributes messages across the group automatically.

## JSON Documents

High-level API for RedisJSON. Maps in, maps out, with atom or list path
syntax instead of JSONPath strings.

```elixir
# Store and retrieve documents
Redis.JSON.set(conn, "user:1", %{name: "Alice", age: 30, tags: ["admin"]})
{:ok, %{"name" => "Alice", "age" => 30}} = Redis.JSON.get(conn, "user:1", fields: [:name, :age])

# Nested updates
Redis.JSON.put(conn, "user:1", [:address, :city], "NYC")

# Merge (like PATCH)
Redis.JSON.merge(conn, "user:1", %{status: "online", last_seen: "2026-04-03"})

# Atomic operations
{:ok, 31} = Redis.JSON.incr(conn, "user:1", :age, 1)

# Array operations
{:ok, 4} = Redis.JSON.append(conn, "user:1", :tags, "moderator")
{:ok, "moderator"} = Redis.JSON.pop(conn, "user:1", :tags)
```

For raw RedisJSON commands, see `Redis.Commands.JSON`.

## Search

High-level search API over RediSearch. Define indexes with keywords, push
documents as maps, search with Elixir filter expressions instead of raw
query strings.

```elixir
# Create an index
Redis.Search.create_index(conn, "movies",
  prefix: "movie:",
  fields: [
    title: :text,
    year: {:numeric, sortable: true},
    genres: :tag
  ]
)

# Add documents as maps
Redis.Search.add(conn, "movies", "movie:1", %{
  title: "The Dark Knight",
  year: 2008,
  genres: "action,thriller"
})

# Search with Elixir filters
{:ok, results} = Redis.Search.find(conn, "movies", "dark knight",
  where: [year: {:gt, 2000}, genres: {:tag, "action"}],
  sort: {:year, :desc},
  limit: 10
)
#=> %Redis.Search.Result{total: 1, results: [%{id: "movie:1", "title" => "The Dark Knight", ...}]}

# Aggregation
{:ok, results} = Redis.Search.aggregate(conn, "movies",
  group_by: :genres,
  reduce: [count: "total"],
  sort: {:total, :desc}
)
```

Filters compile to RediSearch query syntax automatically:

| Elixir | RediSearch |
|---|---|
| `name: "Alice"` | `@name:Alice` |
| `age: {:gt, 18}` | `@age:[(18 +inf]` |
| `age: {:between, 18, 65}` | `@age:[18 65]` |
| `city: {:tag, "NYC"}` | `@city:{NYC}` |
| `city: {:any, ["NYC", "LA"]}` | `@city:{NYC\|LA}` |

Numeric strings are auto-coerced to integers/floats by default.
For raw RediSearch access, see `Redis.Commands.Search`.

## Session Store

Drop-in Plug session store backed by Redis with configurable TTL.

```elixir
plug Plug.Session,
  store: Redis.PlugSession,
  key: "_my_app_session",
  table: :redis,
  signing_salt: "your_salt",
  ttl: 86_400
```

Requires `plug` (optional dependency).

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

## Features

- **RESP3 native** with RESP2 fallback for older servers
- **Cluster** with topology discovery, hash slot routing, MOVED/ASK redirects, cross-slot pipeline splitting, transaction validation
- **Sentinel** with master resolution, role verification, proactive failover via `+switch-master`
- **Pub/Sub** with pattern subscriptions, sharded pub/sub (Redis 7+)
- **Phoenix.PubSub adapter** for cross-node broadcasting (optional dep)
- **Streams Consumer** with consumer groups, auto-ack, and pending message recovery
- **WATCH transactions** with automatic retry on conflict
- **JSON documents** with map-based CRUD, nested paths, atomic operations (Redis Stack)
- **Search** with Elixir filter expressions, auto-coercion, parsed results (Redis Stack)
- **Plug session store** with configurable TTL
- **Client-side caching** via RESP3 server-assisted invalidation + ETS
- **Connection pool** with round-robin/random dispatch
- **Resilience** patterns: circuit breaker, retry with backoff, request coalescing, bulkhead
- **356 command builders** across 21 modules
- **Lua scripting** with automatic EVALSHA/EVAL fallback
- **Telemetry** events for connection lifecycle and command pipeline

## License

MIT

# Redis

[![CI](https://github.com/joshrotenberg/redis_client_ex/actions/workflows/ci.yml/badge.svg)](https://github.com/joshrotenberg/redis_client_ex/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/redis_client_ex.svg)](https://hex.pm/packages/redis_client_ex)
[![Guide](https://img.shields.io/badge/docs-guide-blue.svg)](https://redis-client-ex.hexdocs.pm/readme.html)
[![API](https://img.shields.io/badge/docs-API_reference-blue.svg)](https://redis-client-ex.hexdocs.pm/api-reference.html)
[![License](https://img.shields.io/hexpm/l/redis_client_ex.svg)](https://github.com/joshrotenberg/redis_client_ex/blob/main/LICENSE)

Modern, full-featured Redis client for Elixir built on OTP.

RESP3 native. Cluster-aware. Client-side caching. Resilience built in. Zero required dependencies.

## Documentation

Start with the **[complete guide](https://redis-client-ex.hexdocs.pm/readme.html)**
for installation, topology selection, and end-to-end examples. Use the
**[API reference](https://redis-client-ex.hexdocs.pm/api-reference.html)** for
module and function details.

## Installation

<!-- x-release-please-start-version -->
```elixir
def deps do
  [
    {:redis, "~> 0.8.0", hex: :redis_client_ex}
  ]
end
```
<!-- x-release-please-end -->

The dependency and OTP application are named `:redis`; `hex: :redis_client_ex`
points Mix at the differently named Hex package. All modules use the `Redis`
namespace.

The core client has no required dependencies. Add only the optional packages
needed by the features you use:

| Feature | Add to your application |
|---|---|
| JSON documents, JSON codec, or JSON-backed search | `{:jason, "~> 1.4"}` |
| Resilience wrapper | `{:ex_resilience, "~> 0.4"}` |
| Phoenix.PubSub adapter | `{:phoenix_pubsub, "~> 2.1"}` |
| Plug session store | `{:plug, "~> 1.14"}` |
| Telemetry events | `{:telemetry, "~> 1.0"}` |
| OpenTelemetry spans | `:telemetry`, `:opentelemetry_api`, and your SDK/exporter |

## Server Compatibility

The client negotiates RESP3 by default and falls back to RESP2 when necessary.
Feature-specific APIs still require server support:

| Capability | Server requirement |
|---|---|
| Redis Functions and sharded Pub/Sub | Redis 7+ |
| Vector Sets | Redis 8.0+ |
| JSON and Search | Redis 8 or Redis Stack with the relevant modules |

Command builders do not perform server-version checks. Redis returns an error
when a command is unavailable on the connected server.

## Connecting

```elixir
# Basic
{:ok, conn} = Redis.start_link(port: 6379)

# URI
{:ok, conn} = Redis.start_link("redis://:secret@myhost:6380/2")

# With authentication
{:ok, conn} = Redis.start_link(host: "myhost", password: "secret")

# TLS with certificate and hostname verification
{:ok, conn} = Redis.start_link(
  host: "myhost",
  ssl: true,
  ssl_opts: [
    verify: :verify_peer,
    cacerts: :public_key.cacerts_get(),
    server_name_indication: ~c"myhost"
  ]
)
```

For backwards compatibility, `ssl: true` without `ssl_opts` uses
`verify: :verify_none`. Configure peer verification for production connections.

## Choosing a Client

| Deployment or workload | Start with |
|---|---|
| One Redis endpoint | `Redis` or `Redis.Connection` |
| Several independent connections | `Redis.Connection.Pool` |
| Manually managed primary and replicas | `Redis.ReplicaSet` |
| Sentinel discovery and failover | `Redis.Sentinel` |
| Redis Cluster | `Redis.Cluster` |
| Regular or pattern subscriptions | `Redis.PubSub` |
| Cluster sharded Pub/Sub | `Redis.PubSub.Sharded` |
| Live command inspection | `Redis.Monitor` |

All command-oriented clients accept the same command-list format. Topology
clients add the routing and failover semantics described in their module docs.

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

## Typed Responses

Raw RESP values remain the default. Opt into stable, protocol-independent
values for commands with known reply shapes:

```elixir
{:ok, %{"name" => "Ada", "role" => "admin"}} =
  Redis.command(conn, ["HGETALL", "user:1"], response: :typed)

{:ok, [%Redis.Response.StreamEntry{id: id, fields: fields}]} =
  Redis.command_typed(conn, ["XRANGE", "events", "-", "+"])

{:ok, [hash, clients]} = Redis.pipeline_typed(conn, [
  ["HGETALL", "user:1"],
  ["CLIENT", "LIST"]
])
```

Typed mode parses `HGETALL`, `CONFIG GET`, set operations, `INFO`,
`CLIENT LIST`/`CLIENT INFO`, and the range/read stream commands. Unknown
commands pass through unchanged, including within mixed pipelines. See
`Redis.Response` for the complete return types.

## Auto-Pipelining

Opt in to automatic batching when many processes issue commands concurrently:

```elixir
{:ok, conn} = Redis.start_link(
  auto_pipeline: true,
  auto_pipeline_window: 1,       # collect commands for up to 1 ms
  auto_pipeline_max_size: 1_000  # or flush when this size is reached
)

1..100
|> Task.async_stream(fn i ->
  Redis.command(conn, ["SET", "key:#{i}", to_string(i)])
end, max_concurrency: 100)
|> Stream.run()
```

Each caller still receives only its own reply, with its own hooks, telemetry,
timeout, and typed-response handling. Explicit pipelines, transactions, and
no-reply operations act as ordering barriers and flush queued commands first.
The feature is disabled by default. `Redis.Connection.Pool` passes the options
to every physical connection, so each connection builds independent batches.

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

Hundreds of command builders are organized across 23 modules:
`Redis.Commands.String`, `Redis.Commands.Hash`, `Redis.Commands.List`,
`Redis.Commands.Set`, `Redis.Commands.SortedSet`, `Redis.Commands.Stream`,
`Redis.Commands.Key`, `Redis.Commands.Server`, `Redis.Commands.JSON`,
`Redis.Commands.Search`, `Redis.Commands.Script`, `Redis.Commands.Function`,
`Redis.Commands.VectorSet`, `Redis.Commands.Geo`, `Redis.Commands.Bitmap`,
`Redis.Commands.HyperLogLog`, `Redis.Commands.Bloom`,
`Redis.Commands.Cuckoo`, `Redis.Commands.TopK`, `Redis.Commands.CMS`,
`Redis.Commands.TDigest`, `Redis.Commands.TimeSeries`, and
`Redis.Commands.PubSub`. See the
[API reference](https://redis-client-ex.hexdocs.pm/api-reference.html) for full
coverage.

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
  read_preference: :prefer_replica,
  password: "secret"
)

# Writes use the primary; eligible reads prefer replicas
Redis.Sentinel.command(conn, ["SET", "key", "value"])
Redis.Sentinel.command(conn, ["GET", "key"])
```

Sentinel refreshes both primary and replica topology and reconnects on
failover. The existing `role: :primary | :replica` option remains available
for a fixed-role connection.

## Primary/Replica Routing

For a manually managed replica set, configure the primary and optional
replicas directly:

```elixir
{:ok, redis} = Redis.ReplicaSet.start_link(
  primary: {"redis-primary", 6379},
  replicas: [{"redis-replica-1", 6379}, {"redis-replica-2", 6379}],
  read_preference: :prefer_replica
)

Redis.ReplicaSet.command(redis, ["SET", "key", "value"]) # primary
Redis.ReplicaSet.command(redis, ["GET", "key"])          # replica, then primary fallback
```

Omit `:replicas` to discover online replicas from `INFO REPLICATION`.
Read-only commands are derived from Redis `COMMAND` metadata; unknown
commands, writes, mixed pipelines, and transactions stay on the primary.

## Pub/Sub

```elixir
{:ok, ps} = Redis.PubSub.start_link(port: 6379)
Redis.PubSub.subscribe(ps, "events", self())

receive do
  {:redis_pubsub, :message, "events", payload} ->
    IO.puts("Got: #{payload}")
end
```

## Command Monitoring

`Redis.Monitor` uses a dedicated connection to stream structured command
events. Subscribers are automatically removed when their process exits.

```elixir
{:ok, monitor} = Redis.Monitor.start_link(port: 6379)
:ok = Redis.Monitor.subscribe(monitor, commands: ["SET", "DEL"])

receive do
  {:redis_monitor, %Redis.Monitor.Entry{} = entry} ->
    IO.inspect(entry)
end
```

Redis `MONITOR` exposes live traffic and carries a performance cost. Protect
access to it and use it deliberately in production.

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

## Redis Functions

Redis 7+ functions are persistent, named server-side routines. Load a library
once, then invoke its functions by name:

```elixir
library = """
#!lua name=my_library
redis.register_function('read_value', function(keys, args)
  return redis.call('GET', keys[1])
end)
"""

:ok = Redis.Function.load(conn, library)
{:ok, value} = Redis.Function.call(conn, "read_value", keys: ["mykey"])
```

Use `Redis.Function.call_ro/3` only for functions registered as read-only.
For ad-hoc Lua scripts with automatic `EVALSHA` fallback, use `Redis.Script`.

## Vector Sets

Redis 8.0+ Vector Sets provide native similarity search:

```elixir
{:ok, 1} =
  Redis.VectorSet.vadd(conn, "movies", "matrix", [0.1, 0.8, 0.3])

{:ok, results} =
  Redis.VectorSet.search(conn, "movies", [0.1, 0.8, 0.3], count: 5)
```

Attributes, filtered searches, graph links, and raw `V*` command builders are
available through `Redis.VectorSet` and `Redis.Commands.VectorSet`.

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

# Cache hit -- served locally from ETS
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

## Operational and Extension APIs

| Need | API |
|---|---|
| Rotating cloud credentials | `Redis.CredentialProvider` |
| Custom serialization | `Redis.Codec` |
| Command middleware | `Redis.Hook` |
| Telemetry events | `Redis.Telemetry` |
| OpenTelemetry spans | `Redis.OpenTelemetry` |
| Cluster-wide key scanning | `Redis.Cluster.Scan` |
| Lua script caching and fallback | `Redis.Script` |

## Features

- **RESP3 native** with RESP2 fallback for older servers
- **TCP, TLS, Unix sockets, and Redis URIs** with ACL and rotating credentials
- **Cluster** with topology discovery, hash slot routing, MOVED/ASK redirects, cross-slot pipeline splitting, transaction validation
- **Sentinel** with master resolution, role verification, proactive failover via `+switch-master`
- **Primary/replica routing** with Sentinel and INFO topology discovery
- **Pub/Sub** with pattern subscriptions, sharded pub/sub (Redis 7+)
- **Structured command monitoring** with subscriber filters and cleanup
- **Phoenix.PubSub adapter** for cross-node broadcasting (optional dep)
- **Streams Consumer** with consumer groups, auto-ack, and pending message recovery
- **WATCH transactions** with automatic retry on conflict
- **Auto-pipelining** for concurrent callers, with per-connection batching
- **Typed responses** for protocol-independent hashes, sets, server records, and streams
- **JSON documents** with map-based CRUD, nested paths, atomic operations (Redis Stack)
- **Search** with Elixir filter expressions, auto-coercion, parsed results (Redis Stack)
- **Redis Functions** and **Vector Sets** through high-level APIs and command builders
- **Plug session store** with configurable TTL
- **Client-side caching** via RESP3 server-assisted invalidation + ETS
- **Connection pool** with round-robin/random dispatch
- **Resilience** patterns: circuit breaker, retry with backoff, request coalescing, bulkhead
- **Hundreds of command builders** across 23 modules
- **Custom codecs and command hooks** for application-specific extensions
- **Lua scripting** with automatic EVALSHA/EVAL fallback
- **Telemetry and OpenTelemetry** integrations for connection and command activity

## License

MIT

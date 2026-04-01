# RedisEx Design Document

A modern, full-featured Redis client for Elixir built on OTP principles.

## Goals

- **RESP3 native** with RESP2 fallback
- **Cluster-native** with hash slot routing, MOVED/ASK handling, topology refresh
- **Sentinel-native** with pub/sub failover detection
- **Client-side caching** via RESP3 push invalidations + ETS
- **Pub/Sub as processes** — subscribers receive messages as Erlang messages
- **Streams** — consumer group support with GenServer-based consumers
- **Connection pooling** built in
- **Zero-copy where possible** — binary-friendly protocol parser
- **Redis Stack modules** — JSON, Search, TimeSeries, Bloom as typed APIs (later)

## Architecture

```
RedisEx (top-level API)
├── Protocol
│   ├── RESP3        — encoder/decoder for RESP3 wire format
│   └── RESP2        — encoder/decoder for RESP2 (fallback)
├── Connection       — single TCP connection GenServer
│   ├── Pool         — connection pooling (NimblePool or built-in)
│   └── TLS          — SSL/TLS upgrade handling
├── Commands         — command builders, typed returns
│   ├── String
│   ├── Hash
│   ├── List
│   ├── Set
│   ├── SortedSet
│   ├── Stream
│   ├── Server
│   ├── Key
│   ├── Script
│   └── Generic
├── Pipeline         — command batching and pipelining
├── Transaction      — MULTI/EXEC with optimistic locking (WATCH)
├── Cluster          — cluster topology, hash slot routing
│   ├── Router       — slot → node mapping
│   ├── Topology     — CLUSTER SLOTS / CLUSTER SHARDS refresh
│   └── Node         — per-node connection pool
├── Sentinel         — sentinel-aware connection resolution
│   ├── Resolver     — query sentinels for master/replica
│   └── Monitor      — subscribe to +switch-master
├── PubSub           — pub/sub connection management
│   ├── Subscription — per-subscription process
│   └── Broker       — route messages to subscribers
└── Cache            — client-side caching
    ├── Store        — ETS-backed cache
    └── Tracker      — invalidation listener (RESP3 push)
```

## Layer Responsibilities

### Protocol (RESP3/RESP2)

Pure functions, no processes. Encode commands to iodata, decode binary
responses to Elixir terms.

RESP3 type mapping:
| RESP3 Type      | Elixir Type                 |
|-----------------|-----------------------------|
| Simple string   | `String.t()`               |
| Blob string     | `String.t()`               |
| Simple error    | `%RedisEx.Error{}`         |
| Number          | `integer()`                |
| Double          | `float()`                  |
| Boolean         | `boolean()`                |
| Null            | `nil`                      |
| Array           | `list()`                   |
| Map             | `map()`                    |
| Set             | `MapSet.t()`               |
| Push            | `{:push, type, data}`      |
| Verbatim string | `{:verbatim, enc, String.t()}` |
| Big number      | `integer()`                |

### Connection

GenServer owning a TCP/TLS socket. Responsibilities:
- Socket lifecycle (connect, reconnect with backoff)
- Send commands, receive responses
- Pipeline buffering
- Push message routing (RESP3 invalidations, pub/sub)

State machine: `disconnected → connecting → handshaking → ready`

Handshake: `HELLO 3` (RESP3 negotiate), `AUTH`, `SELECT`, `CLIENT SETNAME`

### Commands

Thin builder modules that return `[String.t()]` command lists.
No connection logic. Each module covers a Redis command group.

```elixir
RedisEx.Commands.String.set("key", "value", ex: 60)
# => ["SET", "key", "value", "EX", "60"]

RedisEx.Commands.Hash.hgetall("myhash")
# => ["HGETALL", "myhash"]
```

The top-level `RedisEx` module provides the ergonomic API that
combines command building with execution:

```elixir
RedisEx.command(conn, ["GET", "key"])             # raw
RedisEx.get(conn, "key")                          # typed
RedisEx.hgetall(conn, "myhash")                   # => %{"k" => "v"}
```

### Pipeline

Collects multiple commands and sends them in a single write.

```elixir
RedisEx.pipeline(conn, [
  ["SET", "a", "1"],
  ["SET", "b", "2"],
  ["MGET", "a", "b"]
])
# => {:ok, ["OK", "OK", ["1", "2"]]}
```

### Transaction

MULTI/EXEC with optional WATCH for optimistic locking.

```elixir
RedisEx.transaction(conn, fn tx ->
  RedisEx.tx_command(tx, ["INCR", "counter"])
  RedisEx.tx_command(tx, ["GET", "counter"])
end)
# => {:ok, [1, "1"]}
```

### Cluster

The cluster layer manages topology and routes commands to the correct node.

- **Router**: maintains a `slot → {host, port}` map in ETS
- **Topology**: periodically runs `CLUSTER SHARDS` (Redis 7+) or `CLUSTER SLOTS`
- **Node**: each cluster node gets its own connection pool
- **Redirect handling**: transparent MOVED (update topology) and ASK (one-shot redirect)
- **Multi-key commands**: validates all keys hash to same slot, or errors

```elixir
{:ok, cluster} = RedisEx.Cluster.start_link(
  nodes: ["redis://node1:7000", "redis://node2:7001"],
  pool_size: 5
)

RedisEx.Cluster.command(cluster, ["GET", "mykey"])
# Routes to correct node based on CRC16 hash slot
```

### Sentinel

Queries sentinels to resolve master/replica addresses. Subscribes to
`+switch-master` for automatic failover handling.

```elixir
{:ok, conn} = RedisEx.Sentinel.start_link(
  sentinels: ["sentinel1:26379", "sentinel2:26379"],
  group: "mymaster",
  role: :primary
)

# Works like a normal connection — failover is transparent
RedisEx.command(conn, ["SET", "key", "value"])
```

### PubSub

Dedicated connection(s) for pub/sub. Subscribers are Elixir processes
that receive messages via standard `send/2`.

```elixir
{:ok, pubsub} = RedisEx.PubSub.start_link(conn_opts)
:ok = RedisEx.PubSub.subscribe(pubsub, "mychannel", self())

receive do
  {:redis_pubsub, :message, "mychannel", payload} ->
    IO.puts("Got: #{payload}")
end
```

### Client-Side Cache

RESP3 client tracking + ETS for local caching of read commands.
Redis pushes invalidation messages when cached keys change.

```elixir
{:ok, conn} = RedisEx.start_link(cache: true)

# First call: hits Redis, caches in ETS
{:ok, val} = RedisEx.get(conn, "key")

# Second call: served from ETS (no network round-trip)
{:ok, val} = RedisEx.get(conn, "key")

# Another client sets "key" → Redis pushes invalidation → ETS entry evicted
```

## Build Order

Phase 1 — Foundation:
1. RESP3 encoder/decoder (pure functions, easy to test)
2. RESP2 encoder/decoder (fallback)
3. Connection GenServer (TCP, handshake, command/response)
4. Basic `RedisEx.command/2` API

Phase 2 — Core Features:
5. Pipeline support
6. Transaction support (MULTI/EXEC/WATCH)
7. Connection pool
8. Command builder modules
9. Typed top-level API (`get`, `set`, `hgetall`, etc.)

Phase 3 — Distributed:
10. Cluster topology + router
11. Cluster command routing + redirect handling
12. Sentinel resolver
13. Sentinel failover monitor

Phase 4 — Advanced:
14. PubSub subscription management
15. Client-side caching (RESP3 push + ETS)
16. Streams / consumer groups
17. Redis Stack module APIs (JSON, Search, etc.)

## Testing Strategy

- Protocol: pure unit tests, no Redis needed
- Connection: integration tests against redis-server-wrapper
- Cluster: integration tests against redis-server-wrapper Cluster
- Sentinel: integration tests against redis-server-wrapper Sentinel
- Property-based tests for RESP3 encode/decode round-trips

## Protocol Parser Strategy

The pure Elixir RESP3 parser (`RedisEx.Protocol.RESP3`) is the default and has
zero dependencies. For high-throughput scenarios, an optional Rustler NIF-backed
parser can be swapped in transparently:

- `resp-rs` (crates.io/crates/resp-rs) provides a battle-tested RESP3 parser in Rust
- A Rustler wrapper would expose the same `encode/1` / `decode/1` interface
- Selection via config: `config :redis_ex, parser: :native` (default: `:elixir`)
- The pure Elixir parser remains the default — no native compilation required
- Benchmark both to quantify the difference before committing

## Dependencies

Minimal:
- No required external dependencies for core functionality
- Optional: `nimble_pool` for connection pooling (or built-in)
- Optional: `castore` for TLS CA certificates
- Optional: `rustler` + `resp-rs` for NIF-backed RESP3 parser
- Dev/test: `redis_server_wrapper` (path dep) for integration tests

## Integration Testing with redis_server_wrapper

The `redis_server_wrapper` library (sibling project) provides programmatic
control over redis-server processes — perfect for integration tests:

```elixir
# test/test_helper.exs
{:ok, _server} = RedisServerWrapper.Server.start_link(port: 6399)

# test/connection_test.exs
{:ok, conn} = RedisEx.start_link(port: 6399)
{:ok, "PONG"} = RedisEx.command(conn, ["PING"])

# Cluster tests
{:ok, _cluster} = RedisServerWrapper.Cluster.start_link(masters: 3, base_port: 7100)
{:ok, client} = RedisEx.Cluster.start_link(nodes: ["redis://127.0.0.1:7100"])

# Sentinel tests
{:ok, _sentinel} = RedisServerWrapper.Sentinel.start_link(master_port: 6500)
{:ok, client} = RedisEx.Sentinel.start_link(sentinels: ["127.0.0.1:26389"], group: "mymaster")
```

Add as a path dep in mix.exs:

```elixir
defp deps do
  [
    {:redis_server_wrapper, path: "../redis_server_wrapper", only: :test}
  ]
end
```

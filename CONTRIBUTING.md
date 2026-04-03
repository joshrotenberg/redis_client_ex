# Contributing

Contributions are welcome! Here's how to get started.

## Setup

1. Fork and clone the repo
2. Install dependencies: `mix deps.get`
3. Install Redis (7+ recommended, 8+ for JSON/Search features)
4. Run tests: `mix test`

You'll need `redis-server` on your PATH for the test suite. The tests use
[redis_server_wrapper](https://hex.pm/packages/redis_server_wrapper) to
manage Redis instances on custom ports automatically.

## Running Tests

```bash
# Unit tests only (fast, no Redis needed -- this is what PR CI runs)
UNIT_ONLY=true mix test test/unit/

# Full suite (needs redis-server, started automatically)
mix test

# Include Redis Stack tests (JSON, Search)
REDIS_STACK=true mix test

# Include cluster failover tests (slower, 6-node cluster)
REDIS_CLUSTER_FAILOVER=true mix test

# Include sentinel tests
REDIS_SENTINEL=true mix test

# Local multi-version testing via Docker
docker compose up -d
REDIS_STACK=true mix test    # tests against redis-stack on 6379
```

## Code Quality

Before submitting a PR, ensure:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix dialyzer
UNIT_ONLY=true mix test test/unit/
```

All of these run in PR CI. Full integration tests run on a daily schedule.

## Pull Requests

- One PR per issue/feature
- Reference the issue with `Closes #N` in the PR body
- Use [conventional commits](https://www.conventionalcommits.org/):
  `feat:`, `fix:`, `docs:`, `test:`, `chore:`, `refactor:`
- Keep PRs focused -- separate unrelated changes into separate PRs
- Add tests for new features
- Update documentation for public API changes

## Test Organization

Tests are organized by category:

```
test/
  unit/               # No Redis needed
    protocol/         # RESP2, RESP3, property tests, coerce
    commands/         # All 21 command builder tests (pure functions)
    uri_test.exs      # URI parsing
    router_test.exs   # Cluster slot routing
    redis_test.exs    # Top-level Redis module API
  integration/        # Needs redis-server (started by test_helper.exs)
    connection_test.exs, pool_test.exs, cluster_test.exs, ...
    integration_test.exs  # Cross-cutting resilience/reconnection tests
  stack/              # Needs Redis Stack (JSON + Search modules)
    json_*.exs, search_*.exs
  adapters/           # Phoenix.PubSub, Plug session store
    phoenix_pubsub_test.exs, plug_session_test.exs
```

### Test Tags

| Tag | Excluded by default | Enable with |
|-----|-------------------|-------------|
| `:redis_stack` | Yes | `REDIS_STACK=true` |
| `:sentinel` | Yes | `REDIS_SENTINEL=true` |
| `:cluster_failover` | Yes | `REDIS_CLUSTER_FAILOVER=true` |

All other tests run in CI on every push.

## Architecture

The codebase is organized by concern:

```
lib/redis/
  connection/     # TCP/TLS connection, pooling
  cluster/        # Cluster routing, topology, failover
  sentinel/       # Sentinel discovery, monitoring
  pubsub/         # Pub/sub, sharded pub/sub
  cache/          # Client-side caching with ETS
  resilience/     # Circuit breaker, retry, bulkhead, coalesce
  commands/       # 21 command builder modules (pure functions)
  consumer.ex     # Streams consumer group GenServer
  json.ex         # High-level JSON document API
  search.ex       # High-level search API
  phoenix_pubsub.ex  # Phoenix.PubSub adapter
  plug_session.ex # Plug session store
  protocol/       # RESP2/RESP3 encode/decode
  script.ex       # Lua script helper
  telemetry.ex    # Telemetry events
  uri.ex          # Redis URI parser
```

Command builders in `lib/redis/commands/` are pure functions that return
command lists. They have no connection logic and can be tested without Redis.

## Questions?

Open an issue or start a discussion. We're happy to help.

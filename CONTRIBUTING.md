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
# Unit and integration tests (starts Redis automatically)
mix test

# Include Redis Stack tests (JSON, Search -- needs redis-stack-server)
REDIS_STACK=true mix test

# Include cluster failover tests (slower, starts a 6-node cluster)
REDIS_CLUSTER_FAILOVER=true mix test

# Include sentinel tests (needs sentinel topology)
REDIS_SENTINEL=true mix test
```

## Code Quality

Before submitting a PR, ensure:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix dialyzer
mix test
```

All of these run in CI.

## Pull Requests

- One PR per issue/feature
- Reference the issue with `Closes #N` in the PR body
- Use [conventional commits](https://www.conventionalcommits.org/):
  `feat:`, `fix:`, `docs:`, `test:`, `chore:`, `refactor:`
- Keep PRs focused -- separate unrelated changes into separate PRs
- Add tests for new features
- Update documentation for public API changes

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
  phoenix_pubsub.ex  # Phoenix.PubSub adapter
  protocol/       # RESP2/RESP3 encode/decode
  script.ex       # Lua script helper
  telemetry.ex    # Telemetry events
  uri.ex          # Redis URI parser
```

Command builders in `lib/redis/commands/` are pure functions that return
command lists. They have no connection logic and can be tested without Redis.

## Questions?

Open an issue or start a discussion. We're happy to help.

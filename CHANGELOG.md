# Changelog

## [0.7.0](https://github.com/joshrotenberg/redis_client_ex/compare/v0.6.0...v0.7.0) (2026-04-06)


### Features

* add credential provider for auth token rotation ([#122](https://github.com/joshrotenberg/redis_client_ex/issues/122)) ([46b8115](https://github.com/joshrotenberg/redis_client_ex/commit/46b8115e384d704b010e86ec46b9e7e3cb4352bd)), closes [#111](https://github.com/joshrotenberg/redis_client_ex/issues/111)
* add custom codec/serializer support ([#121](https://github.com/joshrotenberg/redis_client_ex/issues/121)) ([b926bf7](https://github.com/joshrotenberg/redis_client_ex/commit/b926bf7a1f61e225bc991f57a3b83c8418a8b537)), closes [#110](https://github.com/joshrotenberg/redis_client_ex/issues/110)
* add hook/interceptor system for command middleware ([#120](https://github.com/joshrotenberg/redis_client_ex/issues/120)) ([30cb2dc](https://github.com/joshrotenberg/redis_client_ex/commit/30cb2dc9145ee791dc6572ae00d23d592566fa10))
* add optional OpenTelemetry integration ([#118](https://github.com/joshrotenberg/redis_client_ex/issues/118)) ([0078580](https://github.com/joshrotenberg/redis_client_ex/commit/0078580fc33dc530578650ed8362782f564cee8e)), closes [#108](https://github.com/joshrotenberg/redis_client_ex/issues/108)
* add Redis Functions support (FCALL/FCALL_RO) ([#117](https://github.com/joshrotenberg/redis_client_ex/issues/117)) ([e6861aa](https://github.com/joshrotenberg/redis_client_ex/commit/e6861aa10d326259c9b847e68245c74c0624a821)), closes [#105](https://github.com/joshrotenberg/redis_client_ex/issues/105)
* add vector set commands ([#119](https://github.com/joshrotenberg/redis_client_ex/issues/119)) ([395b689](https://github.com/joshrotenberg/redis_client_ex/commit/395b6893aa0d6cfe1f34a836b74b39de67b10522)), closes [#106](https://github.com/joshrotenberg/redis_client_ex/issues/106)
* replace inline resilience with ex_resilience optional dependency ([#102](https://github.com/joshrotenberg/redis_client_ex/issues/102)) ([aaa45be](https://github.com/joshrotenberg/redis_client_ex/commit/aaa45be975b2bdf6ce1f11ebaa264e696be4c64d))

## [0.6.0](https://github.com/joshrotenberg/redis_client_ex/compare/v0.5.0...v0.6.0) (2026-04-05)


### Features

* add cacheable command allowlist with per-command TTL override ([#99](https://github.com/joshrotenberg/redis_client_ex/issues/99)) ([c0d0ddc](https://github.com/joshrotenberg/redis_client_ex/commit/c0d0ddc8ea161b0e6754b6bf4c54044e41008cd2)), closes [#95](https://github.com/joshrotenberg/redis_client_ex/issues/95)
* add max size, eviction policy, and background sweep to client-side cache ([#97](https://github.com/joshrotenberg/redis_client_ex/issues/97)) ([4aa5ec9](https://github.com/joshrotenberg/redis_client_ex/commit/4aa5ec97b263b362b6305fd6d67da1ce4b46538a)), closes [#94](https://github.com/joshrotenberg/redis_client_ex/issues/94)
* add pluggable cache backend via behaviour ([#100](https://github.com/joshrotenberg/redis_client_ex/issues/100)) ([7d6fdc8](https://github.com/joshrotenberg/redis_client_ex/commit/7d6fdc87860ca1a17fdba4fafade80eac18c631c)), closes [#96](https://github.com/joshrotenberg/redis_client_ex/issues/96)

## [0.5.0](https://github.com/joshrotenberg/redis_client_ex/compare/v0.4.0...v0.5.0) (2026-04-04)


### Features

* add high-level Redis Search API (closes [#64](https://github.com/joshrotenberg/redis_client_ex/issues/64)) ([#66](https://github.com/joshrotenberg/redis_client_ex/issues/66)) ([7f60131](https://github.com/joshrotenberg/redis_client_ex/commit/7f601312152f8a679a2aa651c3f452314d5bc93a))
* high-level Redis JSON document API ([#73](https://github.com/joshrotenberg/redis_client_ex/issues/73)) ([ea88e91](https://github.com/joshrotenberg/redis_client_ex/commit/ea88e91c8b9eb20aa79e7db1571e3c8411c88758))
* migrate from CLUSTER SLOTS to CLUSTER SHARDS ([#88](https://github.com/joshrotenberg/redis_client_ex/issues/88)) ([5a47947](https://github.com/joshrotenberg/redis_client_ex/commit/5a47947cdaad4df3cd999a83f1d5bd44319a9b69))
* send CLIENT SETINFO on connect (closes [#82](https://github.com/joshrotenberg/redis_client_ex/issues/82)) ([#86](https://github.com/joshrotenberg/redis_client_ex/issues/86)) ([3c5e04f](https://github.com/joshrotenberg/redis_client_ex/commit/3c5e04f773ad3b4f3728cc4fcf3363fe446de8e7))


### Bug Fixes

* treat empty string env vars as unset in test_helper ([#93](https://github.com/joshrotenberg/redis_client_ex/issues/93)) ([1f34209](https://github.com/joshrotenberg/redis_client_ex/commit/1f342099ac6c0fe1fdf32c6be57fab189b1eaddd))
* unwrap RESP3 verbatim strings to plain strings at decode time ([#80](https://github.com/joshrotenberg/redis_client_ex/issues/80)) ([a786de7](https://github.com/joshrotenberg/redis_client_ex/commit/a786de79afe1cdf08293433c9da58336d3f26eaa))


### Performance Improvements

* optimize RESP3 decoder + add protocol benchmarks ([#78](https://github.com/joshrotenberg/redis_client_ex/issues/78)) ([2cdbce3](https://github.com/joshrotenberg/redis_client_ex/commit/2cdbce3ee916e3c9105df6e07b9a06c53e35c86a))

## [0.4.0](https://github.com/joshrotenberg/redis_client_ex/compare/v0.3.0...v0.4.0) (2026-04-02)


### Features

* add Plug session store backed by Redis (closes [#34](https://github.com/joshrotenberg/redis_client_ex/issues/34)) ([#62](https://github.com/joshrotenberg/redis_client_ex/issues/62)) ([eaeeea8](https://github.com/joshrotenberg/redis_client_ex/commit/eaeeea8e6954106b3cc2705d133d044a71d4c308))

## [0.3.0](https://github.com/joshrotenberg/redis_client_ex/compare/v0.2.0...v0.3.0) (2026-04-02)


### Features

* add cluster transaction validation and WATCH support (closes [#28](https://github.com/joshrotenberg/redis_client_ex/issues/28)) ([#53](https://github.com/joshrotenberg/redis_client_ex/issues/53)) ([a551b68](https://github.com/joshrotenberg/redis_client_ex/commit/a551b685a78f06436fce0c20fc0a2b641aff2e37))
* add Phoenix.PubSub adapter backed by Redis (closes [#33](https://github.com/joshrotenberg/redis_client_ex/issues/33)) ([#54](https://github.com/joshrotenberg/redis_client_ex/issues/54)) ([393a0c0](https://github.com/joshrotenberg/redis_client_ex/commit/393a0c09c82a1b9af54973b656c98501530ac79e))
* add Redis.Consumer GenServer for streams consumer groups (closes [#29](https://github.com/joshrotenberg/redis_client_ex/issues/29)) ([#55](https://github.com/joshrotenberg/redis_client_ex/issues/55)) ([11848e0](https://github.com/joshrotenberg/redis_client_ex/commit/11848e0203f1825fa205ddac64ca65774b6239fe))
* add WATCH-based optimistic locking transactions (closes [#27](https://github.com/joshrotenberg/redis_client_ex/issues/27)) ([#51](https://github.com/joshrotenberg/redis_client_ex/issues/51)) ([8a1f877](https://github.com/joshrotenberg/redis_client_ex/commit/8a1f8778ad6c90164172fde253b6046484d59a64))


### Bug Fixes

* cluster topology discovery works correctly after failover (closes [#57](https://github.com/joshrotenberg/redis_client_ex/issues/57)) ([#59](https://github.com/joshrotenberg/redis_client_ex/issues/59)) ([c94bab8](https://github.com/joshrotenberg/redis_client_ex/commit/c94bab83849512c58f84eaf3b271467575051290))

## [0.2.0](https://github.com/joshrotenberg/redis_ex/compare/v0.1.0...v0.2.0) (2026-04-02)


### Features

* add dialyxir and credo, fix all warnings ([#46](https://github.com/joshrotenberg/redis_ex/issues/46)) ([03683a8](https://github.com/joshrotenberg/redis_ex/commit/03683a80684ee23c3aaab089f45bbe164950848c))
* release readiness for redis_client_ex ([#44](https://github.com/joshrotenberg/redis_ex/issues/44)) ([6fd19c0](https://github.com/joshrotenberg/redis_ex/commit/6fd19c053a48b022887a41fd5c2aff83b6f56265))

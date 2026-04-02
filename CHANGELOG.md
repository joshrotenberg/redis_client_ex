# Changelog

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

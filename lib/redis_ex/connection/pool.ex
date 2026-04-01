defmodule RedisEx.Connection.Pool do
  @moduledoc """
  Connection pool for RedisEx.

  Manages a pool of `RedisEx.Connection` processes, dispatching commands
  to available connections.

  ## Options

    * `:pool_size` - number of connections (default: 5)
    * `:conn_opts` - options passed to each `RedisEx.Connection`

  ## TODO (Phase 2)

  - Pool strategy: round-robin, random, or least-loaded
  - Health checking / connection replacement
  - Overflow handling
  - Consider NimblePool integration
  """
end

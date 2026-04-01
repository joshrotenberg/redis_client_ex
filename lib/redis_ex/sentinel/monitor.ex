defmodule RedisEx.Sentinel.Monitor do
  @moduledoc """
  Monitors sentinel pub/sub for failover events.

  Subscribes to the `+switch-master` channel on sentinel instances
  and notifies the parent Sentinel connection to reconnect to the
  new master.

  ## TODO (Phase 3)

  - Pub/sub subscription to sentinel instance
  - Parse +switch-master messages
  - Notify parent process of failover
  - Reconnect to new master address
  - Handle sentinel instance failures (try next sentinel)
  """
end

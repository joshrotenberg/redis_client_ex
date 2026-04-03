exclude =
  if(System.get_env("REDIS_STACK"), do: [], else: [:redis_stack]) ++
    if(System.get_env("REDIS_SENTINEL"), do: [], else: [:sentinel]) ++
    if(System.get_env("REDIS_CLUSTER_FAILOVER"), do: [], else: [:cluster_failover]) ++
    if(System.get_env("REDIS_COMPAT"), do: [], else: [:compat])

ExUnit.start(exclude: exclude)

# Define Mox mock for connection behaviour
Mox.defmock(Redis.MockConnection, for: Redis.Connection.Behaviour)

# Start redis-servers for integration tests (skip if UNIT_ONLY is set)
unless System.get_env("UNIT_ONLY") do
  {:ok, _} = RedisServerWrapper.Server.start_link(port: 6399, password: "testpass")
  {:ok, _} = RedisServerWrapper.Server.start_link(port: 6398)
end

env_enabled? = fn var ->
  case System.get_env(var) do
    nil -> false
    "" -> false
    _ -> true
  end
end

exclude =
  if(env_enabled?.("REDIS_STACK"), do: [], else: [:redis_stack]) ++
    if(env_enabled?.("REDIS_SENTINEL"), do: [], else: [:sentinel]) ++
    if(env_enabled?.("REDIS_CLUSTER_FAILOVER"), do: [], else: [:cluster_failover]) ++
    if(env_enabled?.("REDIS_COMPAT"), do: [], else: [:compat])

ExUnit.start(exclude: exclude)

# Define Mox mock for connection behaviour
Mox.defmock(Redis.MockConnection, for: Redis.Connection.Behaviour)

# Start redis-servers for integration tests (skip if UNIT_ONLY is set)
unless env_enabled?.("UNIT_ONLY") do
  {:ok, _} = RedisServerWrapper.Server.start_link(port: 6399, password: "testpass")
  {:ok, _} = RedisServerWrapper.Server.start_link(port: 6398)
end

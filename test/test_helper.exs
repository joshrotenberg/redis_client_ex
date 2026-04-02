exclude =
  if(System.get_env("REDIS_STACK"), do: [], else: [:redis_stack]) ++
    if System.get_env("REDIS_SENTINEL"), do: [], else: [:sentinel]

ExUnit.start(exclude: exclude)

# Start a redis-server for integration tests
{:ok, _} = RedisServerWrapper.Server.start_link(port: 6399, password: "testpass")
{:ok, _} = RedisServerWrapper.Server.start_link(port: 6398)

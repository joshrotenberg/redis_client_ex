ExUnit.start()

# Start a redis-server for integration tests
{:ok, _} = RedisServerWrapper.Server.start_link(port: 6399, password: "testpass")
{:ok, _} = RedisServerWrapper.Server.start_link(port: 6398)

alias Redis
alias Redis.Connection
alias Redis.Cluster
alias Redis.Sentinel
alias Redis.PubSub
alias Redis.Cache
alias Redis.Protocol.RESP3
alias Redis.Protocol.RESP2
alias Redis.Commands.{Key, Hash, List, Set, SortedSet, Stream, Server}

connect = fn opts ->
  defaults = [port: 6379]
  Redis.start_link(Keyword.merge(defaults, opts))
end

IO.puts("""

  Redis - IEx Session
  =====================

  Aliases: Redis, Connection, Cluster, Sentinel, PubSub, Cache,
           RESP3, RESP2, Key, Hash, List, Set, SortedSet, Stream, Server

  Quick start:
    {:ok, c} = connect.(port: 6379)
    Redis.command(c, ["PING"])

  Client-side caching:
    {:ok, ca} = Cache.start_link(port: 6400)
    Cache.command(ca, ["SET", "foo", "bar"])
    Cache.get(ca, "foo")        # miss → fetches from Redis
    Cache.get(ca, "foo")        # hit → served from ETS
    Cache.stats(ca)             # see hits/misses/evictions

    # From another terminal: redis-cli -p 6400 SET foo newval
    Cache.get(ca, "foo")        # miss → invalidated, fetches "newval"
    Cache.stats(ca)
""")

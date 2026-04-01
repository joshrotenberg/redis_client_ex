alias RedisEx
alias RedisEx.Connection
alias RedisEx.Cluster
alias RedisEx.Sentinel
alias RedisEx.PubSub
alias RedisEx.Cache
alias RedisEx.Protocol.RESP3
alias RedisEx.Protocol.RESP2
alias RedisEx.Commands.{Key, Hash, List, Set, SortedSet, Stream, Server}

connect = fn opts ->
  defaults = [port: 6379]
  RedisEx.start_link(Keyword.merge(defaults, opts))
end

IO.puts("""

  RedisEx - IEx Session
  =====================

  Aliases: RedisEx, Connection, Cluster, Sentinel, PubSub, Cache,
           RESP3, RESP2, Key, Hash, List, Set, SortedSet, Stream, Server

  Quick start:
    {:ok, c} = connect.(port: 6379)
    RedisEx.command(c, ["PING"])

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

defmodule RedisEx.Commands.SortedSet do
  @moduledoc """
  Command builders for Redis sorted set operations.

  ## TODO (Phase 2)

  ZADD, ZCARD, ZCOUNT, ZDIFF, ZDIFFSTORE, ZINCRBY, ZINTER,
  ZINTERCARD, ZINTERSTORE, ZLEXCOUNT, ZMPOP, ZMSCORE, ZPOPMAX,
  ZPOPMIN, ZRANDMEMBER, ZRANGE, ZRANGEBYLEX, ZRANGEBYSCORE,
  ZRANGESTORE, ZRANK, ZREM, ZREMRANGEBYLEX, ZREMRANGEBYRANK,
  ZREMRANGEBYSCORE, ZREVRANGE, ZREVRANGEBYSCORE, ZREVRANK,
  ZSCAN, ZSCORE, ZUNION, ZUNIONSTORE
  """

  @spec zadd(String.t(), [{float() | integer(), String.t()}], keyword()) :: [String.t()]
  def zadd(key, score_members, opts \\ []) do
    cmd = ["ZADD", key]
    cmd = if opts[:nx], do: cmd ++ ["NX"], else: cmd
    cmd = if opts[:xx], do: cmd ++ ["XX"], else: cmd
    cmd = if opts[:gt], do: cmd ++ ["GT"], else: cmd
    cmd = if opts[:lt], do: cmd ++ ["LT"], else: cmd
    cmd ++ Enum.flat_map(score_members, fn {score, member} -> [to_string(score), member] end)
  end

  @spec zscore(String.t(), String.t()) :: [String.t()]
  def zscore(key, member), do: ["ZSCORE", key, member]

  @spec zrange(String.t(), String.t(), String.t(), keyword()) :: [String.t()]
  def zrange(key, min, max, opts \\ []) do
    cmd = ["ZRANGE", key, to_string(min), to_string(max)]
    cmd = if opts[:rev], do: cmd ++ ["REV"], else: cmd
    cmd = if opts[:limit], do: cmd ++ ["LIMIT" | Enum.map(Tuple.to_list(opts[:limit]), &to_string/1)], else: cmd
    cmd = if opts[:withscores], do: cmd ++ ["WITHSCORES"], else: cmd
    cmd
  end

  @spec zrank(String.t(), String.t()) :: [String.t()]
  def zrank(key, member), do: ["ZRANK", key, member]

  @spec zrem(String.t(), [String.t()]) :: [String.t()]
  def zrem(key, members) when is_list(members), do: ["ZREM", key | members]

  @spec zcard(String.t()) :: [String.t()]
  def zcard(key), do: ["ZCARD", key]
end

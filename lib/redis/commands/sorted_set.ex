defmodule Redis.Commands.SortedSet do
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

    cmd =
      if opts[:limit],
        do: cmd ++ ["LIMIT" | Enum.map(Tuple.to_list(opts[:limit]), &to_string/1)],
        else: cmd

    cmd = if opts[:withscores], do: cmd ++ ["WITHSCORES"], else: cmd
    cmd
  end

  @spec zrank(String.t(), String.t()) :: [String.t()]
  def zrank(key, member), do: ["ZRANK", key, member]

  @spec zrem(String.t(), [String.t()]) :: [String.t()]
  def zrem(key, members) when is_list(members), do: ["ZREM", key | members]

  @spec zcard(String.t()) :: [String.t()]
  def zcard(key), do: ["ZCARD", key]

  @spec zcount(String.t(), String.t(), String.t()) :: [String.t()]
  def zcount(key, min, max), do: ["ZCOUNT", key, min, max]

  @spec zdiff(integer(), [String.t()], keyword()) :: [String.t()]
  def zdiff(numkeys, keys, opts \\ []) when is_list(keys) do
    cmd = ["ZDIFF", to_string(numkeys)] ++ keys
    if opts[:withscores], do: cmd ++ ["WITHSCORES"], else: cmd
  end

  @spec zdiffstore(String.t(), integer(), [String.t()]) :: [String.t()]
  def zdiffstore(destination, numkeys, keys) when is_list(keys) do
    ["ZDIFFSTORE", destination, to_string(numkeys)] ++ keys
  end

  @spec zincrby(String.t(), float() | integer(), String.t()) :: [String.t()]
  def zincrby(key, increment, member), do: ["ZINCRBY", key, to_string(increment), member]

  @spec zinter(integer(), [String.t()], keyword()) :: [String.t()]
  def zinter(numkeys, keys, opts \\ []) when is_list(keys) do
    cmd = ["ZINTER", to_string(numkeys)] ++ keys

    cmd =
      if opts[:weights],
        do: cmd ++ ["WEIGHTS" | Enum.map(opts[:weights], &to_string/1)],
        else: cmd

    cmd = if opts[:aggregate], do: cmd ++ ["AGGREGATE", opts[:aggregate]], else: cmd
    cmd = if opts[:withscores], do: cmd ++ ["WITHSCORES"], else: cmd
    cmd
  end

  @spec zintercard(integer(), [String.t()], keyword()) :: [String.t()]
  def zintercard(numkeys, keys, opts \\ []) when is_list(keys) do
    cmd = ["ZINTERCARD", to_string(numkeys)] ++ keys
    if opts[:limit], do: cmd ++ ["LIMIT", to_string(opts[:limit])], else: cmd
  end

  @spec zinterstore(String.t(), integer(), [String.t()], keyword()) :: [String.t()]
  def zinterstore(destination, numkeys, keys, opts \\ []) when is_list(keys) do
    cmd = ["ZINTERSTORE", destination, to_string(numkeys)] ++ keys

    cmd =
      if opts[:weights],
        do: cmd ++ ["WEIGHTS" | Enum.map(opts[:weights], &to_string/1)],
        else: cmd

    cmd = if opts[:aggregate], do: cmd ++ ["AGGREGATE", opts[:aggregate]], else: cmd
    cmd
  end

  @spec zlexcount(String.t(), String.t(), String.t()) :: [String.t()]
  def zlexcount(key, min, max), do: ["ZLEXCOUNT", key, min, max]

  @spec zmpop(integer(), [String.t()], String.t(), keyword()) :: [String.t()]
  def zmpop(numkeys, keys, direction, opts \\ []) when is_list(keys) do
    cmd = ["ZMPOP", to_string(numkeys)] ++ keys ++ [direction]
    if opts[:count], do: cmd ++ ["COUNT", to_string(opts[:count])], else: cmd
  end

  @spec zmscore(String.t(), [String.t()]) :: [String.t()]
  def zmscore(key, members) when is_list(members), do: ["ZMSCORE", key | members]

  @spec zpopmax(String.t(), integer() | nil) :: [String.t()]
  def zpopmax(key, count \\ nil) do
    if count, do: ["ZPOPMAX", key, to_string(count)], else: ["ZPOPMAX", key]
  end

  @spec zpopmin(String.t(), integer() | nil) :: [String.t()]
  def zpopmin(key, count \\ nil) do
    if count, do: ["ZPOPMIN", key, to_string(count)], else: ["ZPOPMIN", key]
  end

  @spec zrandmember(String.t(), keyword()) :: [String.t()]
  def zrandmember(key, opts \\ []) do
    cmd = ["ZRANDMEMBER", key]
    cmd = if opts[:count], do: cmd ++ [to_string(opts[:count])], else: cmd
    cmd = if opts[:withscores], do: cmd ++ ["WITHSCORES"], else: cmd
    cmd
  end

  @spec zrangebylex(String.t(), String.t(), String.t(), keyword()) :: [String.t()]
  def zrangebylex(key, min, max, opts \\ []) do
    cmd = ["ZRANGEBYLEX", key, min, max]

    if opts[:limit],
      do: cmd ++ ["LIMIT", to_string(elem(opts[:limit], 0)), to_string(elem(opts[:limit], 1))],
      else: cmd
  end

  @spec zrangebyscore(String.t(), String.t(), String.t(), keyword()) :: [String.t()]
  def zrangebyscore(key, min, max, opts \\ []) do
    cmd = ["ZRANGEBYSCORE", key, min, max]
    cmd = if opts[:withscores], do: cmd ++ ["WITHSCORES"], else: cmd

    cmd =
      if opts[:limit],
        do: cmd ++ ["LIMIT", to_string(elem(opts[:limit], 0)), to_string(elem(opts[:limit], 1))],
        else: cmd

    cmd
  end

  @spec zrangestore(String.t(), String.t(), String.t(), String.t(), keyword()) :: [String.t()]
  def zrangestore(dst, src, min, max, opts \\ []) do
    cmd = ["ZRANGESTORE", dst, src, to_string(min), to_string(max)]
    cmd = if opts[:byscore], do: cmd ++ ["BYSCORE"], else: cmd
    cmd = if opts[:bylex], do: cmd ++ ["BYLEX"], else: cmd
    cmd = if opts[:rev], do: cmd ++ ["REV"], else: cmd

    cmd =
      if opts[:limit],
        do: cmd ++ ["LIMIT", to_string(elem(opts[:limit], 0)), to_string(elem(opts[:limit], 1))],
        else: cmd

    cmd
  end

  @spec zrevrange(String.t(), integer(), integer(), keyword()) :: [String.t()]
  def zrevrange(key, start, stop, opts \\ []) do
    cmd = ["ZREVRANGE", key, to_string(start), to_string(stop)]
    if opts[:withscores], do: cmd ++ ["WITHSCORES"], else: cmd
  end

  @spec zrevrangebyscore(String.t(), String.t(), String.t(), keyword()) :: [String.t()]
  def zrevrangebyscore(key, max, min, opts \\ []) do
    cmd = ["ZREVRANGEBYSCORE", key, max, min]
    cmd = if opts[:withscores], do: cmd ++ ["WITHSCORES"], else: cmd

    cmd =
      if opts[:limit],
        do: cmd ++ ["LIMIT", to_string(elem(opts[:limit], 0)), to_string(elem(opts[:limit], 1))],
        else: cmd

    cmd
  end

  @spec zrevrank(String.t(), String.t()) :: [String.t()]
  def zrevrank(key, member), do: ["ZREVRANK", key, member]

  @spec zscan(String.t(), integer(), keyword()) :: [String.t()]
  def zscan(key, cursor, opts \\ []) do
    cmd = ["ZSCAN", key, to_string(cursor)]
    cmd = if opts[:match], do: cmd ++ ["MATCH", opts[:match]], else: cmd
    cmd = if opts[:count], do: cmd ++ ["COUNT", to_string(opts[:count])], else: cmd
    cmd
  end

  @spec zunion(integer(), [String.t()], keyword()) :: [String.t()]
  def zunion(numkeys, keys, opts \\ []) when is_list(keys) do
    cmd = ["ZUNION", to_string(numkeys)] ++ keys

    cmd =
      if opts[:weights],
        do: cmd ++ ["WEIGHTS" | Enum.map(opts[:weights], &to_string/1)],
        else: cmd

    cmd = if opts[:aggregate], do: cmd ++ ["AGGREGATE", opts[:aggregate]], else: cmd
    cmd = if opts[:withscores], do: cmd ++ ["WITHSCORES"], else: cmd
    cmd
  end

  @spec zunionstore(String.t(), integer(), [String.t()], keyword()) :: [String.t()]
  def zunionstore(destination, numkeys, keys, opts \\ []) when is_list(keys) do
    cmd = ["ZUNIONSTORE", destination, to_string(numkeys)] ++ keys

    cmd =
      if opts[:weights],
        do: cmd ++ ["WEIGHTS" | Enum.map(opts[:weights], &to_string/1)],
        else: cmd

    cmd = if opts[:aggregate], do: cmd ++ ["AGGREGATE", opts[:aggregate]], else: cmd
    cmd
  end

  @spec zremrangebylex(String.t(), String.t(), String.t()) :: [String.t()]
  def zremrangebylex(key, min, max), do: ["ZREMRANGEBYLEX", key, min, max]

  @spec zremrangebyrank(String.t(), integer(), integer()) :: [String.t()]
  def zremrangebyrank(key, start, stop),
    do: ["ZREMRANGEBYRANK", key, to_string(start), to_string(stop)]

  @spec zremrangebyscore(String.t(), String.t(), String.t()) :: [String.t()]
  def zremrangebyscore(key, min, max), do: ["ZREMRANGEBYSCORE", key, min, max]

  @spec bzpopmax([String.t()], integer()) :: [String.t()]
  def bzpopmax(keys, timeout) when is_list(keys), do: ["BZPOPMAX" | keys] ++ [to_string(timeout)]

  @spec bzpopmin([String.t()], integer()) :: [String.t()]
  def bzpopmin(keys, timeout) when is_list(keys), do: ["BZPOPMIN" | keys] ++ [to_string(timeout)]

  @spec bzmpop(integer(), integer(), [String.t()], String.t(), keyword()) :: [String.t()]
  def bzmpop(timeout, numkeys, keys, direction, opts \\ []) when is_list(keys) do
    cmd = ["BZMPOP", to_string(timeout), to_string(numkeys)] ++ keys ++ [direction]
    if opts[:count], do: cmd ++ ["COUNT", to_string(opts[:count])], else: cmd
  end

  @spec zrevrangebylex(String.t(), String.t(), String.t(), keyword()) :: [String.t()]
  def zrevrangebylex(key, max, min, opts \\ []) do
    cmd = ["ZREVRANGEBYLEX", key, max, min]

    if opts[:limit],
      do: cmd ++ ["LIMIT", to_string(elem(opts[:limit], 0)), to_string(elem(opts[:limit], 1))],
      else: cmd
  end
end

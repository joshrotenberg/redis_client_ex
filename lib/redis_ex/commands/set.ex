defmodule RedisEx.Commands.Set do
  @moduledoc """
  Command builders for Redis set operations.

  ## TODO (Phase 2)

  SADD, SCARD, SDIFF, SDIFFSTORE, SINTER, SINTERCARD, SINTERSTORE,
  SISMEMBER, SMEMBERS, SMISMEMBER, SMOVE, SPOP, SRANDMEMBER, SREM,
  SSCAN, SUNION, SUNIONSTORE
  """

  @spec sadd(String.t(), [String.t()]) :: [String.t()]
  def sadd(key, members) when is_list(members), do: ["SADD", key | members]

  @spec srem(String.t(), [String.t()]) :: [String.t()]
  def srem(key, members) when is_list(members), do: ["SREM", key | members]

  @spec smembers(String.t()) :: [String.t()]
  def smembers(key), do: ["SMEMBERS", key]

  @spec sismember(String.t(), String.t()) :: [String.t()]
  def sismember(key, member), do: ["SISMEMBER", key, member]

  @spec scard(String.t()) :: [String.t()]
  def scard(key), do: ["SCARD", key]

  @spec sdiff([String.t()]) :: [String.t()]
  def sdiff(keys) when is_list(keys), do: ["SDIFF" | keys]

  @spec sdiffstore(String.t(), [String.t()]) :: [String.t()]
  def sdiffstore(destination, keys) when is_list(keys), do: ["SDIFFSTORE", destination | keys]

  @spec sinter([String.t()]) :: [String.t()]
  def sinter(keys) when is_list(keys), do: ["SINTER" | keys]

  @spec sintercard(integer(), [String.t()], keyword()) :: [String.t()]
  def sintercard(numkeys, keys, opts \\ []) when is_list(keys) do
    cmd = ["SINTERCARD", to_string(numkeys)] ++ keys
    if opts[:limit], do: cmd ++ ["LIMIT", to_string(opts[:limit])], else: cmd
  end

  @spec sinterstore(String.t(), [String.t()]) :: [String.t()]
  def sinterstore(destination, keys) when is_list(keys), do: ["SINTERSTORE", destination | keys]

  @spec smismember(String.t(), [String.t()]) :: [String.t()]
  def smismember(key, members) when is_list(members), do: ["SMISMEMBER", key | members]

  @spec smove(String.t(), String.t(), String.t()) :: [String.t()]
  def smove(source, destination, member), do: ["SMOVE", source, destination, member]

  @spec spop(String.t(), integer() | nil) :: [String.t()]
  def spop(key, count \\ nil) do
    if count, do: ["SPOP", key, to_string(count)], else: ["SPOP", key]
  end

  @spec srandmember(String.t(), integer() | nil) :: [String.t()]
  def srandmember(key, count \\ nil) do
    if count, do: ["SRANDMEMBER", key, to_string(count)], else: ["SRANDMEMBER", key]
  end

  @spec sscan(String.t(), integer(), keyword()) :: [String.t()]
  def sscan(key, cursor, opts \\ []) do
    cmd = ["SSCAN", key, to_string(cursor)]
    cmd = if opts[:match], do: cmd ++ ["MATCH", opts[:match]], else: cmd
    cmd = if opts[:count], do: cmd ++ ["COUNT", to_string(opts[:count])], else: cmd
    cmd
  end

  @spec sunion([String.t()]) :: [String.t()]
  def sunion(keys) when is_list(keys), do: ["SUNION" | keys]

  @spec sunionstore(String.t(), [String.t()]) :: [String.t()]
  def sunionstore(destination, keys) when is_list(keys), do: ["SUNIONSTORE", destination | keys]
end

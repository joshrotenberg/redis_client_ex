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
end

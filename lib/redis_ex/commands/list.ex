defmodule RedisEx.Commands.List do
  @moduledoc """
  Command builders for Redis list operations.

  ## TODO (Phase 2)

  BLMOVE, BLPOP, BRPOP, LINDEX, LINSERT, LLEN, LMOVE, LPOP,
  LPOS, LPUSH, LPUSHX, LRANGE, LREM, LSET, LTRIM, RPOP,
  RPUSH, RPUSHX
  """

  @spec lpush(String.t(), [String.t()]) :: [String.t()]
  def lpush(key, values) when is_list(values), do: ["LPUSH", key | values]

  @spec rpush(String.t(), [String.t()]) :: [String.t()]
  def rpush(key, values) when is_list(values), do: ["RPUSH", key | values]

  @spec lpop(String.t(), non_neg_integer() | nil) :: [String.t()]
  def lpop(key, count \\ nil) do
    if count, do: ["LPOP", key, to_string(count)], else: ["LPOP", key]
  end

  @spec rpop(String.t(), non_neg_integer() | nil) :: [String.t()]
  def rpop(key, count \\ nil) do
    if count, do: ["RPOP", key, to_string(count)], else: ["RPOP", key]
  end

  @spec lrange(String.t(), integer(), integer()) :: [String.t()]
  def lrange(key, start, stop), do: ["LRANGE", key, to_string(start), to_string(stop)]

  @spec llen(String.t()) :: [String.t()]
  def llen(key), do: ["LLEN", key]
end

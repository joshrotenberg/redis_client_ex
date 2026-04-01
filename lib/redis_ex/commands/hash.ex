defmodule RedisEx.Commands.Hash do
  @moduledoc """
  Command builders for Redis hash operations.

  ## TODO (Phase 2)

  HDEL, HEXISTS, HGET, HGETALL, HINCRBY, HINCRBYFLOAT, HKEYS,
  HLEN, HMGET, HMSET, HRANDFIELD, HSCAN, HSET, HSETNX, HVALS
  """

  @spec hget(String.t(), String.t()) :: [String.t()]
  def hget(key, field), do: ["HGET", key, field]

  @spec hset(String.t(), [{String.t(), String.t()}]) :: [String.t()]
  def hset(key, pairs) when is_list(pairs) do
    ["HSET", key | Enum.flat_map(pairs, fn {f, v} -> [f, to_string(v)] end)]
  end

  @spec hgetall(String.t()) :: [String.t()]
  def hgetall(key), do: ["HGETALL", key]

  @spec hdel(String.t(), [String.t()]) :: [String.t()]
  def hdel(key, fields) when is_list(fields), do: ["HDEL", key | fields]

  @spec hincrby(String.t(), String.t(), integer()) :: [String.t()]
  def hincrby(key, field, amount), do: ["HINCRBY", key, field, to_string(amount)]

  @spec hkeys(String.t()) :: [String.t()]
  def hkeys(key), do: ["HKEYS", key]

  @spec hvals(String.t()) :: [String.t()]
  def hvals(key), do: ["HVALS", key]

  @spec hlen(String.t()) :: [String.t()]
  def hlen(key), do: ["HLEN", key]
end

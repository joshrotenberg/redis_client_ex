defmodule Redis.Commands.List do
  @moduledoc """
  Command builders for Redis list operations.

  This module provides pure functions that return Redis command lists for
  list data type operations, including pushing/popping elements, range
  queries, blocking pops, and atomic moves between lists. All functions
  return a list of strings suitable for use with `Redis.command/2` or
  `Redis.pipeline/2`.

  ## Examples

      # Push multiple elements to the head and tail of a list
      iex> Redis.Commands.List.lpush("queue", ["c", "b", "a"])
      ["LPUSH", "queue", "c", "b", "a"]

      iex> Redis.Commands.List.rpush("queue", ["x", "y"])
      ["RPUSH", "queue", "x", "y"]

      # Retrieve a range of elements (0-based, inclusive)
      iex> Redis.Commands.List.lrange("queue", 0, -1)
      ["LRANGE", "queue", "0", "-1"]

      # Blocking pop with a 5-second timeout
      iex> Redis.Commands.List.blpop(["queue1", "queue2"], 5)
      ["BLPOP", "queue1", "queue2", "5"]

      # Atomically move an element between lists
      iex> Redis.Commands.List.lmove("src", "dst", "LEFT", "RIGHT")
      ["LMOVE", "src", "dst", "LEFT", "RIGHT"]
  """

  @doc """
  Builds an LPUSH command to prepend one or more `values` to the head of
  the list at `key`. Elements are inserted one after another from left to
  right, so the last element in the list will be the first in the resulting
  list. Returns the length of the list after the push.
  """
  @spec lpush(String.t(), [String.t()]) :: [String.t()]
  def lpush(key, values) when is_list(values), do: ["LPUSH", key | values]

  @doc """
  Builds an RPUSH command to append one or more `values` to the tail of
  the list at `key`. Returns the length of the list after the push.
  """
  @spec rpush(String.t(), [String.t()]) :: [String.t()]
  def rpush(key, values) when is_list(values), do: ["RPUSH", key | values]

  @doc """
  Builds an LPOP command to remove and return the first element of the list
  at `key`. When `count` is provided, removes and returns up to `count`
  elements from the head.
  """
  @spec lpop(String.t(), non_neg_integer() | nil) :: [String.t()]
  def lpop(key, count \\ nil) do
    if count, do: ["LPOP", key, to_string(count)], else: ["LPOP", key]
  end

  @doc """
  Builds an RPOP command to remove and return the last element of the list
  at `key`. When `count` is provided, removes and returns up to `count`
  elements from the tail.
  """
  @spec rpop(String.t(), non_neg_integer() | nil) :: [String.t()]
  def rpop(key, count \\ nil) do
    if count, do: ["RPOP", key, to_string(count)], else: ["RPOP", key]
  end

  @doc """
  Builds an LRANGE command to return elements from index `start` to `stop`
  (inclusive) in the list at `key`. Indices are 0-based; negative indices
  count from the end (-1 is the last element).
  """
  @spec lrange(String.t(), integer(), integer()) :: [String.t()]
  def lrange(key, start, stop), do: ["LRANGE", key, to_string(start), to_string(stop)]

  @spec llen(String.t()) :: [String.t()]
  def llen(key), do: ["LLEN", key]

  @doc """
  Builds a BLPOP command to perform a blocking pop from the head of one or
  more lists. The call blocks for up to `timeout` seconds until an element
  becomes available. A timeout of 0 blocks indefinitely.
  """
  @spec blpop([String.t()], integer()) :: [String.t()]
  def blpop(keys, timeout) when is_list(keys), do: ["BLPOP" | keys] ++ [to_string(timeout)]

  @spec brpop([String.t()], integer()) :: [String.t()]
  def brpop(keys, timeout) when is_list(keys), do: ["BRPOP" | keys] ++ [to_string(timeout)]

  @spec blmove(String.t(), String.t(), String.t(), String.t(), integer()) :: [String.t()]
  def blmove(source, destination, wherefrom, whereto, timeout) do
    ["BLMOVE", source, destination, wherefrom, whereto, to_string(timeout)]
  end

  @spec lindex(String.t(), integer()) :: [String.t()]
  def lindex(key, index), do: ["LINDEX", key, to_string(index)]

  @spec linsert(String.t(), :before | :after, String.t(), String.t()) :: [String.t()]
  def linsert(key, position, pivot, element) do
    pos = position |> to_string() |> String.upcase()
    ["LINSERT", key, pos, pivot, element]
  end

  @doc """
  Builds an LMOVE command to atomically pop an element from `source` and
  push it to `destination`. Use `wherefrom` and `whereto` ("LEFT" or
  "RIGHT") to control which end of each list is used.
  """
  @spec lmove(String.t(), String.t(), String.t(), String.t()) :: [String.t()]
  def lmove(source, destination, wherefrom, whereto) do
    ["LMOVE", source, destination, wherefrom, whereto]
  end

  @spec lpos(String.t(), String.t(), keyword()) :: [String.t()]
  def lpos(key, element, opts \\ []) do
    cmd = ["LPOS", key, element]
    cmd = if opts[:rank], do: cmd ++ ["RANK", to_string(opts[:rank])], else: cmd
    cmd = if opts[:count], do: cmd ++ ["COUNT", to_string(opts[:count])], else: cmd
    cmd = if opts[:maxlen], do: cmd ++ ["MAXLEN", to_string(opts[:maxlen])], else: cmd
    cmd
  end

  @spec lpushx(String.t(), [String.t()]) :: [String.t()]
  def lpushx(key, values) when is_list(values), do: ["LPUSHX", key | values]

  @spec rpushx(String.t(), [String.t()]) :: [String.t()]
  def rpushx(key, values) when is_list(values), do: ["RPUSHX", key | values]

  @spec lrem(String.t(), integer(), String.t()) :: [String.t()]
  def lrem(key, count, element), do: ["LREM", key, to_string(count), element]

  @spec lset(String.t(), integer(), String.t()) :: [String.t()]
  def lset(key, index, element), do: ["LSET", key, to_string(index), element]

  @spec ltrim(String.t(), integer(), integer()) :: [String.t()]
  def ltrim(key, start, stop), do: ["LTRIM", key, to_string(start), to_string(stop)]

  @spec lmpop(integer(), [String.t()], String.t(), keyword()) :: [String.t()]
  def lmpop(numkeys, keys, direction, opts \\ []) when is_list(keys) do
    cmd = ["LMPOP", to_string(numkeys)] ++ keys ++ [direction]
    if opts[:count], do: cmd ++ ["COUNT", to_string(opts[:count])], else: cmd
  end

  @spec blmpop(integer(), integer(), [String.t()], String.t(), keyword()) :: [String.t()]
  def blmpop(timeout, numkeys, keys, direction, opts \\ []) when is_list(keys) do
    cmd = ["BLMPOP", to_string(timeout), to_string(numkeys)] ++ keys ++ [direction]
    if opts[:count], do: cmd ++ ["COUNT", to_string(opts[:count])], else: cmd
  end

  @doc "Deprecated: use lmove/4 instead."
  @spec rpoplpush(String.t(), String.t()) :: [String.t()]
  def rpoplpush(source, destination), do: ["RPOPLPUSH", source, destination]

  @doc "Deprecated: use blmove/5 instead."
  @spec brpoplpush(String.t(), String.t(), integer()) :: [String.t()]
  def brpoplpush(source, destination, timeout) do
    ["BRPOPLPUSH", source, destination, to_string(timeout)]
  end
end

defmodule Redis.Commands.List do
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
end

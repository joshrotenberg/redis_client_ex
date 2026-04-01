defmodule RedisEx.Commands.TopK do
  @moduledoc """
  Command builders for Redis Top-K operations.
  """

  @spec add(String.t(), [String.t()]) :: [String.t()]
  def add(key, items) when is_list(items), do: ["TOPK.ADD", key | items]

  @spec query(String.t(), [String.t()]) :: [String.t()]
  def query(key, items) when is_list(items), do: ["TOPK.QUERY", key | items]

  @spec count(String.t(), [String.t()]) :: [String.t()]
  def count(key, items) when is_list(items), do: ["TOPK.COUNT", key | items]

  @spec list(String.t(), keyword()) :: [String.t()]
  def list(key, opts \\ []) do
    cmd = ["TOPK.LIST", key]
    if opts[:withcount], do: cmd ++ ["WITHCOUNT"], else: cmd
  end

  @spec reserve(String.t(), non_neg_integer(), keyword()) :: [String.t()]
  def reserve(key, topk, opts \\ []) do
    cmd = ["TOPK.RESERVE", key, to_string(topk)]
    cmd = if opts[:width], do: cmd ++ [to_string(opts[:width]), to_string(opts[:depth]), to_string(opts[:decay])], else: cmd
    cmd
  end

  @spec info(String.t()) :: [String.t()]
  def info(key), do: ["TOPK.INFO", key]

  @spec incrby(String.t(), [{String.t(), integer()}]) :: [String.t()]
  def incrby(key, item_increments) when is_list(item_increments) do
    ["TOPK.INCRBY", key | Enum.flat_map(item_increments, fn {item, increment} -> [item, to_string(increment)] end)]
  end
end

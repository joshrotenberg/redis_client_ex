defmodule RedisEx.Commands.CMS do
  @moduledoc """
  Command builders for Redis Count-Min Sketch operations.
  """

  @spec initbydim(String.t(), non_neg_integer(), non_neg_integer()) :: [String.t()]
  def initbydim(key, width, depth) do
    ["CMS.INITBYDIM", key, to_string(width), to_string(depth)]
  end

  @spec initbyprob(String.t(), float(), float()) :: [String.t()]
  def initbyprob(key, error, probability) do
    ["CMS.INITBYPROB", key, to_string(error), to_string(probability)]
  end

  @spec incrby(String.t(), [{String.t(), integer()}]) :: [String.t()]
  def incrby(key, item_increments) when is_list(item_increments) do
    ["CMS.INCRBY", key | Enum.flat_map(item_increments, fn {item, increment} -> [item, to_string(increment)] end)]
  end

  @spec query(String.t(), [String.t()]) :: [String.t()]
  def query(key, items) when is_list(items), do: ["CMS.QUERY", key | items]

  @spec merge(String.t(), [String.t()], keyword()) :: [String.t()]
  def merge(destkey, sources, opts \\ []) when is_list(sources) do
    cmd = ["CMS.MERGE", destkey, to_string(length(sources)) | sources]
    cmd = if opts[:weights], do: cmd ++ ["WEIGHTS" | Enum.map(opts[:weights], &to_string/1)], else: cmd
    cmd
  end

  @spec info(String.t()) :: [String.t()]
  def info(key), do: ["CMS.INFO", key]
end

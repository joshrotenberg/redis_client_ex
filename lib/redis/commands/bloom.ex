defmodule Redis.Commands.Bloom do
  @moduledoc """
  Command builders for Redis Bloom filter operations.
  """

  @spec add(String.t(), String.t()) :: [String.t()]
  def add(key, item), do: ["BF.ADD", key, item]

  @spec exists(String.t(), String.t()) :: [String.t()]
  def exists(key, item), do: ["BF.EXISTS", key, item]

  @spec madd(String.t(), [String.t()]) :: [String.t()]
  def madd(key, items) when is_list(items), do: ["BF.MADD", key | items]

  @spec mexists(String.t(), [String.t()]) :: [String.t()]
  def mexists(key, items) when is_list(items), do: ["BF.MEXISTS", key | items]

  @spec reserve(String.t(), float(), non_neg_integer(), keyword()) :: [String.t()]
  def reserve(key, error_rate, capacity, opts \\ []) do
    cmd = ["BF.RESERVE", key, to_string(error_rate), to_string(capacity)]
    cmd = if opts[:expansion], do: cmd ++ ["EXPANSION", to_string(opts[:expansion])], else: cmd
    cmd = if opts[:nonscaling], do: cmd ++ ["NONSCALING"], else: cmd
    cmd
  end

  @spec info(String.t()) :: [String.t()]
  def info(key), do: ["BF.INFO", key]

  @spec insert(String.t(), [String.t()], keyword()) :: [String.t()]
  def insert(key, items, opts \\ []) when is_list(items) do
    cmd = ["BF.INSERT", key]
    cmd = if opts[:capacity], do: cmd ++ ["CAPACITY", to_string(opts[:capacity])], else: cmd
    cmd = if opts[:error], do: cmd ++ ["ERROR", to_string(opts[:error])], else: cmd
    cmd = if opts[:expansion], do: cmd ++ ["EXPANSION", to_string(opts[:expansion])], else: cmd
    cmd = if opts[:nonscaling], do: cmd ++ ["NONSCALING"], else: cmd
    cmd = if opts[:nocreate], do: cmd ++ ["NOCREATE"], else: cmd
    cmd ++ ["ITEMS" | items]
  end

  @spec scandump(String.t(), non_neg_integer()) :: [String.t()]
  def scandump(key, iterator), do: ["BF.SCANDUMP", key, to_string(iterator)]

  @spec loadchunk(String.t(), non_neg_integer(), String.t()) :: [String.t()]
  def loadchunk(key, iterator, data), do: ["BF.LOADCHUNK", key, to_string(iterator), data]
end

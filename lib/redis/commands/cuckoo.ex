defmodule Redis.Commands.Cuckoo do
  @moduledoc """
  Command builders for Redis Cuckoo filter operations.
  """

  @spec add(String.t(), String.t()) :: [String.t()]
  def add(key, item), do: ["CF.ADD", key, item]

  @spec addnx(String.t(), String.t()) :: [String.t()]
  def addnx(key, item), do: ["CF.ADDNX", key, item]

  @spec exists(String.t(), String.t()) :: [String.t()]
  def exists(key, item), do: ["CF.EXISTS", key, item]

  @spec del(String.t(), String.t()) :: [String.t()]
  def del(key, item), do: ["CF.DEL", key, item]

  @spec count(String.t(), String.t()) :: [String.t()]
  def count(key, item), do: ["CF.COUNT", key, item]

  @spec reserve(String.t(), non_neg_integer(), keyword()) :: [String.t()]
  def reserve(key, capacity, opts \\ []) do
    cmd = ["CF.RESERVE", key, to_string(capacity)]
    cmd = if opts[:bucketsize], do: cmd ++ ["BUCKETSIZE", to_string(opts[:bucketsize])], else: cmd
    cmd = if opts[:maxiterations], do: cmd ++ ["MAXITERATIONS", to_string(opts[:maxiterations])], else: cmd
    cmd = if opts[:expansion], do: cmd ++ ["EXPANSION", to_string(opts[:expansion])], else: cmd
    cmd
  end

  @spec info(String.t()) :: [String.t()]
  def info(key), do: ["CF.INFO", key]

  @spec insert(String.t(), [String.t()], keyword()) :: [String.t()]
  def insert(key, items, opts \\ []) when is_list(items) do
    cmd = ["CF.INSERT", key]
    cmd = if opts[:capacity], do: cmd ++ ["CAPACITY", to_string(opts[:capacity])], else: cmd
    cmd = if opts[:nocreate], do: cmd ++ ["NOCREATE"], else: cmd
    cmd ++ ["ITEMS" | items]
  end

  @spec insertnx(String.t(), [String.t()], keyword()) :: [String.t()]
  def insertnx(key, items, opts \\ []) when is_list(items) do
    cmd = ["CF.INSERTNX", key]
    cmd = if opts[:capacity], do: cmd ++ ["CAPACITY", to_string(opts[:capacity])], else: cmd
    cmd = if opts[:nocreate], do: cmd ++ ["NOCREATE"], else: cmd
    cmd ++ ["ITEMS" | items]
  end
end

defmodule Redis.Commands.Cuckoo do
  @moduledoc """
  Command builders for Redis Cuckoo filter (`CF.*`) operations.

  A Cuckoo filter is a probabilistic data structure similar to a Bloom filter
  but with two key advantages: it supports **deletion** of previously added
  items, and it can report approximate item counts. Like Bloom filters, Cuckoo
  filters may return false positives but never false negatives. The trade-off
  is slightly higher memory usage per element compared to Bloom filters.

  All functions in this module are pure and return a command list (a list of
  strings) suitable for passing to `Redis.command/2` or `Redis.pipeline/2`.

  ## Examples

      # Reserve a Cuckoo filter for up to 10_000 items
      Redis.command(conn, Cuckoo.reserve("users", 10_000))

      # Add, check, and delete an item
      Redis.pipeline(conn, [
        Cuckoo.add("users", "alice"),
        Cuckoo.exists("users", "alice"),
        Cuckoo.del("users", "alice")
      ])
  """

  @doc """
  Adds an item to a Cuckoo filter, creating the filter if it does not exist.
  """
  @spec add(String.t(), String.t()) :: [String.t()]
  def add(key, item), do: ["CF.ADD", key, item]

  @spec addnx(String.t(), String.t()) :: [String.t()]
  def addnx(key, item), do: ["CF.ADDNX", key, item]

  @doc """
  Checks whether an item may exist in a Cuckoo filter.

  Returns 1 if the item may exist (possible false positive), 0 if the item
  definitely does not exist.
  """
  @spec exists(String.t(), String.t()) :: [String.t()]
  def exists(key, item), do: ["CF.EXISTS", key, item]

  @doc """
  Deletes an item from a Cuckoo filter.

  This is the main advantage over Bloom filters. Returns 1 if the item was
  found and deleted, 0 otherwise. Deleting an item that was not added may
  cause false negatives for other items.
  """
  @spec del(String.t(), String.t()) :: [String.t()]
  def del(key, item), do: ["CF.DEL", key, item]

  @spec count(String.t(), String.t()) :: [String.t()]
  def count(key, item), do: ["CF.COUNT", key, item]

  @spec reserve(String.t(), non_neg_integer(), keyword()) :: [String.t()]
  def reserve(key, capacity, opts \\ []) do
    cmd = ["CF.RESERVE", key, to_string(capacity)]
    cmd = if opts[:bucketsize], do: cmd ++ ["BUCKETSIZE", to_string(opts[:bucketsize])], else: cmd

    cmd =
      if opts[:maxiterations],
        do: cmd ++ ["MAXITERATIONS", to_string(opts[:maxiterations])],
        else: cmd

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

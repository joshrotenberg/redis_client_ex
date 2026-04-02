defmodule Redis.Commands.Bloom do
  @moduledoc """
  Command builders for Redis Bloom filter (`BF.*`) operations.

  A Bloom filter is a space-efficient probabilistic data structure used for set
  membership testing. It can tell you with certainty that an item is **not** in
  the set, but positive membership responses may be false positives. The
  trade-off is dramatic memory savings compared to storing every element.

  All functions in this module are pure and return a command list (a list of
  strings) suitable for passing to `Redis.command/2` or `Redis.pipeline/2`.

  ## Examples

      # Reserve a filter allowing 0.01 (1%) error rate for up to 1000 items
      Redis.command(conn, Bloom.reserve("emails", 0.01, 1000))

      # Add an item and check membership
      Redis.pipeline(conn, [
        Bloom.add("emails", "alice@example.com"),
        Bloom.exists("emails", "alice@example.com")
      ])
  """

  @doc """
  Adds an item to a Bloom filter, creating the filter if it does not exist.

  Returns 1 if the item was newly added, 0 if it may have existed already.
  """
  @spec add(String.t(), String.t()) :: [String.t()]
  def add(key, item), do: ["BF.ADD", key, item]

  @doc """
  Checks whether an item may exist in a Bloom filter.

  Returns 1 if the item may exist (possible false positive), 0 if the item
  definitely does not exist.
  """
  @spec exists(String.t(), String.t()) :: [String.t()]
  def exists(key, item), do: ["BF.EXISTS", key, item]

  @spec madd(String.t(), [String.t()]) :: [String.t()]
  def madd(key, items) when is_list(items), do: ["BF.MADD", key | items]

  @spec mexists(String.t(), [String.t()]) :: [String.t()]
  def mexists(key, items) when is_list(items), do: ["BF.MEXISTS", key | items]

  @doc """
  Creates an empty Bloom filter with the given `error_rate` and `capacity`.

  The error rate is the desired probability of false positives (e.g. 0.01 for
  1%). The capacity is the expected number of unique items. Optional keyword
  arguments: `:expansion` (growth factor) and `:nonscaling` (disable scaling).
  """
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

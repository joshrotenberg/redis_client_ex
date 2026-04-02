defmodule Redis.Commands.TopK do
  @moduledoc """
  Command builders for Redis Top-K (`TOPK.*`) operations.

  Top-K is a probabilistic data structure that tracks the **K most frequent
  items** (heavy hitters) in a stream of data. It uses a Count-Min Sketch
  internally to approximate item frequencies, making it very memory-efficient
  for finding popular items in high-volume streams without storing every
  element.

  All functions in this module are pure and return a command list (a list of
  strings) suitable for passing to `Redis.command/2` or `Redis.pipeline/2`.

  ## Examples

      # Track the top 3 most popular pages
      Redis.command(conn, TopK.reserve("popular_pages", 3))

      # Record page views and retrieve the current top-K list
      Redis.pipeline(conn, [
        TopK.add("popular_pages", ["/home", "/about", "/home", "/pricing"]),
        TopK.list("popular_pages", withcount: true)
      ])
  """

  @doc """
  Adds one or more items to the Top-K structure.

  Returns a list where each element is either `nil` (if no item was evicted)
  or the name of the item that was evicted to make room.
  """
  @spec add(String.t(), [String.t()]) :: [String.t()]
  def add(key, items) when is_list(items), do: ["TOPK.ADD", key | items]

  @doc """
  Checks whether one or more items are currently in the Top-K list.
  """
  @spec query(String.t(), [String.t()]) :: [String.t()]
  def query(key, items) when is_list(items), do: ["TOPK.QUERY", key | items]

  @spec count(String.t(), [String.t()]) :: [String.t()]
  def count(key, items) when is_list(items), do: ["TOPK.COUNT", key | items]

  @doc """
  Returns the current Top-K list. Pass `withcount: true` to include counts.
  """
  @spec list(String.t(), keyword()) :: [String.t()]
  def list(key, opts \\ []) do
    cmd = ["TOPK.LIST", key]
    if opts[:withcount], do: cmd ++ ["WITHCOUNT"], else: cmd
  end

  @spec reserve(String.t(), non_neg_integer(), keyword()) :: [String.t()]
  def reserve(key, topk, opts \\ []) do
    cmd = ["TOPK.RESERVE", key, to_string(topk)]

    cmd =
      if opts[:width],
        do: cmd ++ [to_string(opts[:width]), to_string(opts[:depth]), to_string(opts[:decay])],
        else: cmd

    cmd
  end

  @spec info(String.t()) :: [String.t()]
  def info(key), do: ["TOPK.INFO", key]

  @spec incrby(String.t(), [{String.t(), integer()}]) :: [String.t()]
  def incrby(key, item_increments) when is_list(item_increments) do
    [
      "TOPK.INCRBY",
      key
      | Enum.flat_map(item_increments, fn {item, increment} -> [item, to_string(increment)] end)
    ]
  end
end

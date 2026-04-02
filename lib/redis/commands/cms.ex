defmodule Redis.Commands.CMS do
  @moduledoc """
  Command builders for Redis Count-Min Sketch (`CMS.*`) operations.

  A Count-Min Sketch is a probabilistic data structure for estimating the
  frequency of items in a data stream. It uses a fixed-size matrix of counters
  addressed by multiple hash functions. Frequency estimates may **overcount**
  but will never **undercount**, making it useful for approximate frequency
  queries where a small positive bias is acceptable.

  All functions in this module are pure and return a command list (a list of
  strings) suitable for passing to `Redis.command/2` or `Redis.pipeline/2`.

  ## Examples

      # Initialize by exact dimensions (width x depth)
      Redis.command(conn, CMS.initbydim("clicks", 2000, 5))

      # Increment counts and query frequencies
      Redis.pipeline(conn, [
        CMS.incrby("clicks", [{"page_a", 3}, {"page_b", 1}]),
        CMS.query("clicks", ["page_a", "page_b"])
      ])
  """

  @doc """
  Initializes a Count-Min Sketch with the given `width` and `depth`.

  The `width` controls accuracy (more columns = less overcounting) and
  `depth` controls confidence (more rows = lower probability of large error).
  """
  @spec initbydim(String.t(), non_neg_integer(), non_neg_integer()) :: [String.t()]
  def initbydim(key, width, depth) do
    ["CMS.INITBYDIM", key, to_string(width), to_string(depth)]
  end

  @doc """
  Initializes a Count-Min Sketch with a desired `error` rate and `probability`
  of exceeding that error. This is a convenience alternative to `initbydim/3`
  that lets Redis choose the matrix dimensions.
  """
  @spec initbyprob(String.t(), float(), float()) :: [String.t()]
  def initbyprob(key, error, probability) do
    ["CMS.INITBYPROB", key, to_string(error), to_string(probability)]
  end

  @doc """
  Increments the count of one or more items. Each element in the list is a
  `{item, increment}` tuple.
  """
  @spec incrby(String.t(), [{String.t(), integer()}]) :: [String.t()]
  def incrby(key, item_increments) when is_list(item_increments) do
    [
      "CMS.INCRBY",
      key
      | Enum.flat_map(item_increments, fn {item, increment} -> [item, to_string(increment)] end)
    ]
  end

  @spec query(String.t(), [String.t()]) :: [String.t()]
  def query(key, items) when is_list(items), do: ["CMS.QUERY", key | items]

  @spec merge(String.t(), [String.t()], keyword()) :: [String.t()]
  def merge(destkey, sources, opts \\ []) when is_list(sources) do
    cmd = ["CMS.MERGE", destkey, to_string(length(sources)) | sources]

    cmd =
      if opts[:weights],
        do: cmd ++ ["WEIGHTS" | Enum.map(opts[:weights], &to_string/1)],
        else: cmd

    cmd
  end

  @spec info(String.t()) :: [String.t()]
  def info(key), do: ["CMS.INFO", key]
end

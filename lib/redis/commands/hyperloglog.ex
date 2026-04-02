defmodule Redis.Commands.HyperLogLog do
  @moduledoc """
  Command builders for Redis HyperLogLog probabilistic data structure.

  Provides pure functions that build command lists for HyperLogLog operations,
  which allow approximate cardinality estimation (counting unique elements) using
  a fixed amount of memory regardless of the number of elements. Supports adding
  elements (PFADD), estimating cardinality (PFCOUNT), and merging multiple
  HyperLogLog keys (PFMERGE). Each function returns a plain list of strings
  suitable for passing to `Redis.command/2` or `Redis.pipeline/2`.

  These functions contain no connection or networking logic -- they only construct
  the Redis protocol command as a list.

  ## Examples

  Track unique visitors and estimate the total count:

      iex> Redis.Commands.HyperLogLog.pfadd("visitors:2026-04-01", ["user:1", "user:2", "user:3"])
      ["PFADD", "visitors:2026-04-01", "user:1", "user:2", "user:3"]
      iex> Redis.Commands.HyperLogLog.pfcount(["visitors:2026-04-01"])
      ["PFCOUNT", "visitors:2026-04-01"]

  Merge multiple days into a weekly count:

      iex> Redis.Commands.HyperLogLog.pfmerge("visitors:week:14", ["visitors:2026-04-01", "visitors:2026-04-02"])
      ["PFMERGE", "visitors:week:14", "visitors:2026-04-01", "visitors:2026-04-02"]
  """

  @doc """
  Builds a PFADD command to add elements to a HyperLogLog key.

  Redis returns 1 if the internal representation was altered (i.e., the estimated
  cardinality changed), 0 otherwise.

  ## Example

      iex> Redis.Commands.HyperLogLog.pfadd("unique_ips", ["10.0.0.1", "10.0.0.2"])
      ["PFADD", "unique_ips", "10.0.0.1", "10.0.0.2"]
  """
  @spec pfadd(String.t(), [String.t()]) :: [String.t()]
  def pfadd(key, elements) when is_list(elements), do: ["PFADD", key | elements]

  @doc """
  Builds a PFCOUNT command to estimate the cardinality of one or more HyperLogLog keys.

  When given multiple keys, Redis returns the approximate cardinality of the union
  of all the keys without modifying them.

  ## Example

      iex> Redis.Commands.HyperLogLog.pfcount(["unique_ips"])
      ["PFCOUNT", "unique_ips"]
  """
  @spec pfcount([String.t()]) :: [String.t()]
  def pfcount(keys) when is_list(keys), do: ["PFCOUNT" | keys]

  @doc """
  Builds a PFMERGE command to merge multiple HyperLogLog keys into a destination key.

  The resulting key will contain the union of all source keys. This is useful for
  computing aggregate cardinality over time periods or shards.

  ## Example

      iex> Redis.Commands.HyperLogLog.pfmerge("all_ips", ["ips:shard1", "ips:shard2"])
      ["PFMERGE", "all_ips", "ips:shard1", "ips:shard2"]
  """
  @spec pfmerge(String.t(), [String.t()]) :: [String.t()]
  def pfmerge(destkey, sourcekeys) when is_list(sourcekeys) do
    ["PFMERGE", destkey | sourcekeys]
  end
end

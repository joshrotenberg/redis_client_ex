defmodule Redis.Commands.TDigest do
  @moduledoc """
  Command builders for Redis t-digest (`TDIGEST.*`) operations.

  A t-digest is a compact data structure for estimating percentiles and
  quantiles from streaming or distributed data. It works by maintaining a
  sorted set of centroids that adaptively merge as data arrives, providing
  high accuracy at the tails of the distribution (e.g. p99, p99.9) where it
  matters most. Typical use cases include latency monitoring, SLA tracking,
  and any scenario where you need to answer "what value is at the Nth
  percentile?" without storing every observation.

  All functions in this module are pure and return a command list (a list of
  strings) suitable for passing to `Redis.command/2` or `Redis.pipeline/2`.

  ## Examples

      # Create a t-digest and add observations
      Redis.pipeline(conn, [
        TDigest.create("latency"),
        TDigest.add("latency", [1.2, 3.4, 5.6, 7.8, 100.0])
      ])

      # Query the 50th and 99th percentiles
      Redis.command(conn, TDigest.quantile("latency", [0.5, 0.99]))
  """

  @doc """
  Creates an empty t-digest sketch. Pass `compression: n` to control the
  trade-off between accuracy and memory (higher = more accurate, default 100).
  """
  @spec create(String.t(), keyword()) :: [String.t()]
  def create(key, opts \\ []) do
    cmd = ["TDIGEST.CREATE", key]
    if opts[:compression], do: cmd ++ ["COMPRESSION", to_string(opts[:compression])], else: cmd
  end

  @doc """
  Adds one or more numeric observations to the t-digest sketch.
  """
  @spec add(String.t(), [float()]) :: [String.t()]
  def add(key, values) when is_list(values) do
    ["TDIGEST.ADD", key | Enum.map(values, &to_string/1)]
  end

  @spec cdf(String.t(), [float()]) :: [String.t()]
  def cdf(key, values) when is_list(values) do
    ["TDIGEST.CDF", key | Enum.map(values, &to_string/1)]
  end

  @doc """
  Estimates the value at each given quantile (0.0 to 1.0). For example,
  `quantile(key, [0.5, 0.99])` returns the estimated median and p99 values.
  """
  @spec quantile(String.t(), [float()]) :: [String.t()]
  def quantile(key, quantiles) when is_list(quantiles) do
    ["TDIGEST.QUANTILE", key | Enum.map(quantiles, &to_string/1)]
  end

  @spec min(String.t()) :: [String.t()]
  def min(key), do: ["TDIGEST.MIN", key]

  @spec max(String.t()) :: [String.t()]
  def max(key), do: ["TDIGEST.MAX", key]

  @spec info(String.t()) :: [String.t()]
  def info(key), do: ["TDIGEST.INFO", key]

  @spec merge(String.t(), [String.t()], keyword()) :: [String.t()]
  def merge(destkey, sources, opts \\ []) when is_list(sources) do
    cmd = ["TDIGEST.MERGE", destkey, to_string(length(sources)) | sources]

    cmd =
      if opts[:compression], do: cmd ++ ["COMPRESSION", to_string(opts[:compression])], else: cmd

    cmd = if opts[:override], do: cmd ++ ["OVERRIDE"], else: cmd
    cmd
  end

  @spec reset(String.t()) :: [String.t()]
  def reset(key), do: ["TDIGEST.RESET", key]

  @spec trimmed_mean(String.t(), float(), float()) :: [String.t()]
  def trimmed_mean(key, low_quantile, high_quantile) do
    ["TDIGEST.TRIMMED_MEAN", key, to_string(low_quantile), to_string(high_quantile)]
  end

  @spec rank(String.t(), [float()]) :: [String.t()]
  def rank(key, values) when is_list(values) do
    ["TDIGEST.RANK", key | Enum.map(values, &to_string/1)]
  end

  @spec revrank(String.t(), [float()]) :: [String.t()]
  def revrank(key, values) when is_list(values) do
    ["TDIGEST.REVRANK", key | Enum.map(values, &to_string/1)]
  end

  @spec byrank(String.t(), [non_neg_integer()]) :: [String.t()]
  def byrank(key, ranks) when is_list(ranks) do
    ["TDIGEST.BYRANK", key | Enum.map(ranks, &to_string/1)]
  end

  @spec byrevrank(String.t(), [non_neg_integer()]) :: [String.t()]
  def byrevrank(key, ranks) when is_list(ranks) do
    ["TDIGEST.BYREVRANK", key | Enum.map(ranks, &to_string/1)]
  end
end

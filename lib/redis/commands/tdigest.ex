defmodule Redis.Commands.TDigest do
  @moduledoc """
  Command builders for Redis t-digest operations.
  """

  @spec create(String.t(), keyword()) :: [String.t()]
  def create(key, opts \\ []) do
    cmd = ["TDIGEST.CREATE", key]
    if opts[:compression], do: cmd ++ ["COMPRESSION", to_string(opts[:compression])], else: cmd
  end

  @spec add(String.t(), [float()]) :: [String.t()]
  def add(key, values) when is_list(values) do
    ["TDIGEST.ADD", key | Enum.map(values, &to_string/1)]
  end

  @spec cdf(String.t(), [float()]) :: [String.t()]
  def cdf(key, values) when is_list(values) do
    ["TDIGEST.CDF", key | Enum.map(values, &to_string/1)]
  end

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
    cmd = if opts[:compression], do: cmd ++ ["COMPRESSION", to_string(opts[:compression])], else: cmd
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

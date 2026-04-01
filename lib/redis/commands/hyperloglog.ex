defmodule Redis.Commands.HyperLogLog do
  @moduledoc """
  Command builders for Redis HyperLogLog operations.
  """

  @spec pfadd(String.t(), [String.t()]) :: [String.t()]
  def pfadd(key, elements) when is_list(elements), do: ["PFADD", key | elements]

  @spec pfcount([String.t()]) :: [String.t()]
  def pfcount(keys) when is_list(keys), do: ["PFCOUNT" | keys]

  @spec pfmerge(String.t(), [String.t()]) :: [String.t()]
  def pfmerge(destkey, sourcekeys) when is_list(sourcekeys) do
    ["PFMERGE", destkey | sourcekeys]
  end
end

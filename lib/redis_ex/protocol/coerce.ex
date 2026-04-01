defmodule RedisEx.Protocol.Coerce do
  @moduledoc """
  Coerces RESP2 flat-list responses into RESP3-style types based on the command.

  RESP3 natively returns HGETALL as a map and SMEMBERS as a set.
  RESP2 returns flat lists for both. This module bridges the gap so
  callers get consistent types regardless of protocol version.

  ## Usage

      result = Coerce.coerce(["f1", "v1", "f2", "v2"], "HGETALL")
      #=> %{"f1" => "v1", "f2" => "v2"}

      result = Coerce.coerce(["a", "b", "c"], "SMEMBERS")
      #=> MapSet.new(["a", "b", "c"])
  """

  @doc """
  Coerces a RESP2 result based on the command name.
  Returns the result unchanged if no coercion applies.
  """
  @spec coerce(term(), String.t()) :: term()
  def coerce(result, command) when is_binary(command) do
    coerce(result, String.upcase(command))
  end

  # Flat list → map
  def coerce(result, cmd) when is_list(result) and cmd in ~w(HGETALL CONFIG XRANGE XREVRANGE) do
    if rem(length(result), 2) == 0 do
      result
      |> Enum.chunk_every(2)
      |> Map.new(fn [k, v] -> {k, v} end)
    else
      result
    end
  end

  # List → MapSet
  def coerce(result, cmd) when is_list(result) and cmd in ~w(SMEMBERS SDIFF SINTER SUNION) do
    MapSet.new(result)
  end

  # No coercion needed
  def coerce(result, _command), do: result

  @doc """
  Extracts the command name from a command list for coercion lookup.
  """
  @spec command_name([String.t()]) :: String.t()
  def command_name([cmd | _]) when is_binary(cmd), do: String.upcase(cmd)
  def command_name(_), do: ""
end

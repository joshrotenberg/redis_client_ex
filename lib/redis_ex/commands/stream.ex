defmodule RedisEx.Commands.Stream do
  @moduledoc """
  Command builders for Redis stream operations.

  ## TODO (Phase 2/4)

  XADD, XLEN, XRANGE, XREVRANGE, XREAD, XTRIM,
  XGROUP CREATE, XGROUP DESTROY, XGROUP SETID,
  XREADGROUP, XACK, XCLAIM, XAUTOCLAIM, XPENDING, XINFO
  """

  @spec xadd(String.t(), String.t(), [{String.t(), String.t()}], keyword()) :: [String.t()]
  def xadd(key, id \\ "*", fields, opts \\ []) do
    cmd = ["XADD", key]
    cmd = if opts[:maxlen], do: cmd ++ ["MAXLEN", "~", to_string(opts[:maxlen])], else: cmd
    cmd = cmd ++ [id]
    cmd ++ Enum.flat_map(fields, fn {f, v} -> [f, to_string(v)] end)
  end

  @spec xlen(String.t()) :: [String.t()]
  def xlen(key), do: ["XLEN", key]

  @spec xrange(String.t(), String.t(), String.t(), keyword()) :: [String.t()]
  def xrange(key, start_id \\ "-", end_id \\ "+", opts \\ []) do
    cmd = ["XRANGE", key, start_id, end_id]
    if opts[:count], do: cmd ++ ["COUNT", to_string(opts[:count])], else: cmd
  end

  @spec xread(keyword()) :: [String.t()]
  def xread(opts) do
    cmd = ["XREAD"]
    cmd = if opts[:count], do: cmd ++ ["COUNT", to_string(opts[:count])], else: cmd
    cmd = if opts[:block], do: cmd ++ ["BLOCK", to_string(opts[:block])], else: cmd
    cmd ++ ["STREAMS" | flatten_streams(opts[:streams])]
  end

  defp flatten_streams(streams) when is_list(streams) do
    {keys, ids} = Enum.unzip(streams)
    Enum.map(keys, &to_string/1) ++ Enum.map(ids, &to_string/1)
  end
end

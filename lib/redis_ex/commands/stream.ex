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

  @spec xack(String.t(), String.t(), [String.t()]) :: [String.t()]
  def xack(key, group, ids) when is_list(ids), do: ["XACK", key, group | ids]

  @spec xdel(String.t(), [String.t()]) :: [String.t()]
  def xdel(key, ids) when is_list(ids), do: ["XDEL", key | ids]

  @spec xrevrange(String.t(), String.t(), String.t(), keyword()) :: [String.t()]
  def xrevrange(key, end_id \\ "+", start_id \\ "-", opts \\ []) do
    cmd = ["XREVRANGE", key, end_id, start_id]
    if opts[:count], do: cmd ++ ["COUNT", to_string(opts[:count])], else: cmd
  end

  @spec xtrim(String.t(), keyword()) :: [String.t()]
  def xtrim(key, opts \\ []) do
    cmd = ["XTRIM", key]
    cmd = if opts[:maxlen], do: cmd ++ ["MAXLEN", "~", to_string(opts[:maxlen])], else: cmd
    cmd = if opts[:minid], do: cmd ++ ["MINID", "~", to_string(opts[:minid])], else: cmd
    cmd
  end

  @spec xclaim(String.t(), String.t(), String.t(), integer(), [String.t()], keyword()) :: [String.t()]
  def xclaim(key, group, consumer, min_idle_time, ids, opts \\ []) when is_list(ids) do
    cmd = ["XCLAIM", key, group, consumer, to_string(min_idle_time)] ++ ids
    cmd = if opts[:idle], do: cmd ++ ["IDLE", to_string(opts[:idle])], else: cmd
    cmd = if opts[:force], do: cmd ++ ["FORCE"], else: cmd
    cmd = if opts[:justid], do: cmd ++ ["JUSTID"], else: cmd
    cmd
  end

  @spec xautoclaim(String.t(), String.t(), String.t(), integer(), String.t(), keyword()) :: [String.t()]
  def xautoclaim(key, group, consumer, min_idle_time, start, opts \\ []) do
    cmd = ["XAUTOCLAIM", key, group, consumer, to_string(min_idle_time), start]
    cmd = if opts[:count], do: cmd ++ ["COUNT", to_string(opts[:count])], else: cmd
    cmd = if opts[:justid], do: cmd ++ ["JUSTID"], else: cmd
    cmd
  end

  @spec xpending(String.t(), String.t(), keyword()) :: [String.t()]
  def xpending(key, group, opts \\ []) do
    cmd = ["XPENDING", key, group]
    cmd = if opts[:idle], do: cmd ++ ["IDLE", to_string(opts[:idle])], else: cmd
    cmd = if opts[:start], do: cmd ++ [opts[:start]], else: cmd
    cmd = if opts[:end], do: cmd ++ [opts[:end]], else: cmd
    cmd = if opts[:count], do: cmd ++ [to_string(opts[:count])], else: cmd
    cmd = if opts[:consumer], do: cmd ++ [opts[:consumer]], else: cmd
    cmd
  end

  @spec xreadgroup(String.t(), String.t(), keyword()) :: [String.t()]
  def xreadgroup(group, consumer, opts) do
    cmd = ["XREADGROUP", "GROUP", group, consumer]
    cmd = if opts[:count], do: cmd ++ ["COUNT", to_string(opts[:count])], else: cmd
    cmd = if opts[:block], do: cmd ++ ["BLOCK", to_string(opts[:block])], else: cmd
    cmd = if opts[:noack], do: cmd ++ ["NOACK"], else: cmd
    cmd ++ ["STREAMS" | flatten_streams(opts[:streams])]
  end

  @spec xgroup_create(String.t(), String.t(), String.t(), keyword()) :: [String.t()]
  def xgroup_create(key, group, id \\ "$", opts \\ []) do
    cmd = ["XGROUP", "CREATE", key, group, id]
    if opts[:mkstream], do: cmd ++ ["MKSTREAM"], else: cmd
  end

  @spec xgroup_createconsumer(String.t(), String.t(), String.t()) :: [String.t()]
  def xgroup_createconsumer(key, group, consumer) do
    ["XGROUP", "CREATECONSUMER", key, group, consumer]
  end

  @spec xgroup_delconsumer(String.t(), String.t(), String.t()) :: [String.t()]
  def xgroup_delconsumer(key, group, consumer) do
    ["XGROUP", "DELCONSUMER", key, group, consumer]
  end

  @spec xgroup_destroy(String.t(), String.t()) :: [String.t()]
  def xgroup_destroy(key, group), do: ["XGROUP", "DESTROY", key, group]

  @spec xgroup_setid(String.t(), String.t(), String.t()) :: [String.t()]
  def xgroup_setid(key, group, id), do: ["XGROUP", "SETID", key, group, id]

  @spec xinfo_consumers(String.t(), String.t()) :: [String.t()]
  def xinfo_consumers(key, group), do: ["XINFO", "CONSUMERS", key, group]

  @spec xinfo_groups(String.t()) :: [String.t()]
  def xinfo_groups(key), do: ["XINFO", "GROUPS", key]

  @spec xinfo_stream(String.t(), keyword()) :: [String.t()]
  def xinfo_stream(key, opts \\ []) do
    cmd = ["XINFO", "STREAM", key]
    if opts[:full], do: cmd ++ ["FULL"], else: cmd
  end

  defp flatten_streams(streams) when is_list(streams) do
    {keys, ids} = Enum.unzip(streams)
    Enum.map(keys, &to_string/1) ++ Enum.map(ids, &to_string/1)
  end
end

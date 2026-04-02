defmodule Redis.Commands.Stream do
  @moduledoc """
  Command builders for Redis stream operations.

  This module provides pure functions that build Redis Stream command
  lists. Streams are append-only log structures that support fan-out
  reads, consumer groups with at-least-once delivery, and automatic
  ID generation. They are well-suited for event sourcing, task queues,
  and activity feeds.

  Every function returns a plain list of strings (a command). To execute
  a command, pass the result to `Redis.command/2`; to batch several
  commands in a single round trip, use `Redis.pipeline/2`.

  ## Examples

  Appending entries and reading them back:

      iex> Redis.command(conn, Redis.Commands.Stream.xadd("events", "*", [{"type", "click"}, {"url", "/home"}]))
      {:ok, "1234567890123-0"}

      iex> Redis.command(conn, Redis.Commands.Stream.xread(streams: [{"events", "0"}], count: 10))
      {:ok, [["events", [["1234567890123-0", ["type", "click", "url", "/home"]]]]]}

  Consumer group pattern -- read, process, acknowledge:

      iex> Redis.command(conn, Redis.Commands.Stream.xgroup_create("events", "workers", "0", mkstream: true))
      {:ok, "OK"}

      iex> Redis.command(conn, Redis.Commands.Stream.xreadgroup("workers", "worker-1", streams: [{"events", ">"}], count: 5))
      {:ok, [["events", [["1234567890123-0", ["type", "click", "url", "/home"]]]]]}

      iex> Redis.command(conn, Redis.Commands.Stream.xack("events", "workers", ["1234567890123-0"]))
      {:ok, 1}
  """

  @doc """
  Builds an XADD command to append an entry to the stream at `key`.

  `id` defaults to `"*"` which lets Redis auto-generate a monotonic ID.
  `fields` is a list of `{field, value}` tuples representing the entry
  payload. Options:

    * `:maxlen` - cap the stream length with approximate trimming (`~`)
  """
  @spec xadd(String.t(), String.t(), [{String.t(), String.t()}], keyword()) :: [String.t()]
  def xadd(key, id \\ "*", fields, opts \\ []) do
    cmd = ["XADD", key]
    cmd = if opts[:maxlen], do: cmd ++ ["MAXLEN", "~", to_string(opts[:maxlen])], else: cmd
    cmd = cmd ++ [id]
    cmd ++ Enum.flat_map(fields, fn {f, v} -> [f, to_string(v)] end)
  end

  @doc """
  Builds an XLEN command to return the number of entries in the stream at `key`.
  """
  @spec xlen(String.t()) :: [String.t()]
  def xlen(key), do: ["XLEN", key]

  @spec xrange(String.t(), String.t(), String.t(), keyword()) :: [String.t()]
  def xrange(key, start_id \\ "-", end_id \\ "+", opts \\ []) do
    cmd = ["XRANGE", key, start_id, end_id]
    if opts[:count], do: cmd ++ ["COUNT", to_string(opts[:count])], else: cmd
  end

  @doc """
  Builds an XREAD command to read entries from one or more streams.

  Options:

    * `:streams` (required) - a list of `{stream_key, last_id}` tuples.
      Use `"0"` to read from the beginning or `"$"` to read only new entries.
    * `:count` - maximum number of entries to return per stream
    * `:block` - block for up to this many milliseconds waiting for new data
  """
  @spec xread(keyword()) :: [String.t()]
  def xread(opts) do
    cmd = ["XREAD"]
    cmd = if opts[:count], do: cmd ++ ["COUNT", to_string(opts[:count])], else: cmd
    cmd = if opts[:block], do: cmd ++ ["BLOCK", to_string(opts[:block])], else: cmd
    cmd ++ ["STREAMS" | flatten_streams(opts[:streams])]
  end

  @doc """
  Builds an XACK command to acknowledge one or more stream entries.

  Acknowledging an entry removes it from the consumer group's pending
  entries list (PEL). Returns the number of entries successfully
  acknowledged.
  """
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

  @spec xclaim(String.t(), String.t(), String.t(), integer(), [String.t()], keyword()) :: [
          String.t()
        ]
  def xclaim(key, group, consumer, min_idle_time, ids, opts \\ []) when is_list(ids) do
    cmd = ["XCLAIM", key, group, consumer, to_string(min_idle_time)] ++ ids
    cmd = if opts[:idle], do: cmd ++ ["IDLE", to_string(opts[:idle])], else: cmd
    cmd = if opts[:force], do: cmd ++ ["FORCE"], else: cmd
    cmd = if opts[:justid], do: cmd ++ ["JUSTID"], else: cmd
    cmd
  end

  @spec xautoclaim(String.t(), String.t(), String.t(), integer(), String.t(), keyword()) :: [
          String.t()
        ]
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

  @doc """
  Builds an XREADGROUP command to read entries via a consumer group.

  Each entry delivered to `consumer` within `group` must later be
  acknowledged with `xack/3`. Options:

    * `:streams` (required) - a list of `{stream_key, id}` tuples.
      Use `">"` as the id to receive only new, undelivered messages.
    * `:count` - maximum number of entries to return per stream
    * `:block` - block for up to this many milliseconds waiting for new data
    * `:noack` - do not require acknowledgement for delivered entries
  """
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

  @doc """
  Builds an XINFO STREAM command to return metadata about the stream at `key`.

  Pass `full: true` to include detailed information about every consumer
  group, consumer, and pending entry.
  """
  @spec xinfo_stream(String.t(), keyword()) :: [String.t()]
  def xinfo_stream(key, opts \\ []) do
    cmd = ["XINFO", "STREAM", key]
    if opts[:full], do: cmd ++ ["FULL"], else: cmd
  end

  @spec xsetid(String.t(), String.t(), keyword()) :: [String.t()]
  def xsetid(key, last_id, opts \\ []) do
    cmd = ["XSETID", key, last_id]

    cmd =
      if opts[:entriesadded],
        do: cmd ++ ["ENTRIESADDED", to_string(opts[:entriesadded])],
        else: cmd

    cmd = if opts[:maxdeletedid], do: cmd ++ ["MAXDELETEDID", opts[:maxdeletedid]], else: cmd
    cmd
  end

  defp flatten_streams(streams) when is_list(streams) do
    {keys, ids} = Enum.unzip(streams)
    Enum.map(keys, &to_string/1) ++ Enum.map(ids, &to_string/1)
  end
end

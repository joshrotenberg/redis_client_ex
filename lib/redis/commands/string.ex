defmodule Redis.Commands.String do
  @moduledoc """
  Command builders for Redis string operations.

  ## TODO (Phase 2)

  APPEND, DECR, DECRBY, GET, GETDEL, GETEX, GETRANGE, GETSET,
  INCR, INCRBY, INCRBYFLOAT, MGET, MSET, MSETNX, SET, SETEX,
  SETNX, SETRANGE, STRLEN
  """

  @spec get(String.t()) :: [String.t()]
  def get(key), do: ["GET", key]

  @spec set(String.t(), String.t(), keyword()) :: [String.t()]
  def set(key, value, opts \\ []) do
    cmd = ["SET", key, to_string(value)]
    cmd = if opts[:ex], do: cmd ++ ["EX", to_string(opts[:ex])], else: cmd
    cmd = if opts[:px], do: cmd ++ ["PX", to_string(opts[:px])], else: cmd
    cmd = if opts[:nx], do: cmd ++ ["NX"], else: cmd
    cmd = if opts[:xx], do: cmd ++ ["XX"], else: cmd
    cmd = if opts[:get], do: cmd ++ ["GET"], else: cmd
    cmd
  end

  @spec mget([String.t()]) :: [String.t()]
  def mget(keys) when is_list(keys), do: ["MGET" | keys]

  @spec mset([{String.t(), String.t()}]) :: [String.t()]
  def mset(pairs) when is_list(pairs) do
    ["MSET" | Enum.flat_map(pairs, fn {k, v} -> [k, to_string(v)] end)]
  end

  @spec incr(String.t()) :: [String.t()]
  def incr(key), do: ["INCR", key]

  @spec incrby(String.t(), integer()) :: [String.t()]
  def incrby(key, amount), do: ["INCRBY", key, to_string(amount)]

  @spec decr(String.t()) :: [String.t()]
  def decr(key), do: ["DECR", key]

  @spec decrby(String.t(), integer()) :: [String.t()]
  def decrby(key, amount), do: ["DECRBY", key, to_string(amount)]

  @spec append(String.t(), String.t()) :: [String.t()]
  def append(key, value), do: ["APPEND", key, value]

  @spec getdel(String.t()) :: [String.t()]
  def getdel(key), do: ["GETDEL", key]

  @spec getex(String.t(), keyword()) :: [String.t()]
  def getex(key, opts \\ []) do
    cmd = ["GETEX", key]
    cmd = if opts[:ex], do: cmd ++ ["EX", to_string(opts[:ex])], else: cmd
    cmd = if opts[:px], do: cmd ++ ["PX", to_string(opts[:px])], else: cmd
    cmd = if opts[:exat], do: cmd ++ ["EXAT", to_string(opts[:exat])], else: cmd
    cmd = if opts[:pxat], do: cmd ++ ["PXAT", to_string(opts[:pxat])], else: cmd
    cmd = if opts[:persist], do: cmd ++ ["PERSIST"], else: cmd
    cmd
  end

  @spec getrange(String.t(), integer(), integer()) :: [String.t()]
  def getrange(key, start, stop), do: ["GETRANGE", key, to_string(start), to_string(stop)]

  @spec incrbyfloat(String.t(), float()) :: [String.t()]
  def incrbyfloat(key, amount), do: ["INCRBYFLOAT", key, to_string(amount)]

  @spec msetnx([{String.t(), String.t()}]) :: [String.t()]
  def msetnx(pairs) when is_list(pairs) do
    ["MSETNX" | Enum.flat_map(pairs, fn {k, v} -> [k, to_string(v)] end)]
  end

  @spec setex(String.t(), integer(), String.t()) :: [String.t()]
  def setex(key, seconds, value), do: ["SETEX", key, to_string(seconds), to_string(value)]

  @spec psetex(String.t(), integer(), String.t()) :: [String.t()]
  def psetex(key, milliseconds, value), do: ["PSETEX", key, to_string(milliseconds), to_string(value)]

  @spec setnx(String.t(), String.t()) :: [String.t()]
  def setnx(key, value), do: ["SETNX", key, to_string(value)]

  @spec setrange(String.t(), integer(), String.t()) :: [String.t()]
  def setrange(key, offset, value), do: ["SETRANGE", key, to_string(offset), value]

  @spec strlen(String.t()) :: [String.t()]
  def strlen(key), do: ["STRLEN", key]

  @spec getset(String.t(), String.t()) :: [String.t()]
  def getset(key, value), do: ["GETSET", key, to_string(value)]

  @spec lcs(String.t(), String.t(), keyword()) :: [String.t()]
  def lcs(key1, key2, opts \\ []) do
    cmd = ["LCS", key1, key2]
    cmd = if opts[:len], do: cmd ++ ["LEN"], else: cmd
    cmd = if opts[:idx], do: cmd ++ ["IDX"], else: cmd
    cmd = if opts[:minmatchlen], do: cmd ++ ["MINMATCHLEN", to_string(opts[:minmatchlen])], else: cmd
    cmd = if opts[:withmatchlen], do: cmd ++ ["WITHMATCHLEN"], else: cmd
    cmd
  end

  @doc "Deprecated: use getrange/3 instead."
  @spec substr(String.t(), integer(), integer()) :: [String.t()]
  def substr(key, start, stop), do: ["SUBSTR", key, to_string(start), to_string(stop)]
end

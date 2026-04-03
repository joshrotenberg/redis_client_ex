defmodule Redis.Commands.String do
  @moduledoc """
  Command builders for Redis string operations.

  This module provides pure functions that return Redis command lists for
  string data type operations, including getting/setting values, atomic
  counters, and bulk operations. All functions return a list of strings
  suitable for use with `Redis.command/2` or `Redis.pipeline/2`.

  ## Examples

      # SET with expiry and NX (only if key does not exist)
      iex> Redis.Commands.String.set("session:abc", "user_1", ex: 3600, nx: true)
      ["SET", "session:abc", "user_1", "EX", "3600", "NX"]

      # GET a value
      iex> Redis.Commands.String.get("session:abc")
      ["GET", "session:abc"]

      # Atomic counter increment
      iex> Redis.Commands.String.incr("page:views")
      ["INCR", "page:views"]

      # Fetch multiple keys at once
      iex> Redis.Commands.String.mget(["key1", "key2", "key3"])
      ["MGET", "key1", "key2", "key3"]
  """

  @doc """
  Builds a GET command to retrieve the value stored at `key`.

  Returns `nil` from Redis when the key does not exist.
  """
  @spec get(String.t()) :: [String.t()]
  def get(key), do: ["GET", key]

  @doc """
  Builds a SET command to store `value` at `key`.

  ## Options

    * `:ex` - set expiry in seconds
    * `:px` - set expiry in milliseconds
    * `:nx` - only set if the key does not already exist
    * `:xx` - only set if the key already exists
    * `:get` - return the old value stored at the key
    * `:ifeq` - only set if the current value equals the given string (Redis 8.0+)
    * `:ifne` - only set if the current value does not equal the given string (Redis 8.0+)
  """
  @spec set(String.t(), String.t(), keyword()) :: [String.t()]
  def set(key, value, opts \\ []) do
    cmd = ["SET", key, to_string(value)]
    cmd = if opts[:ex], do: cmd ++ ["EX", to_string(opts[:ex])], else: cmd
    cmd = if opts[:px], do: cmd ++ ["PX", to_string(opts[:px])], else: cmd
    cmd = if opts[:nx], do: cmd ++ ["NX"], else: cmd
    cmd = if opts[:xx], do: cmd ++ ["XX"], else: cmd
    cmd = if opts[:ifeq], do: cmd ++ ["IFEQ", to_string(opts[:ifeq])], else: cmd
    cmd = if opts[:ifne], do: cmd ++ ["IFNE", to_string(opts[:ifne])], else: cmd
    cmd = if opts[:get], do: cmd ++ ["GET"], else: cmd
    cmd
  end

  @doc """
  Builds an MGET command to retrieve the values of multiple `keys` in one call.

  Returns a list of values in the same order as the requested keys.
  Keys that do not exist produce `nil` in the corresponding position.
  """
  @spec mget([String.t()]) :: [String.t()]
  def mget(keys) when is_list(keys), do: ["MGET" | keys]

  @spec mset([{String.t(), String.t()}]) :: [String.t()]
  def mset(pairs) when is_list(pairs) do
    ["MSET" | Enum.flat_map(pairs, fn {k, v} -> [k, to_string(v)] end)]
  end

  @doc """
  Builds an INCR command to atomically increment the integer value at `key` by 1.

  If the key does not exist, it is initialized to 0 before incrementing.
  """
  @spec incr(String.t()) :: [String.t()]
  def incr(key), do: ["INCR", key]

  @doc """
  Builds an INCRBY command to atomically increment the integer value at `key`
  by `amount`. The amount may be negative to decrement.
  """
  @spec incrby(String.t(), integer()) :: [String.t()]
  def incrby(key, amount), do: ["INCRBY", key, to_string(amount)]

  @spec decr(String.t()) :: [String.t()]
  def decr(key), do: ["DECR", key]

  @spec decrby(String.t(), integer()) :: [String.t()]
  def decrby(key, amount), do: ["DECRBY", key, to_string(amount)]

  @doc """
  Builds an APPEND command to append `value` to the string already stored at
  `key`. If the key does not exist, it is created with `value` as its content.
  Returns the length of the string after the append operation.
  """
  @spec append(String.t(), String.t()) :: [String.t()]
  def append(key, value), do: ["APPEND", key, value]

  @spec getdel(String.t()) :: [String.t()]
  def getdel(key), do: ["GETDEL", key]

  @doc """
  Builds a GETEX command to retrieve the value at `key` and optionally
  set or clear its expiration.

  ## Options

    * `:ex` - set expiry in seconds
    * `:px` - set expiry in milliseconds
    * `:exat` - set expiry as a Unix timestamp in seconds
    * `:pxat` - set expiry as a Unix timestamp in milliseconds
    * `:persist` - remove the existing expiry
  """
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
  def psetex(key, milliseconds, value),
    do: ["PSETEX", key, to_string(milliseconds), to_string(value)]

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

    cmd =
      if opts[:minmatchlen], do: cmd ++ ["MINMATCHLEN", to_string(opts[:minmatchlen])], else: cmd

    cmd = if opts[:withmatchlen], do: cmd ++ ["WITHMATCHLEN"], else: cmd
    cmd
  end

  # ---------------------------------------------------------------------------
  # Redis 8.0+ string commands
  # ---------------------------------------------------------------------------

  @doc """
  Builds a GETDEL command with conditional deletion (Redis 8.0+). Retrieves
  the value at `key` and deletes it only if the condition is met.

  ## Options

    * `:ifeq` - delete only if the current value equals the given string
    * `:ifne` - delete only if the current value does not equal the given string
  """
  @spec delex(String.t(), keyword()) :: [String.t()]
  def delex(key, opts \\ []) do
    cmd = ["GETDEL", key]
    cmd = if opts[:ifeq], do: cmd ++ ["IFEQ", to_string(opts[:ifeq])], else: cmd
    cmd = if opts[:ifne], do: cmd ++ ["IFNE", to_string(opts[:ifne])], else: cmd
    cmd
  end

  @doc """
  Builds a DIGEST command to return the hash digest of the value stored at
  `key` (Redis 8.0+).
  """
  @spec digest(String.t()) :: [String.t()]
  def digest(key), do: ["DIGEST", key]

  @doc """
  Builds an MSETEX command to atomically set multiple key-value pairs with
  a shared expiration (Redis 8.0+).

  `kv_pairs` is a list of `{key, value}` tuples.

  ## Options

    * `:ex` - set expiry in seconds
    * `:px` - set expiry in milliseconds
    * `:exat` - set expiry as a Unix timestamp in seconds
    * `:pxat` - set expiry as a Unix timestamp in milliseconds
  """
  @spec msetex([{String.t(), String.t()}], keyword()) :: [String.t()]
  def msetex(kv_pairs, opts \\ []) when is_list(kv_pairs) do
    cmd = ["MSETEX"]
    cmd = if opts[:ex], do: cmd ++ ["EX", to_string(opts[:ex])], else: cmd
    cmd = if opts[:px], do: cmd ++ ["PX", to_string(opts[:px])], else: cmd
    cmd = if opts[:exat], do: cmd ++ ["EXAT", to_string(opts[:exat])], else: cmd
    cmd = if opts[:pxat], do: cmd ++ ["PXAT", to_string(opts[:pxat])], else: cmd
    cmd ++ Enum.flat_map(kv_pairs, fn {k, v} -> [k, to_string(v)] end)
  end

  @doc "Deprecated: use getrange/3 instead."
  @spec substr(String.t(), integer(), integer()) :: [String.t()]
  def substr(key, start, stop), do: ["SUBSTR", key, to_string(start), to_string(stop)]
end

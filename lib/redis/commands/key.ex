defmodule Redis.Commands.Key do
  @moduledoc """
  Command builders for Redis key management operations.

  Provides pure functions that build command lists for key-level operations such as
  deleting keys, setting expiration, querying TTL, scanning the keyspace, checking
  existence, renaming, and copying keys. Each function returns a plain list of
  strings suitable for passing to `Redis.command/2` or `Redis.pipeline/2`.

  These functions contain no connection or networking logic -- they only construct
  the Redis protocol command as a list.

  ## Examples

  Delete one or more keys:

      iex> Redis.Commands.Key.del(["session:1", "session:2"])
      ["DEL", "session:1", "session:2"]

  Set a TTL and then read it back:

      iex> Redis.Commands.Key.expire("session:1", 300)
      ["EXPIRE", "session:1", "300"]
      iex> Redis.Commands.Key.ttl("session:1")
      ["TTL", "session:1"]

  Scan the keyspace with a pattern and count hint:

      iex> Redis.Commands.Key.scan(0, match: "user:*", count: 100)
      ["SCAN", "0", "MATCH", "user:*", "COUNT", "100"]
  """

  @doc """
  Builds a DEL command to remove one or more keys.

  Returns the command list for deleting the given keys. Redis returns the number
  of keys that were removed.

  ## Example

      iex> Redis.Commands.Key.del(["key1", "key2"])
      ["DEL", "key1", "key2"]
  """
  @spec del([String.t()]) :: [String.t()]
  def del(keys) when is_list(keys), do: ["DEL" | keys]

  @spec exists([String.t()]) :: [String.t()]
  def exists(keys) when is_list(keys), do: ["EXISTS" | keys]

  @doc """
  Builds an EXPIRE command to set a key's time-to-live in seconds.

  Supports the `:nx` option to set the expiry only when the key has no existing
  expiry.

  ## Examples

      iex> Redis.Commands.Key.expire("session:1", 3600)
      ["EXPIRE", "session:1", "3600"]

      iex> Redis.Commands.Key.expire("session:1", 3600, nx: true)
      ["EXPIRE", "session:1", "3600", "NX"]
  """
  @spec expire(String.t(), integer(), keyword()) :: [String.t()]
  def expire(key, seconds, opts \\ []) do
    cmd = ["EXPIRE", key, to_string(seconds)]
    if opts[:nx], do: cmd ++ ["NX"], else: cmd
  end

  @spec ttl(String.t()) :: [String.t()]
  def ttl(key), do: ["TTL", key]

  @spec type(String.t()) :: [String.t()]
  def type(key), do: ["TYPE", key]

  @doc """
  Builds a SCAN command to incrementally iterate over the keyspace.

  Accepts options for pattern matching (`:match`), iteration count hint
  (`:count`), and key type filtering (`:type`).

  ## Examples

      iex> Redis.Commands.Key.scan(0)
      ["SCAN", "0"]

      iex> Redis.Commands.Key.scan(0, match: "user:*", count: 50, type: "string")
      ["SCAN", "0", "MATCH", "user:*", "COUNT", "50", "TYPE", "string"]
  """
  @spec scan(integer(), keyword()) :: [String.t()]
  def scan(cursor, opts \\ []) do
    cmd = ["SCAN", to_string(cursor)]
    cmd = if opts[:match], do: cmd ++ ["MATCH", opts[:match]], else: cmd
    cmd = if opts[:count], do: cmd ++ ["COUNT", to_string(opts[:count])], else: cmd
    cmd = if opts[:type], do: cmd ++ ["TYPE", opts[:type]], else: cmd
    cmd
  end

  @spec copy(String.t(), String.t(), keyword()) :: [String.t()]
  def copy(source, destination, opts \\ []) do
    cmd = ["COPY", source, destination]
    cmd = if opts[:db], do: cmd ++ ["DB", to_string(opts[:db])], else: cmd
    cmd = if opts[:replace], do: cmd ++ ["REPLACE"], else: cmd
    cmd
  end

  @spec dump(String.t()) :: [String.t()]
  def dump(key), do: ["DUMP", key]

  @spec expireat(String.t(), integer(), keyword()) :: [String.t()]
  def expireat(key, timestamp, opts \\ []) do
    cmd = ["EXPIREAT", key, to_string(timestamp)]
    if opts[:nx], do: cmd ++ ["NX"], else: cmd
  end

  @spec expiretime(String.t()) :: [String.t()]
  def expiretime(key), do: ["EXPIRETIME", key]

  @spec keys(String.t()) :: [String.t()]
  def keys(pattern), do: ["KEYS", pattern]

  @spec object_encoding(String.t()) :: [String.t()]
  def object_encoding(key), do: ["OBJECT", "ENCODING", key]

  @spec object_freq(String.t()) :: [String.t()]
  def object_freq(key), do: ["OBJECT", "FREQ", key]

  @spec object_idletime(String.t()) :: [String.t()]
  def object_idletime(key), do: ["OBJECT", "IDLETIME", key]

  @spec persist(String.t()) :: [String.t()]
  def persist(key), do: ["PERSIST", key]

  @spec pexpire(String.t(), integer(), keyword()) :: [String.t()]
  def pexpire(key, milliseconds, opts \\ []) do
    cmd = ["PEXPIRE", key, to_string(milliseconds)]
    if opts[:nx], do: cmd ++ ["NX"], else: cmd
  end

  @spec pexpireat(String.t(), integer(), keyword()) :: [String.t()]
  def pexpireat(key, timestamp, opts \\ []) do
    cmd = ["PEXPIREAT", key, to_string(timestamp)]
    if opts[:nx], do: cmd ++ ["NX"], else: cmd
  end

  @spec pexpiretime(String.t()) :: [String.t()]
  def pexpiretime(key), do: ["PEXPIRETIME", key]

  @spec pttl(String.t()) :: [String.t()]
  def pttl(key), do: ["PTTL", key]

  @spec randomkey() :: [String.t()]
  def randomkey, do: ["RANDOMKEY"]

  @doc """
  Builds a RENAME command to rename a key.

  ## Example

      iex> Redis.Commands.Key.rename("old_key", "new_key")
      ["RENAME", "old_key", "new_key"]
  """
  @spec rename(String.t(), String.t()) :: [String.t()]
  def rename(key, newkey), do: ["RENAME", key, newkey]

  @spec renamenx(String.t(), String.t()) :: [String.t()]
  def renamenx(key, newkey), do: ["RENAMENX", key, newkey]

  @spec restore(String.t(), integer(), String.t(), keyword()) :: [String.t()]
  def restore(key, ttl, serialized_value, opts \\ []) do
    cmd = ["RESTORE", key, to_string(ttl), serialized_value]
    cmd = if opts[:replace], do: cmd ++ ["REPLACE"], else: cmd
    cmd = if opts[:absttl], do: cmd ++ ["ABSTTL"], else: cmd
    cmd = if opts[:idletime], do: cmd ++ ["IDLETIME", to_string(opts[:idletime])], else: cmd
    cmd = if opts[:freq], do: cmd ++ ["FREQ", to_string(opts[:freq])], else: cmd
    cmd
  end

  @spec sort(String.t(), keyword()) :: [String.t()]
  def sort(key, opts \\ []) do
    cmd = ["SORT", key]
    cmd = if opts[:by], do: cmd ++ ["BY", opts[:by]], else: cmd

    cmd =
      if opts[:limit],
        do: cmd ++ ["LIMIT", to_string(elem(opts[:limit], 0)), to_string(elem(opts[:limit], 1))],
        else: cmd

    cmd =
      if opts[:get],
        do: cmd ++ Enum.flat_map(List.wrap(opts[:get]), fn g -> ["GET", g] end),
        else: cmd

    cmd = if opts[:asc], do: cmd ++ ["ASC"], else: cmd
    cmd = if opts[:desc], do: cmd ++ ["DESC"], else: cmd
    cmd = if opts[:alpha], do: cmd ++ ["ALPHA"], else: cmd
    cmd = if opts[:store], do: cmd ++ ["STORE", opts[:store]], else: cmd
    cmd
  end

  @spec touch([String.t()]) :: [String.t()]
  def touch(keys) when is_list(keys), do: ["TOUCH" | keys]

  @spec unlink([String.t()]) :: [String.t()]
  def unlink(keys) when is_list(keys), do: ["UNLINK" | keys]

  @spec wait(integer(), integer()) :: [String.t()]
  def wait(numreplicas, timeout), do: ["WAIT", to_string(numreplicas), to_string(timeout)]

  @spec sort_ro(String.t(), keyword()) :: [String.t()]
  def sort_ro(key, opts \\ []) do
    cmd = ["SORT_RO", key]
    cmd = if opts[:by], do: cmd ++ ["BY", opts[:by]], else: cmd

    cmd =
      if opts[:limit],
        do: cmd ++ ["LIMIT", to_string(elem(opts[:limit], 0)), to_string(elem(opts[:limit], 1))],
        else: cmd

    cmd =
      if opts[:get],
        do: cmd ++ Enum.flat_map(List.wrap(opts[:get]), fn g -> ["GET", g] end),
        else: cmd

    cmd = if opts[:asc], do: cmd ++ ["ASC"], else: cmd
    cmd = if opts[:desc], do: cmd ++ ["DESC"], else: cmd
    cmd = if opts[:alpha], do: cmd ++ ["ALPHA"], else: cmd
    cmd
  end

  @spec migrate(String.t(), integer(), String.t(), integer(), integer(), keyword()) :: [
          String.t()
        ]
  def migrate(host, port, key, dest_db, timeout, opts \\ []) do
    cmd = ["MIGRATE", host, to_string(port), key, to_string(dest_db), to_string(timeout)]
    cmd = if opts[:copy], do: cmd ++ ["COPY"], else: cmd
    cmd = if opts[:replace], do: cmd ++ ["REPLACE"], else: cmd
    cmd = if opts[:auth], do: cmd ++ ["AUTH", opts[:auth]], else: cmd

    cmd =
      if opts[:auth2],
        do: cmd ++ ["AUTH2", elem(opts[:auth2], 0), elem(opts[:auth2], 1)],
        else: cmd

    cmd = if opts[:keys], do: cmd ++ ["KEYS" | opts[:keys]], else: cmd
    cmd
  end
end

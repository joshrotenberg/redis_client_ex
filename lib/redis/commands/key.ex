defmodule Redis.Commands.Key do
  @moduledoc """
  Command builders for Redis key operations.

  Pure functions that return command lists — no connection logic.

  ## TODO (Phase 2)

  DEL, EXISTS, EXPIRE, EXPIREAT, KEYS, PERSIST, PEXPIRE, PTTL,
  RANDOMKEY, RENAME, RENAMENX, SCAN, SORT, TTL, TYPE, UNLINK, WAIT
  """

  @spec del([String.t()]) :: [String.t()]
  def del(keys) when is_list(keys), do: ["DEL" | keys]

  @spec exists([String.t()]) :: [String.t()]
  def exists(keys) when is_list(keys), do: ["EXISTS" | keys]

  @spec expire(String.t(), integer(), keyword()) :: [String.t()]
  def expire(key, seconds, opts \\ []) do
    cmd = ["EXPIRE", key, to_string(seconds)]
    if opts[:nx], do: cmd ++ ["NX"], else: cmd
  end

  @spec ttl(String.t()) :: [String.t()]
  def ttl(key), do: ["TTL", key]

  @spec type(String.t()) :: [String.t()]
  def type(key), do: ["TYPE", key]

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
    cmd = if opts[:limit], do: cmd ++ ["LIMIT", to_string(elem(opts[:limit], 0)), to_string(elem(opts[:limit], 1))], else: cmd
    cmd = if opts[:get], do: cmd ++ Enum.flat_map(List.wrap(opts[:get]), fn g -> ["GET", g] end), else: cmd
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
    cmd = if opts[:limit], do: cmd ++ ["LIMIT", to_string(elem(opts[:limit], 0)), to_string(elem(opts[:limit], 1))], else: cmd
    cmd = if opts[:get], do: cmd ++ Enum.flat_map(List.wrap(opts[:get]), fn g -> ["GET", g] end), else: cmd
    cmd = if opts[:asc], do: cmd ++ ["ASC"], else: cmd
    cmd = if opts[:desc], do: cmd ++ ["DESC"], else: cmd
    cmd = if opts[:alpha], do: cmd ++ ["ALPHA"], else: cmd
    cmd
  end

  @spec migrate(String.t(), integer(), String.t(), integer(), integer(), keyword()) :: [String.t()]
  def migrate(host, port, key, dest_db, timeout, opts \\ []) do
    cmd = ["MIGRATE", host, to_string(port), key, to_string(dest_db), to_string(timeout)]
    cmd = if opts[:copy], do: cmd ++ ["COPY"], else: cmd
    cmd = if opts[:replace], do: cmd ++ ["REPLACE"], else: cmd
    cmd = if opts[:auth], do: cmd ++ ["AUTH", opts[:auth]], else: cmd
    cmd = if opts[:auth2], do: cmd ++ ["AUTH2", elem(opts[:auth2], 0), elem(opts[:auth2], 1)], else: cmd
    cmd = if opts[:keys], do: cmd ++ ["KEYS" | opts[:keys]], else: cmd
    cmd
  end
end

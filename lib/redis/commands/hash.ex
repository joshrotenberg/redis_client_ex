defmodule Redis.Commands.Hash do
  @moduledoc """
  Command builders for Redis hash operations.

  This module provides pure functions that return Redis command lists for
  hash data type operations, including setting and retrieving fields,
  atomic field increments, and hash scanning. All functions return a list
  of strings suitable for use with `Redis.command/2` or `Redis.pipeline/2`.

  ## Examples

      # HSET with multiple fields at once
      iex> Redis.Commands.Hash.hset("user:1", [{"name", "Alice"}, {"age", "30"}])
      ["HSET", "user:1", "name", "Alice", "age", "30"]

      # Retrieve all fields and values
      iex> Redis.Commands.Hash.hgetall("user:1")
      ["HGETALL", "user:1"]

      # Atomically increment a numeric field
      iex> Redis.Commands.Hash.hincrby("user:1", "login_count", 1)
      ["HINCRBY", "user:1", "login_count", "1"]
  """

  @doc """
  Builds an HGET command to retrieve the value of a single `field` in the
  hash stored at `key`. Returns `nil` when the field or key does not exist.
  """
  @spec hget(String.t(), String.t()) :: [String.t()]
  def hget(key, field), do: ["HGET", key, field]

  @doc """
  Builds an HSET command to set one or more field-value pairs in the hash
  stored at `key`. Accepts a list of `{field, value}` tuples. Fields that
  already exist are overwritten.
  """
  @spec hset(String.t(), [{String.t(), String.t()}]) :: [String.t()]
  def hset(key, pairs) when is_list(pairs) do
    ["HSET", key | Enum.flat_map(pairs, fn {f, v} -> [f, to_string(v)] end)]
  end

  @doc """
  Builds an HGETALL command to retrieve all fields and values in the hash
  stored at `key`. The result from Redis is a flat list alternating between
  field names and their values.
  """
  @spec hgetall(String.t()) :: [String.t()]
  def hgetall(key), do: ["HGETALL", key]

  @doc """
  Builds an HDEL command to remove one or more `fields` from the hash at `key`.
  Returns the number of fields that were removed.
  """
  @spec hdel(String.t(), [String.t()]) :: [String.t()]
  def hdel(key, fields) when is_list(fields), do: ["HDEL", key | fields]

  @doc """
  Builds an HINCRBY command to atomically increment the integer value of
  `field` in the hash at `key` by `amount`. If the field does not exist,
  it is initialized to 0 before incrementing.
  """
  @spec hincrby(String.t(), String.t(), integer()) :: [String.t()]
  def hincrby(key, field, amount), do: ["HINCRBY", key, field, to_string(amount)]

  @spec hkeys(String.t()) :: [String.t()]
  def hkeys(key), do: ["HKEYS", key]

  @spec hvals(String.t()) :: [String.t()]
  def hvals(key), do: ["HVALS", key]

  @spec hlen(String.t()) :: [String.t()]
  def hlen(key), do: ["HLEN", key]

  @spec hexists(String.t(), String.t()) :: [String.t()]
  def hexists(key, field), do: ["HEXISTS", key, field]

  @spec hincrbyfloat(String.t(), String.t(), float()) :: [String.t()]
  def hincrbyfloat(key, field, amount), do: ["HINCRBYFLOAT", key, field, to_string(amount)]

  @spec hmget(String.t(), [String.t()]) :: [String.t()]
  def hmget(key, fields) when is_list(fields), do: ["HMGET", key | fields]

  @spec hrandfield(String.t(), keyword()) :: [String.t()]
  def hrandfield(key, opts \\ []) do
    cmd = ["HRANDFIELD", key]
    cmd = if opts[:count], do: cmd ++ [to_string(opts[:count])], else: cmd
    cmd = if opts[:withvalues], do: cmd ++ ["WITHVALUES"], else: cmd
    cmd
  end

  @doc """
  Builds an HSCAN command to incrementally iterate over fields in the hash
  at `key`. Start with `cursor` 0 and use the cursor returned by Redis in
  subsequent calls until it returns 0.

  ## Options

    * `:match` - glob-style pattern to filter field names
    * `:count` - hint for how many elements to return per call
  """
  @spec hscan(String.t(), integer(), keyword()) :: [String.t()]
  def hscan(key, cursor, opts \\ []) do
    cmd = ["HSCAN", key, to_string(cursor)]
    cmd = if opts[:match], do: cmd ++ ["MATCH", opts[:match]], else: cmd
    cmd = if opts[:count], do: cmd ++ ["COUNT", to_string(opts[:count])], else: cmd
    cmd
  end

  @spec hsetnx(String.t(), String.t(), String.t()) :: [String.t()]
  def hsetnx(key, field, value), do: ["HSETNX", key, field, to_string(value)]

  @spec hstrlen(String.t(), String.t()) :: [String.t()]
  def hstrlen(key, field), do: ["HSTRLEN", key, field]

  # ---------------------------------------------------------------------------
  # Redis 8.0+ hash commands
  # ---------------------------------------------------------------------------

  @doc """
  Builds an HGETEX command to retrieve the values of one or more `fields` in
  the hash at `key` and optionally set or clear per-field expiration (Redis 8.0+).

  ## Options

    * `:ex` - set expiry in seconds
    * `:px` - set expiry in milliseconds
    * `:exat` - set expiry as a Unix timestamp in seconds
    * `:pxat` - set expiry as a Unix timestamp in milliseconds
    * `:persist` - remove existing expiry from the fields
  """
  @spec hgetex(String.t(), [String.t()], keyword()) :: [String.t()]
  def hgetex(key, fields, opts \\ []) when is_list(fields) do
    cmd = ["HGETEX", key, "FIELDS", to_string(length(fields)) | fields]
    cmd = if opts[:ex], do: cmd ++ ["EX", to_string(opts[:ex])], else: cmd
    cmd = if opts[:px], do: cmd ++ ["PX", to_string(opts[:px])], else: cmd
    cmd = if opts[:exat], do: cmd ++ ["EXAT", to_string(opts[:exat])], else: cmd
    cmd = if opts[:pxat], do: cmd ++ ["PXAT", to_string(opts[:pxat])], else: cmd
    cmd = if opts[:persist], do: cmd ++ ["PERSIST"], else: cmd
    cmd
  end

  @doc """
  Builds an HSETEX command to set one or more field-value pairs in the hash at
  `key` with a per-field expiration (Redis 8.0+).

  `field_values` is a list of `{field, value}` tuples.

  ## Options

    * `:ex` - set expiry in seconds
    * `:px` - set expiry in milliseconds
    * `:exat` - set expiry as a Unix timestamp in seconds
    * `:pxat` - set expiry as a Unix timestamp in milliseconds
  """
  @spec hsetex(String.t(), [{String.t(), String.t()}], keyword()) :: [String.t()]
  def hsetex(key, field_values, opts \\ []) when is_list(field_values) do
    num_fields = length(field_values)
    pairs = Enum.flat_map(field_values, fn {f, v} -> [f, to_string(v)] end)
    cmd = ["HSETEX", key]
    cmd = if opts[:ex], do: cmd ++ ["EX", to_string(opts[:ex])], else: cmd
    cmd = if opts[:px], do: cmd ++ ["PX", to_string(opts[:px])], else: cmd
    cmd = if opts[:exat], do: cmd ++ ["EXAT", to_string(opts[:exat])], else: cmd
    cmd = if opts[:pxat], do: cmd ++ ["PXAT", to_string(opts[:pxat])], else: cmd
    cmd ++ ["FIELDS", to_string(num_fields) | pairs]
  end

  @doc """
  Builds an HGETDEL command to atomically retrieve and delete one or more
  `fields` from the hash at `key` (Redis 8.0+).
  """
  @spec hgetdel(String.t(), [String.t()]) :: [String.t()]
  def hgetdel(key, fields) when is_list(fields) do
    ["HGETDEL", key, "FIELDS", to_string(length(fields)) | fields]
  end

  @doc "Deprecated: use hset/2 instead."
  @spec hmset(String.t(), [{String.t(), String.t()}]) :: [String.t()]
  def hmset(key, pairs) when is_list(pairs) do
    ["HMSET", key | Enum.flat_map(pairs, fn {f, v} -> [f, to_string(v)] end)]
  end

  # ---------------------------------------------------------------------------
  # Hash field expiration commands (Redis 7.4+)
  # ---------------------------------------------------------------------------

  @doc """
  Builds an HEXPIRE command to set a timeout in `seconds` on one or more
  hash `fields` stored at `key`.

  ## Options

    * `:nx` - set expiry only when the field has no expiry
    * `:xx` - set expiry only when the field already has an expiry
    * `:gt` - set expiry only when the new expiry is greater than the current one
    * `:lt` - set expiry only when the new expiry is less than the current one
  """
  @spec hexpire(String.t(), integer(), [String.t()], keyword()) :: [String.t()]
  def hexpire(key, seconds, fields, opts \\ []) when is_list(fields) do
    ["HEXPIRE", key, to_string(seconds)]
    |> append_expire_opts(opts)
    |> append_fields(fields)
  end

  @doc """
  Builds an HPEXPIRE command to set a timeout in `milliseconds` on one or more
  hash `fields` stored at `key`.

  Accepts the same options as `hexpire/4`.
  """
  @spec hpexpire(String.t(), integer(), [String.t()], keyword()) :: [String.t()]
  def hpexpire(key, milliseconds, fields, opts \\ []) when is_list(fields) do
    ["HPEXPIRE", key, to_string(milliseconds)]
    |> append_expire_opts(opts)
    |> append_fields(fields)
  end

  @doc """
  Builds an HEXPIREAT command to set an expiry on one or more hash `fields`
  at the given absolute Unix `timestamp` (seconds).

  Accepts the same options as `hexpire/4`.
  """
  @spec hexpireat(String.t(), integer(), [String.t()], keyword()) :: [String.t()]
  def hexpireat(key, timestamp, fields, opts \\ []) when is_list(fields) do
    ["HEXPIREAT", key, to_string(timestamp)]
    |> append_expire_opts(opts)
    |> append_fields(fields)
  end

  @doc """
  Builds an HPEXPIREAT command to set an expiry on one or more hash `fields`
  at the given absolute Unix `timestamp` (milliseconds).

  Accepts the same options as `hexpire/4`.
  """
  @spec hpexpireat(String.t(), integer(), [String.t()], keyword()) :: [String.t()]
  def hpexpireat(key, timestamp_ms, fields, opts \\ []) when is_list(fields) do
    ["HPEXPIREAT", key, to_string(timestamp_ms)]
    |> append_expire_opts(opts)
    |> append_fields(fields)
  end

  @doc """
  Builds an HTTL command to retrieve the remaining time-to-live in seconds
  for each of the specified hash `fields` at `key`.
  """
  @spec httl(String.t(), [String.t()]) :: [String.t()]
  def httl(key, fields) when is_list(fields) do
    ["HTTL", key] |> append_fields(fields)
  end

  @doc """
  Builds an HPTTL command to retrieve the remaining time-to-live in
  milliseconds for each of the specified hash `fields` at `key`.
  """
  @spec hpttl(String.t(), [String.t()]) :: [String.t()]
  def hpttl(key, fields) when is_list(fields) do
    ["HPTTL", key] |> append_fields(fields)
  end

  @doc """
  Builds an HEXPIRETIME command to retrieve the absolute Unix expiration
  timestamp (seconds) for each of the specified hash `fields` at `key`.
  """
  @spec hexpiretime(String.t(), [String.t()]) :: [String.t()]
  def hexpiretime(key, fields) when is_list(fields) do
    ["HEXPIRETIME", key] |> append_fields(fields)
  end

  @doc """
  Builds an HPEXPIRETIME command to retrieve the absolute Unix expiration
  timestamp (milliseconds) for each of the specified hash `fields` at `key`.
  """
  @spec hpexpiretime(String.t(), [String.t()]) :: [String.t()]
  def hpexpiretime(key, fields) when is_list(fields) do
    ["HPEXPIRETIME", key] |> append_fields(fields)
  end

  @doc """
  Builds an HPERSIST command to remove the expiration from one or more
  hash `fields` at `key`, making them persistent.
  """
  @spec hpersist(String.t(), [String.t()]) :: [String.t()]
  def hpersist(key, fields) when is_list(fields) do
    ["HPERSIST", key] |> append_fields(fields)
  end

  # -- Private helpers --------------------------------------------------------

  defp append_fields(cmd, fields) do
    cmd ++ ["FIELDS", to_string(length(fields)) | fields]
  end

  defp append_expire_opts(cmd, opts) do
    cond do
      opts[:nx] -> cmd ++ ["NX"]
      opts[:xx] -> cmd ++ ["XX"]
      opts[:gt] -> cmd ++ ["GT"]
      opts[:lt] -> cmd ++ ["LT"]
      true -> cmd
    end
  end
end

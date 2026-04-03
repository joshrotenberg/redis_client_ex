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

  @doc "Deprecated: use hset/2 instead."
  @spec hmset(String.t(), [{String.t(), String.t()}]) :: [String.t()]
  def hmset(key, pairs) when is_list(pairs) do
    ["HMSET", key | Enum.flat_map(pairs, fn {f, v} -> [f, to_string(v)] end)]
  end

  # -------------------------------------------------------------------
  # Hash field expiration (Redis 7.4+)
  # -------------------------------------------------------------------

  @doc "HEXPIRE — set TTL in seconds on hash fields. Options: :nx, :xx, :gt, :lt"
  @spec hexpire(String.t(), integer(), [String.t()], keyword()) :: [String.t()]
  def hexpire(key, seconds, fields, opts \\ []) when is_list(fields) do
    ["HEXPIRE", key, to_string(seconds)] ++ condition_args(opts) ++ fields_args(fields)
  end

  @doc "HPEXPIRE — set TTL in milliseconds on hash fields."
  @spec hpexpire(String.t(), integer(), [String.t()], keyword()) :: [String.t()]
  def hpexpire(key, ms, fields, opts \\ []) when is_list(fields) do
    ["HPEXPIRE", key, to_string(ms)] ++ condition_args(opts) ++ fields_args(fields)
  end

  @doc "HEXPIREAT — set expiry as Unix timestamp (seconds) on hash fields."
  @spec hexpireat(String.t(), integer(), [String.t()], keyword()) :: [String.t()]
  def hexpireat(key, timestamp, fields, opts \\ []) when is_list(fields) do
    ["HEXPIREAT", key, to_string(timestamp)] ++ condition_args(opts) ++ fields_args(fields)
  end

  @doc "HPEXPIREAT — set expiry as Unix timestamp (milliseconds) on hash fields."
  @spec hpexpireat(String.t(), integer(), [String.t()], keyword()) :: [String.t()]
  def hpexpireat(key, ms_timestamp, fields, opts \\ []) when is_list(fields) do
    ["HPEXPIREAT", key, to_string(ms_timestamp)] ++ condition_args(opts) ++ fields_args(fields)
  end

  @doc "HTTL — get TTL in seconds for hash fields."
  @spec httl(String.t(), [String.t()]) :: [String.t()]
  def httl(key, fields) when is_list(fields) do
    ["HTTL", key | fields_args(fields)]
  end

  @doc "HPTTL — get TTL in milliseconds for hash fields."
  @spec hpttl(String.t(), [String.t()]) :: [String.t()]
  def hpttl(key, fields) when is_list(fields) do
    ["HPTTL", key | fields_args(fields)]
  end

  @doc "HEXPIRETIME — get expiry as Unix timestamp (seconds) for hash fields."
  @spec hexpiretime(String.t(), [String.t()]) :: [String.t()]
  def hexpiretime(key, fields) when is_list(fields) do
    ["HEXPIRETIME", key | fields_args(fields)]
  end

  @doc "HPEXPIRETIME — get expiry as Unix timestamp (ms) for hash fields."
  @spec hpexpiretime(String.t(), [String.t()]) :: [String.t()]
  def hpexpiretime(key, fields) when is_list(fields) do
    ["HPEXPIRETIME", key | fields_args(fields)]
  end

  @doc "HPERSIST — remove TTL from hash fields."
  @spec hpersist(String.t(), [String.t()]) :: [String.t()]
  def hpersist(key, fields) when is_list(fields) do
    ["HPERSIST", key | fields_args(fields)]
  end

  # -------------------------------------------------------------------
  # Redis 8.0+ hash commands
  # -------------------------------------------------------------------

  @doc "HGETEX — get fields and optionally set expiration. Options: :ex, :px, :exat, :pxat, :persist"
  @spec hgetex(String.t(), [String.t()], keyword()) :: [String.t()]
  def hgetex(key, fields, opts \\ []) when is_list(fields) do
    ["HGETEX", key | fields_args(fields)] ++ expiry_args(opts)
  end

  @doc "HSETEX — set fields with expiration. Options: :ex, :px, :exat, :pxat"
  @spec hsetex(String.t(), [{String.t(), String.t()}], keyword()) :: [String.t()]
  def hsetex(key, field_values, opts \\ []) when is_list(field_values) do
    fv = Enum.flat_map(field_values, fn {f, v} -> [f, to_string(v)] end)
    ["HSETEX", key | fields_args_raw(fv)] ++ expiry_args(opts)
  end

  @doc "HGETDEL — get and delete hash fields atomically."
  @spec hgetdel(String.t(), [String.t()]) :: [String.t()]
  def hgetdel(key, fields) when is_list(fields) do
    ["HGETDEL", key | fields_args(fields)]
  end

  # -------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------

  defp fields_args(fields) do
    ["FIELDS", to_string(length(fields)) | fields]
  end

  defp fields_args_raw(flat_list) do
    count = div(length(flat_list), 2)
    ["FIELDS", to_string(count) | flat_list]
  end

  defp condition_args(opts) do
    cond do
      opts[:nx] -> ["NX"]
      opts[:xx] -> ["XX"]
      opts[:gt] -> ["GT"]
      opts[:lt] -> ["LT"]
      true -> []
    end
  end

  defp expiry_args(opts) do
    cond do
      opts[:ex] -> ["EX", to_string(opts[:ex])]
      opts[:px] -> ["PX", to_string(opts[:px])]
      opts[:exat] -> ["EXAT", to_string(opts[:exat])]
      opts[:pxat] -> ["PXAT", to_string(opts[:pxat])]
      opts[:persist] -> ["PERSIST"]
      true -> []
    end
  end
end

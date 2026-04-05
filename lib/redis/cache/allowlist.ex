defmodule Redis.Cache.Allowlist do
  @moduledoc """
  Default allowlist of cacheable read-only Redis commands and helpers
  for normalizing user-provided cacheable configuration.

  The allowlist contains single-key read-only commands where the first
  argument after the command name is the Redis key. Multi-key commands
  like MGET, SDIFF, and SINTER are excluded (MGET has its own
  specialized handler in `Redis.Cache`).

  ## Configuration Formats

  The `:cacheable` option accepts three formats:

    * `:default` - uses the built-in allowlist with no per-command TTL overrides
    * A list of command entries:
      ```
      ["GET", "HGETALL", {"LRANGE", ttl: 5_000}]
      ```
    * A function for full control:
      ```
      fn ["GET" | _] -> true; ["LRANGE" | _] -> {:ok, 5_000}; _ -> false end
      ```
  """

  @default_commands [
    # String / generic
    "BITCOUNT",
    "BITPOS",
    "EXISTS",
    "GET",
    "GETBIT",
    "GETRANGE",
    "STRLEN",
    "TYPE",
    # Hash
    "HEXISTS",
    "HGET",
    "HGETALL",
    "HKEYS",
    "HLEN",
    "HMGET",
    "HSTRLEN",
    "HVALS",
    # List
    "LINDEX",
    "LLEN",
    "LPOS",
    "LRANGE",
    # Set (single-key only)
    "SCARD",
    "SISMEMBER",
    "SMEMBERS",
    "SMISMEMBER",
    # Sorted Set (single-key only)
    "ZCARD",
    "ZCOUNT",
    "ZLEXCOUNT",
    "ZMSCORE",
    "ZRANGE",
    "ZRANGEBYLEX",
    "ZRANGEBYSCORE",
    "ZRANK",
    "ZREVRANGE",
    "ZREVRANGEBYLEX",
    "ZREVRANGEBYSCORE",
    "ZREVRANK",
    "ZSCORE",
    # Geo
    "GEODIST",
    "GEOHASH",
    "GEOPOS",
    "GEOSEARCH",
    # Stream (single-key only)
    "XLEN",
    "XPENDING",
    "XRANGE",
    "XREVRANGE",
    # JSON
    "JSON.ARRINDEX",
    "JSON.ARRLEN",
    "JSON.GET",
    "JSON.OBJKEYS",
    "JSON.OBJLEN",
    "JSON.STRLEN",
    "JSON.TYPE",
    # TimeSeries
    "TS.GET",
    "TS.INFO",
    "TS.RANGE",
    "TS.REVRANGE"
  ]

  @doc "Returns the default set of cacheable command names."
  @spec default_commands() :: [String.t()]
  def default_commands, do: @default_commands

  @doc """
  Normalizes the `:cacheable` option into an internal representation.

  Returns either:
    * `{:map, %{command => ttl | nil}}` for list/default configs
    * `{:function, fun}` for function configs
  """
  @spec normalize(term()) :: {:map, %{String.t() => non_neg_integer() | nil}} | {:function, fun()}
  def normalize(:default) do
    {:map, Map.new(@default_commands, &{&1, nil})}
  end

  def normalize(fun) when is_function(fun, 1) do
    {:function, fun}
  end

  def normalize(entries) when is_list(entries) do
    map =
      Map.new(entries, fn
        {cmd, opts} when is_list(opts) ->
          {String.upcase(to_string(cmd)), Keyword.get(opts, :ttl)}

        cmd ->
          {String.upcase(to_string(cmd)), nil}
      end)

    {:map, map}
  end

  @doc """
  Checks if a command is cacheable and returns its TTL override (if any).

  Returns:
    * `{:ok, ttl}` where ttl is `nil` (use global) or a positive integer
    * `:nocache`
  """
  @spec check({:map, map()} | {:function, fun()}, [String.t()]) ::
          {:ok, non_neg_integer() | nil} | :nocache
  def check({:map, map}, [cmd | _]) do
    case Map.fetch(map, String.upcase(cmd)) do
      {:ok, ttl} -> {:ok, ttl}
      :error -> :nocache
    end
  end

  def check({:function, fun}, args) do
    case fun.(args) do
      true -> {:ok, nil}
      {:ok, ttl} -> {:ok, ttl}
      _ -> :nocache
    end
  end

  def check(_, _), do: :nocache
end

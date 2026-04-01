defmodule RedisEx.Commands.Key do
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
end

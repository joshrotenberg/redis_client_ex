defmodule RedisEx.Commands.String do
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
end

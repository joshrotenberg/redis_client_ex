defmodule Redis.Commands.Set do
  @moduledoc """
  Command builders for Redis set operations.

  This module provides pure functions that build Redis SET command lists.
  Sets are unordered collections of unique strings, useful for membership
  tracking, tagging, and computing intersections, unions, and differences
  across collections.

  Every function returns a plain list of strings (a command). To execute
  a command, pass the result to `Redis.command/2`; to batch several
  commands in a single round trip, use `Redis.pipeline/2`.

  ## Examples

  Adding members and retrieving a set:

      iex> Redis.command(conn, Redis.Commands.Set.sadd("tags", ["elixir", "redis", "otp"]))
      {:ok, 3}

      iex> Redis.command(conn, Redis.Commands.Set.smembers("tags"))
      {:ok, ["elixir", "redis", "otp"]}

  Set operations -- intersection and union:

      iex> Redis.pipeline(conn, [
      ...>   Redis.Commands.Set.sadd("set:a", ["1", "2", "3"]),
      ...>   Redis.Commands.Set.sadd("set:b", ["2", "3", "4"]),
      ...>   Redis.Commands.Set.sinter(["set:a", "set:b"]),
      ...>   Redis.Commands.Set.sunion(["set:a", "set:b"])
      ...> ])
      {:ok, [3, 3, ["2", "3"], ["1", "2", "3", "4"]]}

  Removing members:

      iex> Redis.command(conn, Redis.Commands.Set.srem("tags", ["otp"]))
      {:ok, 1}
  """

  @doc """
  Builds a SADD command to add one or more `members` to the set at `key`.

  Returns the number of members that were added (excluding duplicates).
  """
  @spec sadd(String.t(), [String.t()]) :: [String.t()]
  def sadd(key, members) when is_list(members), do: ["SADD", key | members]

  @doc """
  Builds a SREM command to remove one or more `members` from the set at `key`.

  Returns the number of members that were actually removed.
  """
  @spec srem(String.t(), [String.t()]) :: [String.t()]
  def srem(key, members) when is_list(members), do: ["SREM", key | members]

  @doc """
  Builds a SMEMBERS command to return all members of the set at `key`.

  For large sets, consider `sscan/3` instead to iterate incrementally.
  """
  @spec smembers(String.t()) :: [String.t()]
  def smembers(key), do: ["SMEMBERS", key]

  @doc """
  Builds a SISMEMBER command to test whether `member` belongs to the set at `key`.

  Returns 1 if the member exists, 0 otherwise.
  """
  @spec sismember(String.t(), String.t()) :: [String.t()]
  def sismember(key, member), do: ["SISMEMBER", key, member]

  @spec scard(String.t()) :: [String.t()]
  def scard(key), do: ["SCARD", key]

  @doc """
  Builds a SDIFF command to return members in the first set that are not in any
  of the subsequent sets listed in `keys`.
  """
  @spec sdiff([String.t()]) :: [String.t()]
  def sdiff(keys) when is_list(keys), do: ["SDIFF" | keys]

  @spec sdiffstore(String.t(), [String.t()]) :: [String.t()]
  def sdiffstore(destination, keys) when is_list(keys), do: ["SDIFFSTORE", destination | keys]

  @doc """
  Builds a SINTER command to return the intersection of all sets in `keys`.

  Only members present in every listed set are returned.
  """
  @spec sinter([String.t()]) :: [String.t()]
  def sinter(keys) when is_list(keys), do: ["SINTER" | keys]

  @spec sintercard(integer(), [String.t()], keyword()) :: [String.t()]
  def sintercard(numkeys, keys, opts \\ []) when is_list(keys) do
    cmd = ["SINTERCARD", to_string(numkeys)] ++ keys
    if opts[:limit], do: cmd ++ ["LIMIT", to_string(opts[:limit])], else: cmd
  end

  @spec sinterstore(String.t(), [String.t()]) :: [String.t()]
  def sinterstore(destination, keys) when is_list(keys), do: ["SINTERSTORE", destination | keys]

  @spec smismember(String.t(), [String.t()]) :: [String.t()]
  def smismember(key, members) when is_list(members), do: ["SMISMEMBER", key | members]

  @spec smove(String.t(), String.t(), String.t()) :: [String.t()]
  def smove(source, destination, member), do: ["SMOVE", source, destination, member]

  @spec spop(String.t(), integer() | nil) :: [String.t()]
  def spop(key, count \\ nil) do
    if count, do: ["SPOP", key, to_string(count)], else: ["SPOP", key]
  end

  @spec srandmember(String.t(), integer() | nil) :: [String.t()]
  def srandmember(key, count \\ nil) do
    if count, do: ["SRANDMEMBER", key, to_string(count)], else: ["SRANDMEMBER", key]
  end

  @spec sscan(String.t(), integer(), keyword()) :: [String.t()]
  def sscan(key, cursor, opts \\ []) do
    cmd = ["SSCAN", key, to_string(cursor)]
    cmd = if opts[:match], do: cmd ++ ["MATCH", opts[:match]], else: cmd
    cmd = if opts[:count], do: cmd ++ ["COUNT", to_string(opts[:count])], else: cmd
    cmd
  end

  @doc """
  Builds a SUNION command to return the union of all sets in `keys`.
  """
  @spec sunion([String.t()]) :: [String.t()]
  def sunion(keys) when is_list(keys), do: ["SUNION" | keys]

  @spec sunionstore(String.t(), [String.t()]) :: [String.t()]
  def sunionstore(destination, keys) when is_list(keys), do: ["SUNIONSTORE", destination | keys]
end

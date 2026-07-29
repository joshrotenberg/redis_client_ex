defmodule Redis.ReplicaSet.CommandMetadata do
  @moduledoc false

  alias Redis.Connection

  # Used only when COMMAND is unavailable (for example, because an ACL denies it).
  # Redis' own command metadata is the source of truth during normal operation.
  @fallback_read_only ~w(
    BITCOUNT BITFIELD_RO BITPOS DBSIZE DUMP EVAL_RO EVALSHA_RO EXISTS EXPIRETIME
    FCALL_RO
    GEODIST GEOHASH GEOPOS GEOSEARCH
    GET GETBIT GETRANGE
    HGET HGETALL HEXISTS HKEYS HLEN HMGET HRANDFIELD HSCAN HSTRLEN HVALS
    KEYS LCS LINDEX LLEN LPOS LRANGE
    MGET OBJECT PEXPIRETIME PFCOUNT PTTL RANDOMKEY SCAN SORT_RO
    SCARD SDIFF SINTER SINTERCARD SISMEMBER SMEMBERS SMISMEMBER SRANDMEMBER SSCAN
    STRLEN SUBSTR SUNION TTL TYPE
    XINFO XLEN XPENDING XRANGE XREAD XREVRANGE
    ZCARD ZCOUNT ZDIFF ZINTER ZINTERCARD ZLEXCOUNT ZMSCORE ZRANDMEMBER
    ZRANGE ZRANGEBYLEX ZRANGEBYSCORE ZRANK ZREVRANGE ZREVRANGEBYLEX
    ZREVRANGEBYSCORE ZREVRANK ZSCAN ZSCORE ZUNION
  )

  @spec fetch(GenServer.server(), [String.t()], timeout()) :: MapSet.t(String.t())
  def fetch(connection, extra_commands \\ [], timeout \\ 5_000) do
    discovered =
      case Connection.command(connection, ["COMMAND"], timeout: timeout) do
        {:ok, response} -> from_command_response(response)
        {:error, _reason} -> MapSet.new()
      end

    @fallback_read_only
    |> MapSet.new()
    |> MapSet.union(discovered)
    |> MapSet.union(normalize_commands(extra_commands))
  end

  @doc false
  @spec from_command_response(term()) :: MapSet.t(String.t())
  def from_command_response(response), do: collect(response, MapSet.new())

  @spec read_only?(MapSet.t(String.t()), [term()]) :: boolean()
  def read_only?(_commands, []), do: false

  def read_only?(commands, [command | arguments]) do
    command = command |> to_string() |> String.upcase()

    subcommand =
      case arguments do
        [subcommand | _rest] -> command <> "|" <> (subcommand |> to_string() |> String.upcase())
        [] -> nil
      end

    MapSet.member?(commands, command) or
      (subcommand != nil and MapSet.member?(commands, subcommand))
  end

  defp collect([name, arity, flags | rest], commands)
       when is_binary(name) and is_integer(arity) do
    commands =
      if flag_member?(flags, "readonly") do
        MapSet.put(commands, String.upcase(name))
      else
        commands
      end

    Enum.reduce(rest, commands, &collect/2)
  end

  defp collect(list, commands) when is_list(list),
    do: Enum.reduce(list, commands, &collect/2)

  defp collect(_term, commands), do: commands

  defp flag_member?(%MapSet{} = flags, flag), do: MapSet.member?(flags, flag)
  defp flag_member?(flags, flag) when is_list(flags), do: flag in flags
  defp flag_member?(_flags, _flag), do: false

  defp normalize_commands(commands) do
    commands
    |> List.wrap()
    |> Enum.map(&(to_string(&1) |> String.upcase()))
    |> MapSet.new()
  end
end

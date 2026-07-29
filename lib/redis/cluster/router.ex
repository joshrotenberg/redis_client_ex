defmodule Redis.Cluster.Router do
  @moduledoc """
  Hash slot router for Redis Cluster.

  Computes CRC16 hash slots and extracts keys from commands for routing.
  """

  @hash_slots 16_384
  @keyless_commands ~w(
    ACL ASKING AUTH BGREWRITEAOF BGSAVE CLIENT CLUSTER COMMAND CONFIG DBSIZE
    DEBUG ECHO FAILOVER FLUSHALL FLUSHDB FUNCTION HELLO INFO LASTSAVE LATENCY
    KEYS MODULE MONITOR PING PSUBSCRIBE PUBLISH PUBSUB PUNSUBSCRIBE QUIT
    READONLY READWRITE REPLICAOF RESET ROLE SAVE SCAN SCRIPT SELECT SHUTDOWN
    SLOWLOG SUBSCRIBE SWAPDB SYNC TIME UNSUBSCRIBE WAIT WAITAOF
  )
  @all_args_are_keys ~w(
    DEL EXISTS MGET PFCOUNT PFMERGE SDIFF SDIFFSTORE SINTER SINTERSTORE SUNION
    SUNIONSTORE TOUCH UNLINK WATCH
  )
  @two_key_commands ~w(
    BLMOVE BRPOPLPUSH COPY LMOVE RENAME RENAMENX RPOPLPUSH SMOVE
  )

  @doc "Computes the hash slot for a key."
  @spec slot(String.t()) :: non_neg_integer()
  def slot(key) do
    key = extract_hash_tag(key)
    crc16(key) |> rem(@hash_slots)
  end

  @doc """
  Extracts the first key from a Redis command for slot routing.
  """
  @spec key_from_command([String.t()]) :: String.t() | nil
  def key_from_command(command), do: command |> keys_from_command() |> List.first()

  @doc """
  Extracts the keys referenced by a command.

  Commands with dynamic key positions (such as `EVAL`, `XREAD`, and the
  `*MPOP` family) and common multi-key commands are handled explicitly.
  Unknown commands fall back to Redis' usual first-argument key convention.
  """
  @spec keys_from_command([String.t()]) :: [String.t()]
  def keys_from_command([]), do: []
  def keys_from_command([_cmd]), do: []

  def keys_from_command([cmd | args]) do
    command = String.upcase(to_string(cmd))
    extract_keys(command, args)
  end

  @doc """
  Extracts all keys from a command. For multi-key commands,
  validates they all hash to the same slot.
  Returns `{:ok, slot}` or `{:error, :cross_slot}`.
  """
  @spec slot_for_command([String.t()]) ::
          {:ok, non_neg_integer()} | {:error, :no_key} | {:error, :cross_slot}
  def slot_for_command(command) do
    case command_slots(command) do
      [] -> {:error, :no_key}
      [single_slot] -> {:ok, single_slot}
      _ -> {:error, :cross_slot}
    end
  end

  @doc """
  Validates that all commands in a pipeline target the same slot.
  """
  @spec validate_pipeline([[String.t()]]) ::
          {:ok, non_neg_integer()}
          | {:error, :cross_slot}
          | {:error, :empty}
          | {:error, :no_key}
  def validate_pipeline([]), do: {:error, :empty}

  def validate_pipeline(commands) do
    case Enum.reduce_while(commands, MapSet.new(), &collect_command_slots/2) do
      :cross_slot ->
        {:error, :cross_slot}

      slots ->
        case MapSet.to_list(slots) do
          [] -> {:error, :no_key}
          [single_slot] -> {:ok, single_slot}
          _ -> {:error, :cross_slot}
        end
    end
  end

  defp collect_command_slots(command, acc) do
    case command_slots(command) do
      [_single_slot] = slots -> {:cont, Enum.into(slots, acc)}
      [] -> {:cont, acc}
      _multiple_slots -> {:halt, :cross_slot}
    end
  end

  defp command_slots(command) do
    command
    |> keys_from_command()
    |> Enum.map(&slot/1)
    |> Enum.uniq()
  end

  defp extract_keys(command, _args) when command in @keyless_commands, do: []
  defp extract_keys(command, args) when command in @all_args_are_keys, do: args
  defp extract_keys(command, args) when command in @two_key_commands, do: Enum.take(args, 2)

  defp extract_keys(command, args) when command in ["MSET", "MSETNX", "JSON.MSET"] do
    step = if command == "JSON.MSET", do: 3, else: 2
    args |> Enum.take_every(step)
  end

  defp extract_keys("JSON.MGET", args), do: Enum.drop(args, -1)
  defp extract_keys("BITOP", [_operation | keys]), do: keys

  defp extract_keys(command, args) when command in ["BLPOP", "BRPOP", "BZPOPMAX", "BZPOPMIN"],
    do: Enum.drop(args, -1)

  defp extract_keys(command, [script_or_function, num_keys | rest])
       when command in ["EVAL", "EVALSHA", "EVAL_RO", "EVALSHA_RO", "FCALL", "FCALL_RO"] do
    _ = script_or_function
    take_declared_keys(rest, num_keys)
  end

  defp extract_keys(command, [num_keys | rest])
       when command in [
              "LMPOP",
              "SINTERCARD",
              "ZDIFF",
              "ZINTER",
              "ZINTERCARD",
              "ZMPOP",
              "ZUNION"
            ] do
    take_declared_keys(rest, num_keys)
  end

  defp extract_keys(command, [destination, num_keys | rest])
       when command in ["ZDIFFSTORE", "ZINTERSTORE", "ZUNIONSTORE"] do
    [destination | take_declared_keys(rest, num_keys)]
  end

  defp extract_keys(command, [_timeout, num_keys | rest])
       when command in ["BLMPOP", "BZMPOP"] do
    take_declared_keys(rest, num_keys)
  end

  defp extract_keys(command, args) when command in ["XREAD", "XREADGROUP"] do
    keys_after_streams(args)
  end

  defp extract_keys("MIGRATE", [_host, _port, key, _db, _timeout | options]) do
    case Enum.find_index(options, &(String.upcase(to_string(&1)) == "KEYS")) do
      nil -> if key == "", do: [], else: [key]
      index -> Enum.drop(options, index + 1)
    end
  end

  defp extract_keys(command, [key | args]) when command in ["SORT", "SORT_RO"] do
    case option_value(args, "STORE") do
      nil -> [key]
      destination -> [key, destination]
    end
  end

  defp extract_keys(command, [key | args])
       when command in ["GEORADIUS", "GEORADIUSBYMEMBER"] do
    destinations =
      ["STORE", "STOREDIST"]
      |> Enum.map(&option_value(args, &1))
      |> Enum.reject(&is_nil/1)

    [key | destinations]
  end

  defp extract_keys("MEMORY", [subcommand | args]) do
    if String.upcase(to_string(subcommand)) == "USAGE", do: Enum.take(args, 1), else: []
  end

  defp extract_keys(command, [_subcommand, key | _])
       when command in ["OBJECT", "XGROUP", "XINFO"],
       do: [key]

  defp extract_keys(_command, [key | _]), do: [key]
  defp extract_keys(_command, []), do: []

  defp take_declared_keys(args, num_keys) do
    case Integer.parse(to_string(num_keys)) do
      {count, ""} when count >= 0 -> Enum.take(args, count)
      _ -> []
    end
  end

  defp keys_after_streams(args) do
    case Enum.find_index(args, &(String.upcase(to_string(&1)) == "STREAMS")) do
      nil ->
        []

      index ->
        stream_args = Enum.drop(args, index + 1)
        Enum.take(stream_args, div(length(stream_args), 2))
    end
  end

  defp option_value(args, option) do
    case Enum.find_index(args, &(String.upcase(to_string(&1)) == option)) do
      nil -> nil
      index -> Enum.at(args, index + 1)
    end
  end

  # -------------------------------------------------------------------
  # Hash tag extraction
  # -------------------------------------------------------------------

  defp extract_hash_tag(key) do
    case :binary.match(key, "{") do
      {start, 1} ->
        rest = binary_part(key, start + 1, byte_size(key) - start - 1)

        case :binary.match(rest, "}") do
          {end_pos, 1} when end_pos > 0 -> binary_part(rest, 0, end_pos)
          _ -> key
        end

      :nomatch ->
        key
    end
  end

  # -------------------------------------------------------------------
  # CRC16-CCITT (XMODEM) — Redis cluster hash function
  # -------------------------------------------------------------------

  defp crc16(data), do: crc16(data, 0)

  defp crc16(<<>>, crc), do: crc

  defp crc16(<<byte, rest::binary>>, crc) do
    crc = :erlang.bxor(crc, :erlang.bsl(byte, 8))

    crc =
      Enum.reduce(1..8, crc, fn _, acc ->
        if :erlang.band(acc, 0x8000) != 0 do
          :erlang.bxor(:erlang.bsl(acc, 1), 0x1021) |> :erlang.band(0xFFFF)
        else
          :erlang.bsl(acc, 1) |> :erlang.band(0xFFFF)
        end
      end)

    crc16(rest, crc)
  end
end

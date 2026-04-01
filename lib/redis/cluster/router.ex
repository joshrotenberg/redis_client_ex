defmodule Redis.Cluster.Router do
  @moduledoc """
  Hash slot router for Redis Cluster.

  Computes CRC16 hash slots and extracts keys from commands for routing.
  """

  @hash_slots 16384

  @doc "Computes the hash slot for a key."
  @spec slot(String.t()) :: non_neg_integer()
  def slot(key) do
    key = extract_hash_tag(key)
    crc16(key) |> rem(@hash_slots)
  end

  @doc """
  Extracts the first key from a Redis command for slot routing.
  Most commands have the key as the second element (index 1).
  """
  @spec key_from_command([String.t()]) :: String.t() | nil
  def key_from_command([]), do: nil
  def key_from_command([_cmd]), do: nil
  def key_from_command([_cmd, key | _]), do: key

  @doc """
  Extracts all keys from a command. For multi-key commands,
  validates they all hash to the same slot.
  Returns `{:ok, slot}` or `{:error, :cross_slot}`.
  """
  @spec slot_for_command([String.t()]) :: {:ok, non_neg_integer()} | {:error, :no_key} | {:error, :cross_slot}
  def slot_for_command(command) do
    case key_from_command(command) do
      nil -> {:error, :no_key}
      key -> {:ok, slot(key)}
    end
  end

  @doc """
  Validates that all commands in a pipeline target the same slot.
  """
  @spec validate_pipeline([[String.t()]]) :: {:ok, non_neg_integer()} | {:error, :cross_slot} | {:error, :empty}
  def validate_pipeline([]), do: {:error, :empty}

  def validate_pipeline(commands) do
    slots =
      commands
      |> Enum.map(&key_from_command/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&slot/1)
      |> Enum.uniq()

    case slots do
      [] -> {:error, :empty}
      [single_slot] -> {:ok, single_slot}
      _ -> {:error, :cross_slot}
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

defmodule Redis.Monitor.Entry do
  @moduledoc """
  A structured command received from Redis `MONITOR`.

  Redis emits monitor records in this form:

      1339518083.107412 [0 127.0.0.1:60866] "SET" "key" "value"

  `parse/1` handles Redis' quoted-string escapes, including binary bytes
  represented as `\\xNN`.
  """

  @enforce_keys [:timestamp, :database, :client, :command, :arguments, :raw]
  defstruct [:timestamp, :database, :client, :command, :arguments, :raw]

  @type t :: %__MODULE__{
          timestamp: float(),
          database: non_neg_integer(),
          client: String.t(),
          command: String.t(),
          arguments: [binary()],
          raw: binary()
        }

  @entry_pattern ~r/\A(?<timestamp>\d+(?:\.\d+)?) \[(?<database>\d+) (?<client>[^\]]+)\] (?<argv>.+)\z/

  @doc """
  Parses a raw Redis `MONITOR` record.

  Returns `{:error, :invalid_monitor_entry}` when the record is malformed.
  """
  @spec parse(binary()) :: {:ok, t()} | {:error, :invalid_monitor_entry}
  def parse(raw) when is_binary(raw) do
    with %{
           "timestamp" => timestamp,
           "database" => database,
           "client" => client,
           "argv" => argv
         } <- Regex.named_captures(@entry_pattern, raw),
         {timestamp, ""} <- Float.parse(timestamp),
         {database, ""} <- Integer.parse(database),
         {:ok, [command | arguments]} <- parse_arguments(argv) do
      {:ok,
       %__MODULE__{
         timestamp: timestamp,
         database: database,
         client: client,
         command: command,
         arguments: arguments,
         raw: raw
       }}
    else
      _ -> {:error, :invalid_monitor_entry}
    end
  end

  def parse(_raw), do: {:error, :invalid_monitor_entry}

  defp parse_arguments(data), do: parse_arguments(data, [])

  defp parse_arguments(<<>>, arguments), do: {:ok, Enum.reverse(arguments)}

  defp parse_arguments(<<" ", rest::binary>>, arguments),
    do: parse_arguments(rest, arguments)

  defp parse_arguments(<<"\"", rest::binary>>, arguments) do
    with {:ok, argument, rest} <- parse_quoted(rest, []),
         true <- rest == <<>> or :binary.first(rest) == ?\s do
      parse_arguments(rest, [argument | arguments])
    else
      _ -> {:error, :invalid_monitor_entry}
    end
  end

  defp parse_arguments(_data, _arguments), do: {:error, :invalid_monitor_entry}

  defp parse_quoted(<<"\"", rest::binary>>, bytes) do
    {:ok, bytes |> Enum.reverse() |> IO.iodata_to_binary(), rest}
  end

  defp parse_quoted(<<"\\x", high, low, rest::binary>>, bytes) do
    with {:ok, value} <- decode_hex_byte(high, low) do
      parse_quoted(rest, [value | bytes])
    end
  end

  defp parse_quoted(<<"\\", escaped, rest::binary>>, bytes) do
    case decode_escape(escaped) do
      {:ok, value} -> parse_quoted(rest, [value | bytes])
      :error -> {:error, :invalid_monitor_entry}
    end
  end

  defp parse_quoted(<<byte, rest::binary>>, bytes),
    do: parse_quoted(rest, [byte | bytes])

  defp parse_quoted(<<>>, _bytes), do: {:error, :invalid_monitor_entry}

  defp decode_hex_byte(high, low) do
    case Integer.parse(<<high, low>>, 16) do
      {value, ""} -> {:ok, value}
      _ -> :error
    end
  end

  defp decode_escape(?a), do: {:ok, 7}
  defp decode_escape(?b), do: {:ok, 8}
  defp decode_escape(?t), do: {:ok, ?\t}
  defp decode_escape(?n), do: {:ok, ?\n}
  defp decode_escape(?r), do: {:ok, ?\r}
  defp decode_escape(?"), do: {:ok, ?"}
  defp decode_escape(?\\), do: {:ok, ?\\}
  defp decode_escape(_escaped), do: :error
end

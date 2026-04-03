defmodule Redis.Protocol.RESP3 do
  @moduledoc """
  RESP3 protocol encoder and decoder.

  Pure functions — no processes, no side effects.
  Encodes commands to iodata and decodes binary wire data to Elixir terms.

  ## RESP3 Type Mapping

  | Wire prefix | RESP3 Type      | Elixir Type                     |
  |-------------|-----------------|--------------------------------|
  | `+`         | Simple string   | `String.t()`                   |
  | `$`         | Blob string     | `String.t()`                   |
  | `-`         | Simple error    | `%Redis.Error{}`             |
  | `!`         | Blob error      | `%Redis.Error{}`             |
  | `:`         | Number          | `integer()`                    |
  | `,`         | Double          | `float()`                      |
  | `#`         | Boolean         | `boolean()`                    |
  | `_`         | Null            | `nil`                          |
  | `*`         | Array           | `list()`                       |
  | `%`         | Map             | `map()`                        |
  | `~`         | Set             | `MapSet.t()`                   |
  | `>`         | Push            | `{:push, list()}`              |
  | `=`         | Verbatim string | `{:verbatim, enc, String.t()}` |
  | `(`         | Big number      | `integer()`                    |
  """

  @crlf "\r\n"

  # -------------------------------------------------------------------
  # Encoding
  # -------------------------------------------------------------------

  @doc """
  Encodes a command (list of strings/binaries) into RESP3 wire format.
  Returns iodata for efficient socket writing.

      iex> Redis.Protocol.RESP3.encode(["SET", "key", "value"]) |> IO.iodata_to_binary()
      "*3\\r\\n$3\\r\\nSET\\r\\n$3\\r\\nkey\\r\\n$5\\r\\nvalue\\r\\n"
  """
  @spec encode([binary()]) :: iodata()
  def encode(args) when is_list(args) do
    count = length(args)
    [?*, Integer.to_string(count), @crlf | encode_args(args)]
  end

  @doc """
  Encodes multiple commands for pipelining. Returns iodata.
  """
  @spec encode_pipeline([[binary()]]) :: iodata()
  def encode_pipeline(commands) when is_list(commands) do
    Enum.map(commands, &encode/1)
  end

  defp encode_args([]), do: []

  defp encode_args([arg | rest]) do
    arg = to_string(arg)
    [?$, Integer.to_string(byte_size(arg)), @crlf, arg, @crlf | encode_args(rest)]
  end

  # -------------------------------------------------------------------
  # Decoding
  # -------------------------------------------------------------------

  @doc """
  Decodes a RESP3 response from binary data.
  Returns `{:ok, term, rest}` or `{:continuation, fun}` if more data is needed.
  """
  @spec decode(binary()) :: {:ok, term(), binary()} | {:continuation, (binary() -> term())}
  def decode(<<>>), do: {:continuation, &decode/1}
  def decode(data), do: decode_type(data)

  # Null, boolean — fixed-size, check first
  defp decode_type(<<"_\r\n", rest::binary>>), do: {:ok, nil, rest}
  defp decode_type(<<"#t\r\n", rest::binary>>), do: {:ok, true, rest}
  defp decode_type(<<"#f\r\n", rest::binary>>), do: {:ok, false, rest}

  # Simple string — fast path for common responses
  defp decode_type(<<"+OK\r\n", rest::binary>>), do: {:ok, "OK", rest}
  defp decode_type(<<"+PONG\r\n", rest::binary>>), do: {:ok, "PONG", rest}
  defp decode_type(<<"+QUEUED\r\n", rest::binary>>), do: {:ok, "QUEUED", rest}
  defp decode_type(<<"+", rest::binary>>), do: decode_simple_string(rest)

  # Simple error
  defp decode_type(<<"-", rest::binary>>), do: decode_simple_error(rest)

  # Number — fast path for common small integers
  defp decode_type(<<":0\r\n", rest::binary>>), do: {:ok, 0, rest}
  defp decode_type(<<":1\r\n", rest::binary>>), do: {:ok, 1, rest}
  defp decode_type(<<":-1\r\n", rest::binary>>), do: {:ok, -1, rest}
  defp decode_type(<<":", rest::binary>>), do: decode_number(rest)

  # Blob string
  defp decode_type(<<"$", rest::binary>>), do: decode_blob_string(rest)

  # Array
  defp decode_type(<<"*", rest::binary>>), do: decode_array(rest)

  # Double
  defp decode_type(<<",", rest::binary>>), do: decode_double(rest)

  # Big number: (3492890328409238509324850943850943825024385\r\n
  defp decode_type(<<"(", rest::binary>>), do: decode_big_number(rest)

  # Blob error: !<len>\r\n<data>\r\n
  defp decode_type(<<"!", rest::binary>>), do: decode_blob_error(rest)

  # Verbatim string: =<len>\r\n<enc>:<data>\r\n
  defp decode_type(<<"=", rest::binary>>), do: decode_verbatim_string(rest)

  # Map: %<count>\r\n...
  defp decode_type(<<"%", rest::binary>>), do: decode_map(rest)

  # Set: ~<count>\r\n...
  defp decode_type(<<"~", rest::binary>>), do: decode_set(rest)

  # Push: ><count>\r\n...
  defp decode_type(<<">", rest::binary>>), do: decode_push(rest)

  # Need more data
  defp decode_type(_data), do: {:continuation, &decode/1}

  # --- Simple string ---

  defp decode_simple_string(data) do
    case :binary.match(data, "\r\n") do
      {pos, 2} ->
        str = binary_part(data, 0, pos)
        rest = binary_part(data, pos + 2, byte_size(data) - pos - 2)
        {:ok, str, rest}

      :nomatch ->
        {:continuation, &decode/1}
    end
  end

  # --- Simple error ---

  defp decode_simple_error(data) do
    case :binary.match(data, "\r\n") do
      {pos, 2} ->
        msg = binary_part(data, 0, pos)
        rest = binary_part(data, pos + 2, byte_size(data) - pos - 2)
        {:ok, %Redis.Error{message: msg}, rest}

      :nomatch ->
        {:continuation, &decode/1}
    end
  end

  # --- Number ---

  defp decode_number(data) do
    case :binary.match(data, "\r\n") do
      {pos, 2} ->
        num_str = binary_part(data, 0, pos)
        rest = binary_part(data, pos + 2, byte_size(data) - pos - 2)

        case safe_to_integer(num_str) do
          {:ok, n} -> {:ok, n, rest}
          :error -> {:continuation, &decode/1}
        end

      :nomatch ->
        {:continuation, &decode/1}
    end
  end

  # --- Double ---

  defp decode_double(data) do
    case :binary.match(data, "\r\n") do
      {pos, 2} ->
        str = binary_part(data, 0, pos)
        rest = binary_part(data, pos + 2, byte_size(data) - pos - 2)

        case str do
          "inf" -> {:ok, :infinity, rest}
          "-inf" -> {:ok, :neg_infinity, rest}
          _ -> {:ok, parse_double(str), rest}
        end

      :nomatch ->
        {:continuation, &decode/1}
    end
  end

  defp parse_double("nan" <> _), do: :nan
  defp parse_double("inf"), do: :inf
  defp parse_double("-inf"), do: :neg_inf

  defp parse_double(str) do
    case Float.parse(str) do
      {f, ""} -> f
      _ -> String.to_float(str <> ".0")
    end
  end

  # --- Big number ---

  defp decode_big_number(data) do
    case :binary.match(data, "\r\n") do
      {pos, 2} ->
        num_str = binary_part(data, 0, pos)
        rest = binary_part(data, pos + 2, byte_size(data) - pos - 2)

        case safe_to_integer(num_str) do
          {:ok, n} -> {:ok, n, rest}
          :error -> {:continuation, &decode/1}
        end

      :nomatch ->
        {:continuation, &decode/1}

      [_] ->
        {:continuation, &decode/1}
    end
  end

  # --- Blob string ---

  defp decode_blob_string(<<"-1\r\n", rest::binary>>), do: {:ok, nil, rest}

  defp decode_blob_string(data) do
    case :binary.match(data, "\r\n") do
      {pos, 2} ->
        len_str = binary_part(data, 0, pos)
        rest = binary_part(data, pos + 2, byte_size(data) - pos - 2)
        decode_blob_body(len_str, rest, &{:ok, &1, &2})

      :nomatch ->
        {:continuation, &decode/1}
    end
  end

  # --- Blob error ---

  defp decode_blob_error(data) do
    case :binary.match(data, "\r\n") do
      {pos, 2} ->
        len_str = binary_part(data, 0, pos)
        rest = binary_part(data, pos + 2, byte_size(data) - pos - 2)
        decode_blob_body(len_str, rest, &{:ok, %Redis.Error{message: &1}, &2})

      :nomatch ->
        {:continuation, &decode/1}
    end
  end

  # --- Verbatim string ---

  defp decode_verbatim_string(data) do
    case :binary.match(data, "\r\n") do
      {pos, 2} ->
        len_str = binary_part(data, 0, pos)
        rest = binary_part(data, pos + 2, byte_size(data) - pos - 2)

        decode_blob_body(len_str, rest, fn blob, rest2 ->
          <<enc::binary-size(3), ":", content::binary>> = blob
          {:ok, {:verbatim, enc, content}, rest2}
        end)

      :nomatch ->
        {:continuation, &decode/1}
    end
  end

  # --- Array ---

  defp decode_array(<<"-1\r\n", rest::binary>>), do: {:ok, nil, rest}

  defp decode_array(data) do
    case decode_counted(data) do
      {:ok, count, rest} -> decode_elements(rest, count, [])
      :continuation -> {:continuation, &decode/1}
    end
  end

  # --- Map ---

  defp decode_map(data) do
    case decode_counted(data) do
      {:ok, count, rest} -> decode_map_pairs(rest, count, %{})
      :continuation -> {:continuation, &decode/1}
    end
  end

  # --- Set ---

  defp decode_set(data) do
    case decode_counted(data) do
      {:ok, count, rest} ->
        case decode_elements(rest, count, []) do
          {:ok, elements, rest2} -> {:ok, MapSet.new(elements), rest2}
          other -> other
        end

      :continuation ->
        {:continuation, &decode/1}
    end
  end

  # --- Push ---

  defp decode_push(data) do
    case decode_counted(data) do
      {:ok, count, rest} ->
        case decode_elements(rest, count, []) do
          {:ok, elements, rest2} -> {:ok, {:push, elements}, rest2}
          other -> other
        end

      :continuation ->
        {:continuation, &decode/1}
    end
  end

  # --- Aggregate helpers ---

  defp decode_elements(rest, 0, acc), do: {:ok, Enum.reverse(acc), rest}

  defp decode_elements(data, count, acc) do
    case decode_type(data) do
      {:ok, element, rest} -> decode_elements(rest, count - 1, [element | acc])
      {:continuation, _} -> {:continuation, &decode/1}
    end
  end

  defp decode_map_pairs(rest, 0, acc), do: {:ok, acc, rest}

  defp decode_map_pairs(data, count, acc) do
    with {:ok, key, rest1} <- decode_type(data),
         {:ok, value, rest2} <- decode_type(rest1) do
      decode_map_pairs(rest2, count - 1, Map.put(acc, key, value))
    else
      {:continuation, _} -> {:continuation, &decode/1}
    end
  end

  # Shared helper: parse a length-prefixed blob and apply a callback
  defp decode_blob_body(len_str, rest, callback) do
    case safe_to_integer(len_str) do
      {:ok, len} ->
        case rest do
          <<blob::binary-size(len), "\r\n", rest2::binary>> -> callback.(blob, rest2)
          _ -> {:continuation, &decode/1}
        end

      :error ->
        {:continuation, &decode/1}
    end
  end

  # Shared helper: find CRLF and parse the count as integer
  defp decode_counted(data) do
    case :binary.match(data, "\r\n") do
      {pos, 2} ->
        count_str = binary_part(data, 0, pos)
        rest = binary_part(data, pos + 2, byte_size(data) - pos - 2)

        case safe_to_integer(count_str) do
          {:ok, count} -> {:ok, count, rest}
          :error -> :continuation
        end

      :nomatch ->
        :continuation
    end
  end

  defp safe_to_integer(""), do: :error

  defp safe_to_integer(str) do
    case Integer.parse(str) do
      {n, ""} -> {:ok, n}
      _ -> :error
    end
  end
end

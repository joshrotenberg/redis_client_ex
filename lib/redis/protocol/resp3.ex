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

  # Simple string: +OK\r\n
  defp decode_type(<<"+", rest::binary>>), do: decode_simple_string(rest)

  # Simple error: -ERR message\r\n
  defp decode_type(<<"-", rest::binary>>), do: decode_simple_error(rest)

  # Number: :42\r\n
  defp decode_type(<<":", rest::binary>>), do: decode_number(rest)

  # Blob string: $5\r\nhello\r\n
  defp decode_type(<<"$", rest::binary>>), do: decode_blob_string(rest)

  # Array: *3\r\n...
  defp decode_type(<<"*", rest::binary>>), do: decode_array(rest)

  # Null: _\r\n
  defp decode_type(<<"_\r\n", rest::binary>>), do: {:ok, nil, rest}

  # Boolean: #t\r\n or #f\r\n
  defp decode_type(<<"#t\r\n", rest::binary>>), do: {:ok, true, rest}
  defp decode_type(<<"#f\r\n", rest::binary>>), do: {:ok, false, rest}

  # Double: ,1.5\r\n
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
    case :binary.split(data, @crlf) do
      [str, rest] -> {:ok, str, rest}
      [_] -> {:continuation, &decode/1}
    end
  end

  # --- Simple error ---

  defp decode_simple_error(data) do
    case :binary.split(data, @crlf) do
      [msg, rest] -> {:ok, %Redis.Error{message: msg}, rest}
      [_] -> {:continuation, &decode/1}
    end
  end

  # --- Number ---

  defp decode_number(data) do
    case :binary.split(data, @crlf) do
      [num_str, rest] -> {:ok, String.to_integer(num_str), rest}
      [_] -> {:continuation, &decode/1}
    end
  end

  # --- Double ---

  defp decode_double(data) do
    case :binary.split(data, @crlf) do
      ["inf", rest] -> {:ok, :infinity, rest}
      ["-inf", rest] -> {:ok, :neg_infinity, rest}
      [str, rest] -> {:ok, parse_double(str), rest}
      [_] -> {:continuation, &decode/1}
    end
  end

  defp parse_double(str) do
    case Float.parse(str) do
      {f, ""} -> f
      _ -> String.to_float(str <> ".0")
    end
  end

  # --- Big number ---

  defp decode_big_number(data) do
    case :binary.split(data, @crlf) do
      [num_str, rest] -> {:ok, String.to_integer(num_str), rest}
      [_] -> {:continuation, &decode/1}
    end
  end

  # --- Blob string ---

  defp decode_blob_string(data) do
    case :binary.split(data, @crlf) do
      ["-1", rest] ->
        {:ok, nil, rest}

      [len_str, rest] ->
        len = String.to_integer(len_str)

        case rest do
          <<blob::binary-size(len), "\r\n", rest2::binary>> ->
            {:ok, blob, rest2}

          _ ->
            {:continuation, &decode/1}
        end

      [_] ->
        {:continuation, &decode/1}
    end
  end

  # --- Blob error ---

  defp decode_blob_error(data) do
    case :binary.split(data, @crlf) do
      [len_str, rest] ->
        len = String.to_integer(len_str)

        case rest do
          <<blob::binary-size(len), "\r\n", rest2::binary>> ->
            {:ok, %Redis.Error{message: blob}, rest2}

          _ ->
            {:continuation, &decode/1}
        end

      [_] ->
        {:continuation, &decode/1}
    end
  end

  # --- Verbatim string ---

  defp decode_verbatim_string(data) do
    case :binary.split(data, @crlf) do
      [len_str, rest] ->
        len = String.to_integer(len_str)

        case rest do
          <<blob::binary-size(len), "\r\n", rest2::binary>> ->
            <<enc::binary-size(3), ":", content::binary>> = blob
            {:ok, {:verbatim, enc, content}, rest2}

          _ ->
            {:continuation, &decode/1}
        end

      [_] ->
        {:continuation, &decode/1}
    end
  end

  # --- Array ---

  defp decode_array(data) do
    case :binary.split(data, @crlf) do
      ["-1", rest] ->
        {:ok, nil, rest}

      [count_str, rest] ->
        count = String.to_integer(count_str)
        decode_elements(rest, count, [])

      [_] ->
        {:continuation, &decode/1}
    end
  end

  # --- Map ---

  defp decode_map(data) do
    case :binary.split(data, @crlf) do
      [count_str, rest] ->
        count = String.to_integer(count_str)
        decode_map_pairs(rest, count, %{})

      [_] ->
        {:continuation, &decode/1}
    end
  end

  # --- Set ---

  defp decode_set(data) do
    case :binary.split(data, @crlf) do
      [count_str, rest] ->
        count = String.to_integer(count_str)

        case decode_elements(rest, count, []) do
          {:ok, elements, rest2} -> {:ok, MapSet.new(elements), rest2}
          other -> other
        end

      [_] ->
        {:continuation, &decode/1}
    end
  end

  # --- Push ---

  defp decode_push(data) do
    case :binary.split(data, @crlf) do
      [count_str, rest] ->
        count = String.to_integer(count_str)

        case decode_elements(rest, count, []) do
          {:ok, elements, rest2} -> {:ok, {:push, elements}, rest2}
          other -> other
        end

      [_] ->
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
end

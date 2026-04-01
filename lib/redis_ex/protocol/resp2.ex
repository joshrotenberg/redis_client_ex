defmodule RedisEx.Protocol.RESP2 do
  @moduledoc """
  RESP2 protocol encoder and decoder (fallback for older Redis servers).

  RESP2 uses the same array/bulk-string encoding for commands but has fewer
  response types than RESP3: simple strings, errors, integers, bulk strings,
  and arrays.
  """

  @crlf "\r\n"

  # Encoding is identical to RESP3 (commands always use array of bulk strings)
  defdelegate encode(args), to: RedisEx.Protocol.RESP3
  defdelegate encode_pipeline(commands), to: RedisEx.Protocol.RESP3

  # -------------------------------------------------------------------
  # Decoding
  # -------------------------------------------------------------------

  @doc """
  Decodes a RESP2 response from binary data.
  Returns `{:ok, term, rest}` or `{:continuation, fun}` if more data is needed.
  """
  @spec decode(binary()) :: {:ok, term(), binary()} | {:continuation, (binary() -> term())}
  def decode(<<>>), do: {:continuation, &decode/1}
  def decode(data), do: decode_type(data)

  defp decode_type(<<"+", rest::binary>>), do: decode_line(rest, :string)
  defp decode_type(<<"-", rest::binary>>), do: decode_line(rest, :error)
  defp decode_type(<<":", rest::binary>>), do: decode_line(rest, :integer)
  defp decode_type(<<"$", rest::binary>>), do: decode_bulk_string(rest)
  defp decode_type(<<"*", rest::binary>>), do: decode_array(rest)
  defp decode_type(_data), do: {:continuation, &decode/1}

  defp decode_line(data, type) do
    case :binary.split(data, @crlf) do
      [value, rest] ->
        decoded =
          case type do
            :string -> value
            :error -> %RedisEx.Error{message: value}
            :integer -> String.to_integer(value)
          end

        {:ok, decoded, rest}

      [_] ->
        {:continuation, &decode/1}
    end
  end

  defp decode_bulk_string(data) do
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

  defp decode_elements(rest, 0, acc), do: {:ok, Enum.reverse(acc), rest}

  defp decode_elements(data, count, acc) do
    case decode_type(data) do
      {:ok, element, rest} -> decode_elements(rest, count - 1, [element | acc])
      {:continuation, _} -> {:continuation, &decode/1}
    end
  end
end

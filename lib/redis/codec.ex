defmodule Redis.Codec do
  @moduledoc """
  Behaviour for custom value encoding/decoding.

  A codec transforms values before they are sent to Redis and after they are
  received. This lets you transparently store structured data (JSON, Erlang
  terms, etc.) while keeping the Redis commands unchanged.

  ## Built-in codecs

    * `Redis.Codec.Raw` -- passthrough, no transformation (default)
    * `Redis.Codec.JSON` -- JSON via Jason (requires `:jason` dependency)
    * `Redis.Codec.Term` -- Erlang external term format with safe decoding

  ## Usage

  Codecs are not wired into the connection automatically. Instead, use the
  helper functions `encode_value/2` and `decode_result/2` to transform values
  at the call site:

      codec = Redis.Codec.JSON

      {:ok, encoded} = Redis.Codec.encode_value(codec, %{name: "Alice"})
      {:ok, "OK"} = Redis.command(conn, ["SET", "user:1", encoded])

      {:ok, raw} = Redis.command(conn, ["GET", "user:1"])
      {:ok, %{"name" => "Alice"}} = Redis.Codec.decode_result(codec, raw)

  ## Implementing a custom codec

      defmodule MyApp.MsgpackCodec do
        @behaviour Redis.Codec

        @impl true
        def encode(term), do: {:ok, Msgpax.pack!(term, iodata: false)}

        @impl true
        def decode(binary), do: {:ok, Msgpax.unpack!(binary)}

        @impl true
        def content_type, do: "application/msgpack"
      end
  """

  @doc "Encode a term into a binary suitable for storage in Redis."
  @callback encode(term()) :: {:ok, binary()} | {:error, term()}

  @doc "Decode a binary retrieved from Redis back into a term."
  @callback decode(binary()) :: {:ok, term()} | {:error, term()}

  @doc "Returns the MIME content type for this codec (e.g. \"application/json\")."
  @callback content_type() :: String.t()

  @doc """
  Encode a value using the given codec module.

  Returns `{:ok, binary}` on success or `{:error, reason}` on failure.
  """
  @spec encode_value(module(), term()) :: {:ok, binary()} | {:error, term()}
  def encode_value(codec, value) do
    codec.encode(value)
  end

  @doc """
  Decode a result using the given codec module.

  Passes `nil` through unchanged (for missing keys). Non-binary values are
  returned as-is, since they cannot be decoded.
  """
  @spec decode_result(module(), term()) :: {:ok, term()} | {:error, term()}
  def decode_result(_codec, nil), do: {:ok, nil}

  def decode_result(codec, value) when is_binary(value) do
    codec.decode(value)
  end

  def decode_result(_codec, value), do: {:ok, value}

  @doc """
  Decode a list of results using the given codec module.

  Useful for decoding pipeline or MGET results.
  """
  @spec decode_results(module(), [term()]) :: {:ok, [term()]} | {:error, term()}
  def decode_results(codec, results) when is_list(results) do
    results
    |> Enum.reduce_while([], fn value, acc ->
      case decode_result(codec, value) do
        {:ok, decoded} -> {:cont, [decoded | acc]}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:error, _} = err -> err
      acc -> {:ok, Enum.reverse(acc)}
    end
  end
end

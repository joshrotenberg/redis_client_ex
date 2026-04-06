if Code.ensure_loaded?(Jason) do
  defmodule Redis.Codec.JSON do
    @moduledoc """
    JSON codec using Jason.

    Encodes terms to JSON strings before storing in Redis and decodes JSON
    strings back to Elixir terms on retrieval. Requires the `:jason` optional
    dependency.
    """

    @behaviour Redis.Codec

    @impl true
    def encode(term) do
      case Jason.encode(term) do
        {:ok, json} -> {:ok, json}
        {:error, reason} -> {:error, {:json_encode_error, reason}}
      end
    end

    @impl true
    def decode(binary) when is_binary(binary) do
      case Jason.decode(binary) do
        {:ok, term} -> {:ok, term}
        {:error, reason} -> {:error, {:json_decode_error, reason}}
      end
    end

    def decode(other), do: {:ok, other}

    @impl true
    def content_type, do: "application/json"
  end
end

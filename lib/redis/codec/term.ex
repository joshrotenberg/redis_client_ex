defmodule Redis.Codec.Term do
  @moduledoc """
  Erlang external term format codec.

  Encodes terms with `:erlang.term_to_binary/1` and decodes with
  `:erlang.binary_to_term/2` using the `:safe` option to prevent atom
  creation from untrusted data.
  """

  @behaviour Redis.Codec

  @impl true
  def encode(term) do
    {:ok, :erlang.term_to_binary(term)}
  rescue
    e -> {:error, {:term_encode_error, e}}
  end

  @impl true
  def decode(binary) when is_binary(binary) do
    {:ok, :erlang.binary_to_term(binary, [:safe])}
  rescue
    ArgumentError -> {:error, :term_decode_error}
  end

  def decode(other), do: {:ok, other}

  @impl true
  def content_type, do: "application/x-erlang-term"
end

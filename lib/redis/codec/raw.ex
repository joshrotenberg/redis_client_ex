defmodule Redis.Codec.Raw do
  @moduledoc """
  Passthrough codec that performs no transformation.

  Values are returned as-is. This is the default codec and is useful as a
  no-op placeholder when codec support is optional.
  """

  @behaviour Redis.Codec

  @impl true
  def encode(value) when is_binary(value), do: {:ok, value}
  def encode(value), do: {:ok, to_string(value)}

  @impl true
  def decode(value), do: {:ok, value}

  @impl true
  def content_type, do: "application/octet-stream"
end

defmodule Redis.Codec.RawTest do
  use ExUnit.Case, async: true

  alias Redis.Codec.Raw

  describe "encode/1" do
    test "passes through binary values unchanged" do
      assert {:ok, "hello"} = Raw.encode("hello")
    end

    test "converts non-binary values to strings" do
      assert {:ok, "42"} = Raw.encode(42)
      assert {:ok, "true"} = Raw.encode(true)
    end
  end

  describe "decode/1" do
    test "passes through values unchanged" do
      assert {:ok, "hello"} = Raw.decode("hello")
      assert {:ok, <<0, 1, 2>>} = Raw.decode(<<0, 1, 2>>)
    end
  end

  describe "content_type/0" do
    test "returns octet-stream" do
      assert "application/octet-stream" = Raw.content_type()
    end
  end
end

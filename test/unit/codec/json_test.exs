defmodule Redis.Codec.JSONTest do
  use ExUnit.Case, async: true

  alias Redis.Codec.JSON

  describe "encode/1" do
    test "encodes a map to JSON" do
      assert {:ok, json} = JSON.encode(%{name: "Alice", age: 30})
      assert is_binary(json)
      assert {:ok, %{"name" => "Alice", "age" => 30}} = Jason.decode(json)
    end

    test "encodes a list to JSON" do
      assert {:ok, json} = JSON.encode([1, 2, 3])
      assert {:ok, [1, 2, 3]} = Jason.decode(json)
    end

    test "encodes a string to JSON" do
      assert {:ok, ~s("hello")} = JSON.encode("hello")
    end

    test "returns error for unencodable values" do
      assert {:error, {:json_encode_error, _}} = JSON.encode({:tuple, "value"})
    end
  end

  describe "decode/1" do
    test "decodes a JSON string to a map" do
      json = ~s({"name":"Alice","age":30})
      assert {:ok, %{"name" => "Alice", "age" => 30}} = JSON.decode(json)
    end

    test "decodes a JSON array" do
      assert {:ok, [1, 2, 3]} = JSON.decode("[1,2,3]")
    end

    test "returns error for invalid JSON" do
      assert {:error, {:json_decode_error, _}} = JSON.decode("not json{")
    end

    test "passes through non-binary values" do
      assert {:ok, 42} = JSON.decode(42)
    end
  end

  describe "content_type/0" do
    test "returns application/json" do
      assert "application/json" = JSON.content_type()
    end
  end
end

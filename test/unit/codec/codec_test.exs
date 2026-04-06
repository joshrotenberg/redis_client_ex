defmodule Redis.CodecTest do
  use ExUnit.Case, async: true

  alias Redis.Codec

  describe "encode_value/2" do
    test "delegates to the codec module" do
      assert {:ok, json} = Codec.encode_value(Codec.JSON, %{a: 1})
      assert {:ok, %{"a" => 1}} = Jason.decode(json)
    end
  end

  describe "decode_result/2" do
    test "passes nil through unchanged" do
      assert {:ok, nil} = Codec.decode_result(Codec.JSON, nil)
    end

    test "decodes binary values" do
      assert {:ok, %{"a" => 1}} = Codec.decode_result(Codec.JSON, ~s({"a":1}))
    end

    test "passes non-binary values through" do
      assert {:ok, 42} = Codec.decode_result(Codec.JSON, 42)
    end
  end

  describe "decode_results/2" do
    test "decodes a list of results" do
      results = [~s({"a":1}), ~s({"b":2}), nil]
      assert {:ok, [%{"a" => 1}, %{"b" => 2}, nil]} = Codec.decode_results(Codec.JSON, results)
    end

    test "returns error if any decode fails" do
      results = [~s({"a":1}), "not json{"]
      assert {:error, {:json_decode_error, _}} = Codec.decode_results(Codec.JSON, results)
    end

    test "works with raw codec" do
      results = ["hello", "world"]
      assert {:ok, ["hello", "world"]} = Codec.decode_results(Codec.Raw, results)
    end
  end
end

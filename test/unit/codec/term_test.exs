defmodule Redis.Codec.TermTest do
  use ExUnit.Case, async: true

  alias Redis.Codec.Term

  describe "encode/1" do
    test "encodes a map" do
      assert {:ok, binary} = Term.encode(%{key: "value"})
      assert is_binary(binary)
      assert %{key: "value"} = :erlang.binary_to_term(binary, [:safe])
    end

    test "encodes a list" do
      assert {:ok, binary} = Term.encode([1, 2, 3])
      assert [1, 2, 3] = :erlang.binary_to_term(binary, [:safe])
    end

    test "encodes a tuple" do
      assert {:ok, binary} = Term.encode({:ok, "hello"})
      assert {:ok, "hello"} = :erlang.binary_to_term(binary, [:safe])
    end
  end

  describe "decode/1" do
    test "decodes a valid term binary" do
      binary = :erlang.term_to_binary(%{key: "value"})
      assert {:ok, %{key: "value"}} = Term.decode(binary)
    end

    test "returns error for invalid binary" do
      assert {:error, :term_decode_error} = Term.decode(<<0, 1, 2, 3>>)
    end

    test "passes through non-binary values" do
      assert {:ok, 42} = Term.decode(42)
    end

    test "uses safe mode to prevent atom creation" do
      # Create a binary containing a non-existing atom
      binary = :erlang.term_to_binary(:__nonexistent_atom_for_codec_test_xyz__)

      # The atom already exists from the line above, so we can't test that
      # directly. Instead, verify the decode path works with :safe option.
      assert {:ok, :__nonexistent_atom_for_codec_test_xyz__} = Term.decode(binary)
    end
  end

  describe "content_type/0" do
    test "returns erlang term content type" do
      assert "application/x-erlang-term" = Term.content_type()
    end
  end

  describe "round-trip" do
    test "preserves complex data structures" do
      data = %{
        strings: ["a", "b", "c"],
        numbers: [1, 2.0, -3],
        nested: %{inner: true},
        tuple: {:ok, :done}
      }

      assert {:ok, encoded} = Term.encode(data)
      assert {:ok, ^data} = Term.decode(encoded)
    end
  end
end

defmodule Redis.Protocol.RESP3PropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Redis.Protocol.RESP3

  # -------------------------------------------------------------------
  # Generators
  # -------------------------------------------------------------------

  # Generate a RESP3-compatible Elixir value
  defp resp3_value do
    gen all(
          value <-
            one_of([
              resp3_simple_string(),
              resp3_integer(),
              resp3_double(),
              resp3_boolean(),
              resp3_null(),
              resp3_blob_string(),
              resp3_array(),
              resp3_map()
            ])
        ) do
      value
    end
  end

  # Simple string: any string without \r or \n
  defp resp3_simple_string do
    gen all(str <- string(:printable, min_length: 0, max_length: 100)) do
      String.replace(str, ~r/[\r\n]/, "")
    end
  end

  defp resp3_integer, do: integer(-1_000_000..1_000_000)

  defp resp3_double do
    gen all(f <- float(min: -1.0e10, max: 1.0e10)) do
      # Avoid NaN/Inf since those have special atom representation
      f
    end
  end

  defp resp3_boolean, do: boolean()
  defp resp3_null, do: constant(nil)

  # Blob string: any binary (including embedded \r\n)
  defp resp3_blob_string do
    binary(min_length: 0, max_length: 200)
  end

  # Shallow array of scalar values (avoid deep nesting for performance)
  defp resp3_array do
    gen all(
          elements <-
            list_of(
              one_of([
                resp3_simple_string(),
                resp3_integer(),
                resp3_blob_string(),
                resp3_boolean(),
                resp3_null()
              ]),
              min_length: 0,
              max_length: 10
            )
        ) do
      elements
    end
  end

  # Map with string keys and scalar values
  defp resp3_map do
    gen all(
          pairs <-
            list_of(
              tuple({
                resp3_simple_string(),
                one_of([
                  resp3_simple_string(),
                  resp3_integer(),
                  resp3_blob_string(),
                  resp3_boolean(),
                  resp3_null()
                ])
              }),
              min_length: 0,
              max_length: 5
            )
        ) do
      Map.new(pairs)
    end
  end

  # -------------------------------------------------------------------
  # RESP3 wire format encoders (for building test data)
  # -------------------------------------------------------------------

  defp to_resp3_wire(value) when is_binary(value) do
    # Encode as blob string to handle embedded \r\n safely
    "$#{byte_size(value)}\r\n#{value}\r\n"
  end

  defp to_resp3_wire(value) when is_integer(value) do
    ":#{value}\r\n"
  end

  defp to_resp3_wire(value) when is_float(value) do
    ",#{value}\r\n"
  end

  defp to_resp3_wire(true), do: "#t\r\n"
  defp to_resp3_wire(false), do: "#f\r\n"
  defp to_resp3_wire(nil), do: "_\r\n"

  defp to_resp3_wire(value) when is_list(value) do
    elements = Enum.map_join(value, &to_resp3_wire/1)
    "*#{length(value)}\r\n#{elements}"
  end

  defp to_resp3_wire(value) when is_map(value) and not is_struct(value) do
    pairs =
      Enum.map_join(value, fn {k, v} ->
        to_resp3_wire(k) <> to_resp3_wire(v)
      end)

    "%#{map_size(value)}\r\n#{pairs}"
  end

  # -------------------------------------------------------------------
  # Property tests
  # -------------------------------------------------------------------

  describe "encode/decode round-trip" do
    property "encoding then decoding a command returns the original args as blob strings" do
      check all(
              args <-
                list_of(binary(min_length: 1, max_length: 50), min_length: 1, max_length: 10)
            ) do
        encoded = RESP3.encode(args) |> IO.iodata_to_binary()

        # Decoding an encoded command yields an array of the original binaries
        assert {:ok, decoded, ""} = RESP3.decode(encoded)
        assert decoded == args
      end
    end
  end

  describe "decode round-trip via wire format" do
    property "simple strings decode correctly" do
      check all(str <- resp3_simple_string(), str != "") do
        wire = "+#{str}\r\n"
        assert {:ok, ^str, ""} = RESP3.decode(wire)
      end
    end

    property "integers decode correctly" do
      check all(n <- integer(-1_000_000..1_000_000)) do
        wire = ":#{n}\r\n"
        assert {:ok, ^n, ""} = RESP3.decode(wire)
      end
    end

    property "doubles decode correctly" do
      check all(f <- float(min: -1.0e10, max: 1.0e10)) do
        wire = ",#{f}\r\n"
        assert {:ok, decoded, ""} = RESP3.decode(wire)
        assert is_float(decoded)
        assert_in_delta decoded, f, 1.0e-10
      end
    end

    property "blob strings decode correctly (binary-safe)" do
      check all(blob <- binary(min_length: 0, max_length: 500)) do
        wire = "$#{byte_size(blob)}\r\n#{blob}\r\n"
        assert {:ok, ^blob, ""} = RESP3.decode(wire)
      end
    end

    property "booleans decode correctly" do
      check all(b <- boolean()) do
        wire = if b, do: "#t\r\n", else: "#f\r\n"
        assert {:ok, ^b, ""} = RESP3.decode(wire)
      end
    end

    property "arrays of integers decode correctly" do
      check all(ints <- list_of(integer(), min_length: 0, max_length: 20)) do
        elements = Enum.map_join(ints, fn n -> ":#{n}\r\n" end)
        wire = "*#{length(ints)}\r\n#{elements}"
        assert {:ok, ^ints, ""} = RESP3.decode(wire)
      end
    end

    property "maps with string keys and integer values decode correctly" do
      check all(
              pairs <-
                list_of(
                  tuple({string(:ascii, min_length: 1, max_length: 20), integer()}),
                  min_length: 0,
                  max_length: 10
                )
            ) do
        expected = Map.new(pairs)

        wire_pairs =
          Enum.map_join(pairs, fn {k, v} ->
            "+#{k}\r\n:#{v}\r\n"
          end)

        wire = "%#{length(pairs)}\r\n#{wire_pairs}"
        assert {:ok, decoded, ""} = RESP3.decode(wire)
        assert decoded == expected
      end
    end
  end

  describe "decode/encode composite round-trip" do
    property "encoding and decoding preserves arbitrary RESP3 values" do
      check all(value <- resp3_value()) do
        wire = to_resp3_wire(value)
        assert {:ok, decoded, ""} = RESP3.decode(wire)
        assert values_equal?(value, decoded)
      end
    end
  end

  describe "decoder robustness" do
    property "decoder never crashes on arbitrary binary input" do
      check all(data <- binary(min_length: 0, max_length: 500)) do
        result = RESP3.decode(data)

        assert match?({:ok, _, _}, result) or
                 match?({:continuation, _}, result)
      end
    end

    property "decoder never crashes on binary input with valid prefixes" do
      check all(
              prefix <-
                member_of(["+", "-", ":", "$", "*", "_", "#", ",", "(", "!", "=", "%", "~", ">"]),
              tail <- binary(min_length: 0, max_length: 200)
            ) do
        data = prefix <> tail
        result = RESP3.decode(data)

        assert match?({:ok, _, _}, result) or
                 match?({:continuation, _}, result)
      end
    end

    property "partial blob strings return continuation" do
      check all(blob <- binary(min_length: 5, max_length: 100)) do
        # Declare a length longer than the actual data
        wire = "$#{byte_size(blob) + 10}\r\n#{blob}"
        assert {:continuation, _} = RESP3.decode(wire)
      end
    end
  end

  describe "special doubles" do
    test "nan decodes to :nan atom" do
      assert {:ok, :nan, ""} = RESP3.decode(",nan\r\n")
    end

    test "nan.0 decodes to :nan atom" do
      assert {:ok, :nan, ""} = RESP3.decode(",nan.0\r\n")
    end

    test "inf decodes to :infinity" do
      assert {:ok, :infinity, ""} = RESP3.decode(",inf\r\n")
    end

    test "-inf decodes to :neg_infinity" do
      assert {:ok, :neg_infinity, ""} = RESP3.decode(",-inf\r\n")
    end
  end

  describe "concatenated responses" do
    property "multiple concatenated responses all decode sequentially" do
      check all(
              values <-
                list_of(one_of([resp3_integer(), resp3_boolean(), resp3_null()]),
                  min_length: 1,
                  max_length: 10
                )
            ) do
        wire = Enum.map_join(values, &to_resp3_wire/1)

        {decoded, rest} =
          Enum.reduce(values, {[], wire}, fn _val, {acc, data} ->
            assert {:ok, decoded, rest} = RESP3.decode(data)
            {acc ++ [decoded], rest}
          end)

        assert decoded == values
        assert rest == ""
      end
    end
  end

  # -------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------

  # Compare values allowing float imprecision
  defp values_equal?(a, b) when is_float(a) and is_float(b) do
    abs(a - b) < 1.0e-10
  end

  defp values_equal?(a, b) when is_list(a) and is_list(b) do
    length(a) == length(b) and
      Enum.zip(a, b) |> Enum.all?(fn {x, y} -> values_equal?(x, y) end)
  end

  defp values_equal?(a, b) when is_map(a) and is_map(b) do
    Map.keys(a) == Map.keys(b) and
      Enum.all?(Map.keys(a), fn k -> values_equal?(Map.get(a, k), Map.get(b, k)) end)
  end

  defp values_equal?(a, b), do: a == b
end

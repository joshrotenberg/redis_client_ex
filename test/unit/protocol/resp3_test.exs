defmodule Redis.Protocol.RESP3Test do
  use ExUnit.Case, async: true

  alias Redis.Protocol.RESP3

  describe "encode/1" do
    test "encodes a simple command" do
      assert RESP3.encode(["PING"]) |> IO.iodata_to_binary() ==
               "*1\r\n$4\r\nPING\r\n"
    end

    test "encodes a command with arguments" do
      assert RESP3.encode(["SET", "key", "value"]) |> IO.iodata_to_binary() ==
               "*3\r\n$3\r\nSET\r\n$3\r\nkey\r\n$5\r\nvalue\r\n"
    end

    test "encodes binary-safe arguments" do
      assert RESP3.encode(["SET", "key", "hello\r\nworld"]) |> IO.iodata_to_binary() ==
               "*3\r\n$3\r\nSET\r\n$3\r\nkey\r\n$12\r\nhello\r\nworld\r\n"
    end
  end

  describe "encode_pipeline/1" do
    test "encodes multiple commands" do
      commands = [["SET", "a", "1"], ["GET", "a"]]
      encoded = RESP3.encode_pipeline(commands) |> IO.iodata_to_binary()
      assert encoded == "*3\r\n$3\r\nSET\r\n$1\r\na\r\n$1\r\n1\r\n*2\r\n$3\r\nGET\r\n$1\r\na\r\n"
    end
  end

  describe "decode/1 - simple types" do
    test "simple string" do
      assert {:ok, "OK", ""} = RESP3.decode("+OK\r\n")
    end

    test "simple error" do
      assert {:ok, %Redis.Error{message: "ERR unknown"}, ""} =
               RESP3.decode("-ERR unknown\r\n")
    end

    test "number" do
      assert {:ok, 42, ""} = RESP3.decode(":42\r\n")
      assert {:ok, -1, ""} = RESP3.decode(":-1\r\n")
      assert {:ok, 0, ""} = RESP3.decode(":0\r\n")
    end

    test "null" do
      assert {:ok, nil, ""} = RESP3.decode("_\r\n")
    end

    test "boolean" do
      assert {:ok, true, ""} = RESP3.decode("#t\r\n")
      assert {:ok, false, ""} = RESP3.decode("#f\r\n")
    end

    test "double" do
      assert {:ok, 1.5, ""} = RESP3.decode(",1.5\r\n")
      assert {:ok, :infinity, ""} = RESP3.decode(",inf\r\n")
      assert {:ok, :neg_infinity, ""} = RESP3.decode(",-inf\r\n")
    end

    test "big number" do
      assert {:ok, 3_492_890_328_409, ""} = RESP3.decode("(3492890328409\r\n")
    end
  end

  describe "decode/1 - blob types" do
    test "blob string" do
      assert {:ok, "hello", ""} = RESP3.decode("$5\r\nhello\r\n")
    end

    test "empty blob string" do
      assert {:ok, "", ""} = RESP3.decode("$0\r\n\r\n")
    end

    test "null bulk string (RESP2 compat)" do
      assert {:ok, nil, ""} = RESP3.decode("$-1\r\n")
    end

    test "blob error" do
      assert {:ok, %Redis.Error{message: "ERR this is an error"}, ""} =
               RESP3.decode("!20\r\nERR this is an error\r\n")
    end

    test "verbatim string" do
      assert {:ok, {:verbatim, "txt", "hello"}, ""} =
               RESP3.decode("=9\r\ntxt:hello\r\n")
    end
  end

  describe "decode/1 - aggregates" do
    test "array" do
      data = "*3\r\n:1\r\n:2\r\n:3\r\n"
      assert {:ok, [1, 2, 3], ""} = RESP3.decode(data)
    end

    test "null array (RESP2 compat)" do
      assert {:ok, nil, ""} = RESP3.decode("*-1\r\n")
    end

    test "nested array" do
      data = "*2\r\n*2\r\n:1\r\n:2\r\n*2\r\n:3\r\n:4\r\n"
      assert {:ok, [[1, 2], [3, 4]], ""} = RESP3.decode(data)
    end

    test "map" do
      data = "%2\r\n+key1\r\n:1\r\n+key2\r\n:2\r\n"
      assert {:ok, %{"key1" => 1, "key2" => 2}, ""} = RESP3.decode(data)
    end

    test "set" do
      data = "~3\r\n:1\r\n:2\r\n:3\r\n"
      assert {:ok, set, ""} = RESP3.decode(data)
      assert set == MapSet.new([1, 2, 3])
    end

    test "push" do
      data = ">2\r\n+invalidate\r\n+key1\r\n"
      assert {:ok, {:push, ["invalidate", "key1"]}, ""} = RESP3.decode(data)
    end
  end

  describe "decode/1 - mixed types in array" do
    test "array with mixed types" do
      data = "*4\r\n+OK\r\n:42\r\n$5\r\nhello\r\n#t\r\n"
      assert {:ok, ["OK", 42, "hello", true], ""} = RESP3.decode(data)
    end
  end

  describe "decode/1 - incomplete data" do
    test "returns continuation for empty data" do
      assert {:continuation, _} = RESP3.decode(<<>>)
    end

    test "returns continuation for partial simple string" do
      assert {:continuation, _} = RESP3.decode("+OK")
    end

    test "returns continuation for partial blob string" do
      assert {:continuation, _} = RESP3.decode("$5\r\nhel")
    end
  end

  describe "decode/1 - leftover data" do
    test "returns remaining data after decode" do
      assert {:ok, "OK", "+NEXT\r\n"} = RESP3.decode("+OK\r\n+NEXT\r\n")
    end
  end
end

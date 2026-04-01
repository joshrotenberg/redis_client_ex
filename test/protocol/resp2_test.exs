defmodule RedisEx.Protocol.RESP2Test do
  use ExUnit.Case, async: true

  alias RedisEx.Protocol.RESP2

  describe "decode/1" do
    test "simple string" do
      assert {:ok, "OK", ""} = RESP2.decode("+OK\r\n")
    end

    test "error" do
      assert {:ok, %RedisEx.Error{message: "ERR unknown"}, ""} =
               RESP2.decode("-ERR unknown\r\n")
    end

    test "integer" do
      assert {:ok, 42, ""} = RESP2.decode(":42\r\n")
    end

    test "bulk string" do
      assert {:ok, "hello", ""} = RESP2.decode("$5\r\nhello\r\n")
    end

    test "null bulk string" do
      assert {:ok, nil, ""} = RESP2.decode("$-1\r\n")
    end

    test "array" do
      assert {:ok, [1, 2, 3], ""} = RESP2.decode("*3\r\n:1\r\n:2\r\n:3\r\n")
    end

    test "null array" do
      assert {:ok, nil, ""} = RESP2.decode("*-1\r\n")
    end

    test "mixed array" do
      data = "*3\r\n+OK\r\n:42\r\n$5\r\nhello\r\n"
      assert {:ok, ["OK", 42, "hello"], ""} = RESP2.decode(data)
    end
  end
end

defmodule Redis.Monitor.EntryTest do
  use ExUnit.Case, async: true

  alias Redis.Monitor.Entry

  describe "parse/1" do
    test "parses a standard monitor record" do
      raw = ~s(1339518083.107412 [0 127.0.0.1:60866] "SET" "key" "value")

      assert {:ok,
              %Entry{
                timestamp: 1_339_518_083.107412,
                database: 0,
                client: "127.0.0.1:60866",
                command: "SET",
                arguments: ["key", "value"],
                raw: ^raw
              }} = Entry.parse(raw)
    end

    test "decodes quoted, control, and binary escapes" do
      raw = ~s(1.25 [2 unix:/tmp/redis.sock] "set" "a\\\"b" "line\\nnext" "\\x00\\xff")

      assert {:ok,
              %Entry{
                database: 2,
                client: "unix:/tmp/redis.sock",
                command: "set",
                arguments: ["a\"b", "line\nnext", <<0, 255>>]
              }} = Entry.parse(raw)
    end

    test "supports Lua as a client identifier" do
      assert {:ok, %Entry{client: "lua", command: "GET", arguments: ["key"]}} =
               Entry.parse(~s(10.0 [0 lua] "GET" "key"))
    end

    test "rejects malformed records" do
      assert {:error, :invalid_monitor_entry} = Entry.parse("not a monitor record")
      assert {:error, :invalid_monitor_entry} = Entry.parse(~s(1.0 [0 client] "unterminated))
      assert {:error, :invalid_monitor_entry} = Entry.parse(~s(1.0 [0 client] "bad\\q"))
    end
  end
end

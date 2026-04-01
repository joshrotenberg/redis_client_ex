defmodule Redis.Protocol.CoerceTest do
  use ExUnit.Case, async: true

  alias Redis.Protocol.Coerce

  describe "coerce/2" do
    test "HGETALL flat list to map" do
      assert Coerce.coerce(["f1", "v1", "f2", "v2"], "HGETALL") == %{"f1" => "v1", "f2" => "v2"}
    end

    test "HGETALL case insensitive" do
      assert Coerce.coerce(["a", "1"], "hgetall") == %{"a" => "1"}
    end

    test "HGETALL odd-length list unchanged" do
      assert Coerce.coerce(["a", "b", "c"], "HGETALL") == ["a", "b", "c"]
    end

    test "CONFIG flat list to map" do
      assert Coerce.coerce(["maxmemory", "0", "hz", "10"], "CONFIG") ==
               %{"maxmemory" => "0", "hz" => "10"}
    end

    test "SMEMBERS list to MapSet" do
      assert Coerce.coerce(["a", "b", "c"], "SMEMBERS") == MapSet.new(["a", "b", "c"])
    end

    test "SDIFF list to MapSet" do
      assert Coerce.coerce(["x", "y"], "SDIFF") == MapSet.new(["x", "y"])
    end

    test "SINTER list to MapSet" do
      assert Coerce.coerce(["a"], "SINTER") == MapSet.new(["a"])
    end

    test "unknown command passes through" do
      assert Coerce.coerce("OK", "SET") == "OK"
      assert Coerce.coerce(42, "INCR") == 42
      assert Coerce.coerce(nil, "GET") == nil
    end

    test "non-list result passes through even for map commands" do
      assert Coerce.coerce(nil, "HGETALL") == nil
      assert Coerce.coerce("OK", "SMEMBERS") == "OK"
    end
  end

  describe "command_name/1" do
    test "extracts and upcases command name" do
      assert Coerce.command_name(["get", "key"]) == "GET"
      assert Coerce.command_name(["HGETALL", "key"]) == "HGETALL"
      assert Coerce.command_name(["PING"]) == "PING"
    end

    test "empty/invalid returns empty string" do
      assert Coerce.command_name([]) == ""
      assert Coerce.command_name(nil) == ""
    end
  end
end

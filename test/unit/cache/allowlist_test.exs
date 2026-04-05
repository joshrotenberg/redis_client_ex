defmodule Redis.Cache.AllowlistTest do
  use ExUnit.Case, async: true

  alias Redis.Cache.Allowlist

  describe "normalize/1" do
    test ":default produces a map with all default commands" do
      {:map, map} = Allowlist.normalize(:default)

      assert map["GET"] == nil
      assert map["HGETALL"] == nil
      assert map["LRANGE"] == nil
      assert map["ZCARD"] == nil
      assert map["JSON.GET"] == nil
      assert map["TS.RANGE"] == nil

      # Not in the allowlist
      refute Map.has_key?(map, "SET")
      refute Map.has_key?(map, "DEL")
      refute Map.has_key?(map, "MGET")
    end

    test "list of strings" do
      {:map, map} = Allowlist.normalize(["GET", "LLEN"])

      assert map["GET"] == nil
      assert map["LLEN"] == nil
      assert map_size(map) == 2
    end

    test "list with per-command TTL" do
      {:map, map} = Allowlist.normalize(["GET", {"LRANGE", ttl: 5_000}])

      assert map["GET"] == nil
      assert map["LRANGE"] == 5_000
    end

    test "list normalizes case" do
      {:map, map} = Allowlist.normalize(["get", {"lrange", ttl: 1_000}])

      assert map["GET"] == nil
      assert map["LRANGE"] == 1_000
    end

    test "function is stored as-is" do
      fun = fn
        ["GET" | _] -> true
        _ -> false
      end

      assert {:function, ^fun} = Allowlist.normalize(fun)
    end
  end

  describe "check/2" do
    test "map — command in allowlist" do
      config = Allowlist.normalize(:default)
      assert {:ok, nil} = Allowlist.check(config, ["GET", "mykey"])
    end

    test "map — command not in allowlist" do
      config = Allowlist.normalize(:default)
      assert :nocache = Allowlist.check(config, ["SET", "mykey", "val"])
    end

    test "map — per-command TTL" do
      config = Allowlist.normalize([{"LRANGE", ttl: 3_000}])
      assert {:ok, 3_000} = Allowlist.check(config, ["LRANGE", "mylist", "0", "10"])
    end

    test "map — case insensitive command matching" do
      config = Allowlist.normalize(:default)
      assert {:ok, nil} = Allowlist.check(config, ["get", "mykey"])
    end

    test "function — returns true" do
      config =
        Allowlist.normalize(fn
          ["GET" | _] -> true
          _ -> false
        end)

      assert {:ok, nil} = Allowlist.check(config, ["GET", "mykey"])
    end

    test "function — returns {:ok, ttl}" do
      config = Allowlist.normalize(fn _ -> {:ok, 5_000} end)
      assert {:ok, 5_000} = Allowlist.check(config, ["LRANGE", "mylist", "0", "10"])
    end

    test "function — returns false" do
      config = Allowlist.normalize(fn _ -> false end)
      assert :nocache = Allowlist.check(config, ["GET", "mykey"])
    end
  end

  describe "default_commands/0" do
    test "returns a non-empty list of strings" do
      commands = Allowlist.default_commands()
      assert is_list(commands)
      assert length(commands) > 50
      assert Enum.all?(commands, &is_binary/1)
    end

    test "does not include write commands" do
      commands = Allowlist.default_commands()
      refute "SET" in commands
      refute "DEL" in commands
      refute "LPUSH" in commands
      refute "ZADD" in commands
    end

    test "does not include multi-key commands" do
      commands = Allowlist.default_commands()
      refute "MGET" in commands
      refute "SDIFF" in commands
      refute "SINTER" in commands
      refute "SUNION" in commands
    end
  end
end

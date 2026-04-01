defmodule Redis.Commands.SetExpandedTest do
  use ExUnit.Case, async: true

  alias Redis.Commands.Set

  describe "SADD" do
    test "basic" do
      assert Set.sadd("s", ["a", "b", "c"]) == ["SADD", "s", "a", "b", "c"]
    end
  end

  describe "SREM" do
    test "basic" do
      assert Set.srem("s", ["a", "b"]) == ["SREM", "s", "a", "b"]
    end
  end

  describe "SMEMBERS" do
    test "basic" do
      assert Set.smembers("s") == ["SMEMBERS", "s"]
    end
  end

  describe "SISMEMBER" do
    test "basic" do
      assert Set.sismember("s", "a") == ["SISMEMBER", "s", "a"]
    end
  end

  describe "SCARD" do
    test "basic" do
      assert Set.scard("s") == ["SCARD", "s"]
    end
  end

  describe "SDIFF" do
    test "basic" do
      assert Set.sdiff(["s1", "s2"]) == ["SDIFF", "s1", "s2"]
    end
  end

  describe "SDIFFSTORE" do
    test "basic" do
      assert Set.sdiffstore("dest", ["s1", "s2"]) == ["SDIFFSTORE", "dest", "s1", "s2"]
    end
  end

  describe "SINTER" do
    test "basic" do
      assert Set.sinter(["s1", "s2"]) == ["SINTER", "s1", "s2"]
    end
  end

  describe "SINTERCARD" do
    test "basic" do
      assert Set.sintercard(2, ["s1", "s2"]) == ["SINTERCARD", "2", "s1", "s2"]
    end

    test "with limit" do
      assert Set.sintercard(2, ["s1", "s2"], limit: 5) ==
               ["SINTERCARD", "2", "s1", "s2", "LIMIT", "5"]
    end
  end

  describe "SINTERSTORE" do
    test "basic" do
      assert Set.sinterstore("dest", ["s1", "s2"]) == ["SINTERSTORE", "dest", "s1", "s2"]
    end
  end

  describe "SMISMEMBER" do
    test "basic" do
      assert Set.smismember("s", ["a", "b", "c"]) == ["SMISMEMBER", "s", "a", "b", "c"]
    end
  end

  describe "SMOVE" do
    test "basic" do
      assert Set.smove("src", "dst", "member") == ["SMOVE", "src", "dst", "member"]
    end
  end

  describe "SPOP" do
    test "without count" do
      assert Set.spop("s") == ["SPOP", "s"]
    end

    test "with count" do
      assert Set.spop("s", 3) == ["SPOP", "s", "3"]
    end
  end

  describe "SRANDMEMBER" do
    test "without count" do
      assert Set.srandmember("s") == ["SRANDMEMBER", "s"]
    end

    test "with count" do
      assert Set.srandmember("s", 5) == ["SRANDMEMBER", "s", "5"]
    end

    test "with negative count" do
      assert Set.srandmember("s", -3) == ["SRANDMEMBER", "s", "-3"]
    end
  end

  describe "SSCAN" do
    test "basic" do
      assert Set.sscan("s", 0) == ["SSCAN", "s", "0"]
    end

    test "with match and count" do
      assert Set.sscan("s", 0, match: "a*", count: 100) ==
               ["SSCAN", "s", "0", "MATCH", "a*", "COUNT", "100"]
    end
  end

  describe "SUNION" do
    test "basic" do
      assert Set.sunion(["s1", "s2"]) == ["SUNION", "s1", "s2"]
    end
  end

  describe "SUNIONSTORE" do
    test "basic" do
      assert Set.sunionstore("dest", ["s1", "s2"]) == ["SUNIONSTORE", "dest", "s1", "s2"]
    end
  end
end

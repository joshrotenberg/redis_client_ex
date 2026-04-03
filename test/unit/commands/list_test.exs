defmodule Redis.Commands.ListExpandedTest do
  use ExUnit.Case, async: true

  alias Redis.Commands.List

  describe "LPUSH" do
    test "basic" do
      assert List.lpush("list", ["a", "b"]) == ["LPUSH", "list", "a", "b"]
    end
  end

  describe "RPUSH" do
    test "basic" do
      assert List.rpush("list", ["a", "b"]) == ["RPUSH", "list", "a", "b"]
    end
  end

  describe "LPOP" do
    test "without count" do
      assert List.lpop("list") == ["LPOP", "list"]
    end

    test "with count" do
      assert List.lpop("list", 3) == ["LPOP", "list", "3"]
    end
  end

  describe "RPOP" do
    test "without count" do
      assert List.rpop("list") == ["RPOP", "list"]
    end

    test "with count" do
      assert List.rpop("list", 3) == ["RPOP", "list", "3"]
    end
  end

  describe "LRANGE" do
    test "basic" do
      assert List.lrange("list", 0, -1) == ["LRANGE", "list", "0", "-1"]
    end
  end

  describe "LLEN" do
    test "basic" do
      assert List.llen("list") == ["LLEN", "list"]
    end
  end

  describe "BLPOP" do
    test "basic" do
      assert List.blpop(["l1", "l2"], 5) == ["BLPOP", "l1", "l2", "5"]
    end
  end

  describe "BRPOP" do
    test "basic" do
      assert List.brpop(["l1"], 0) == ["BRPOP", "l1", "0"]
    end
  end

  describe "BLMOVE" do
    test "basic" do
      assert List.blmove("src", "dst", "LEFT", "RIGHT", 10) ==
               ["BLMOVE", "src", "dst", "LEFT", "RIGHT", "10"]
    end
  end

  describe "LINDEX" do
    test "basic" do
      assert List.lindex("list", 3) == ["LINDEX", "list", "3"]
    end

    test "negative index" do
      assert List.lindex("list", -1) == ["LINDEX", "list", "-1"]
    end
  end

  describe "LINSERT" do
    test "before" do
      assert List.linsert("list", :before, "pivot", "element") ==
               ["LINSERT", "list", "BEFORE", "pivot", "element"]
    end

    test "after" do
      assert List.linsert("list", :after, "pivot", "element") ==
               ["LINSERT", "list", "AFTER", "pivot", "element"]
    end
  end

  describe "LMOVE" do
    test "basic" do
      assert List.lmove("src", "dst", "LEFT", "RIGHT") ==
               ["LMOVE", "src", "dst", "LEFT", "RIGHT"]
    end
  end

  describe "LPOS" do
    test "basic" do
      assert List.lpos("list", "elem") == ["LPOS", "list", "elem"]
    end

    test "with rank" do
      assert List.lpos("list", "elem", rank: 2) == ["LPOS", "list", "elem", "RANK", "2"]
    end

    test "with count and maxlen" do
      assert List.lpos("list", "elem", count: 0, maxlen: 1000) ==
               ["LPOS", "list", "elem", "COUNT", "0", "MAXLEN", "1000"]
    end
  end

  describe "LPUSHX" do
    test "basic" do
      assert List.lpushx("list", ["a", "b"]) == ["LPUSHX", "list", "a", "b"]
    end
  end

  describe "RPUSHX" do
    test "basic" do
      assert List.rpushx("list", ["a"]) == ["RPUSHX", "list", "a"]
    end
  end

  describe "LREM" do
    test "basic" do
      assert List.lrem("list", 2, "elem") == ["LREM", "list", "2", "elem"]
    end
  end

  describe "LSET" do
    test "basic" do
      assert List.lset("list", 0, "newval") == ["LSET", "list", "0", "newval"]
    end
  end

  describe "LTRIM" do
    test "basic" do
      assert List.ltrim("list", 0, 99) == ["LTRIM", "list", "0", "99"]
    end
  end

  describe "LMPOP" do
    test "basic" do
      assert List.lmpop(2, ["l1", "l2"], "LEFT") == ["LMPOP", "2", "l1", "l2", "LEFT"]
    end

    test "with count" do
      assert List.lmpop(1, ["l1"], "RIGHT", count: 5) ==
               ["LMPOP", "1", "l1", "RIGHT", "COUNT", "5"]
    end
  end

  describe "BLMPOP" do
    test "basic" do
      assert List.blmpop(0, 2, ["l1", "l2"], "LEFT") ==
               ["BLMPOP", "0", "2", "l1", "l2", "LEFT"]
    end

    test "with count" do
      assert List.blmpop(5, 1, ["l1"], "RIGHT", count: 3) ==
               ["BLMPOP", "5", "1", "l1", "RIGHT", "COUNT", "3"]
    end
  end

  describe "RPOPLPUSH (deprecated)" do
    test "basic" do
      assert List.rpoplpush("src", "dst") == ["RPOPLPUSH", "src", "dst"]
    end
  end

  describe "BRPOPLPUSH (deprecated)" do
    test "basic" do
      assert List.brpoplpush("src", "dst", 10) == ["BRPOPLPUSH", "src", "dst", "10"]
    end
  end
end

defmodule Redis.Commands.SortedSetTest do
  use ExUnit.Case, async: true

  alias Redis.Commands.SortedSet

  describe "ZADD" do
    test "basic" do
      assert SortedSet.zadd("zs", [{1.0, "a"}, {2.0, "b"}]) ==
               ["ZADD", "zs", "1.0", "a", "2.0", "b"]
    end

    test "with NX" do
      assert SortedSet.zadd("zs", [{1.0, "a"}], nx: true) ==
               ["ZADD", "zs", "NX", "1.0", "a"]
    end

    test "with XX and GT" do
      assert SortedSet.zadd("zs", [{5.0, "a"}], xx: true, gt: true) ==
               ["ZADD", "zs", "XX", "GT", "5.0", "a"]
    end
  end

  describe "ZSCORE" do
    test "basic" do
      assert SortedSet.zscore("zs", "a") == ["ZSCORE", "zs", "a"]
    end
  end

  describe "ZRANGE" do
    test "basic" do
      assert SortedSet.zrange("zs", "0", "-1") == ["ZRANGE", "zs", "0", "-1"]
    end

    test "with REV and WITHSCORES" do
      assert SortedSet.zrange("zs", "0", "-1", rev: true, withscores: true) ==
               ["ZRANGE", "zs", "0", "-1", "REV", "WITHSCORES"]
    end

    test "with LIMIT" do
      assert SortedSet.zrange("zs", "0", "100", limit: {0, 10}) ==
               ["ZRANGE", "zs", "0", "100", "LIMIT", "0", "10"]
    end
  end

  describe "ZRANK" do
    test "basic" do
      assert SortedSet.zrank("zs", "a") == ["ZRANK", "zs", "a"]
    end
  end

  describe "ZREM" do
    test "basic" do
      assert SortedSet.zrem("zs", ["a", "b"]) == ["ZREM", "zs", "a", "b"]
    end
  end

  describe "ZCARD" do
    test "basic" do
      assert SortedSet.zcard("zs") == ["ZCARD", "zs"]
    end
  end

  describe "ZCOUNT" do
    test "basic" do
      assert SortedSet.zcount("zs", "-inf", "+inf") == ["ZCOUNT", "zs", "-inf", "+inf"]
    end
  end

  describe "BZPOPMAX" do
    test "basic" do
      assert SortedSet.bzpopmax(["zs1", "zs2"], 0) == ["BZPOPMAX", "zs1", "zs2", "0"]
    end
  end

  describe "BZPOPMIN" do
    test "basic" do
      assert SortedSet.bzpopmin(["zs1"], 5) == ["BZPOPMIN", "zs1", "5"]
    end
  end

  describe "BZMPOP" do
    test "basic" do
      assert SortedSet.bzmpop(0, 2, ["zs1", "zs2"], "MIN") ==
               ["BZMPOP", "0", "2", "zs1", "zs2", "MIN"]
    end

    test "with count" do
      assert SortedSet.bzmpop(0, 1, ["zs"], "MAX", count: 3) ==
               ["BZMPOP", "0", "1", "zs", "MAX", "COUNT", "3"]
    end
  end

  describe "ZREVRANGEBYLEX" do
    test "basic" do
      assert SortedSet.zrevrangebylex("zs", "+", "-") ==
               ["ZREVRANGEBYLEX", "zs", "+", "-"]
    end

    test "with limit" do
      assert SortedSet.zrevrangebylex("zs", "+", "-", limit: {0, 10}) ==
               ["ZREVRANGEBYLEX", "zs", "+", "-", "LIMIT", "0", "10"]
    end
  end

  describe "ZDIFF" do
    test "basic" do
      assert SortedSet.zdiff(2, ["zs1", "zs2"]) == ["ZDIFF", "2", "zs1", "zs2"]
    end

    test "with WITHSCORES" do
      assert SortedSet.zdiff(2, ["zs1", "zs2"], withscores: true) ==
               ["ZDIFF", "2", "zs1", "zs2", "WITHSCORES"]
    end
  end

  describe "ZDIFFSTORE" do
    test "basic" do
      assert SortedSet.zdiffstore("dest", 2, ["zs1", "zs2"]) ==
               ["ZDIFFSTORE", "dest", "2", "zs1", "zs2"]
    end
  end

  describe "ZINCRBY" do
    test "basic" do
      assert SortedSet.zincrby("zs", 2, "a") == ["ZINCRBY", "zs", "2", "a"]
    end
  end

  describe "ZINTER" do
    test "basic" do
      assert SortedSet.zinter(2, ["zs1", "zs2"]) == ["ZINTER", "2", "zs1", "zs2"]
    end

    test "with weights and aggregate" do
      cmd =
        SortedSet.zinter(2, ["zs1", "zs2"], weights: [1, 2], aggregate: "SUM", withscores: true)

      assert "WEIGHTS" in cmd
      assert "AGGREGATE" in cmd
      assert "WITHSCORES" in cmd
    end
  end

  describe "ZINTERCARD" do
    test "basic" do
      assert SortedSet.zintercard(2, ["zs1", "zs2"]) == ["ZINTERCARD", "2", "zs1", "zs2"]
    end

    test "with limit" do
      assert SortedSet.zintercard(2, ["zs1", "zs2"], limit: 5) ==
               ["ZINTERCARD", "2", "zs1", "zs2", "LIMIT", "5"]
    end
  end

  describe "ZINTERSTORE" do
    test "basic" do
      assert SortedSet.zinterstore("dest", 2, ["zs1", "zs2"]) ==
               ["ZINTERSTORE", "dest", "2", "zs1", "zs2"]
    end
  end

  describe "ZLEXCOUNT" do
    test "basic" do
      assert SortedSet.zlexcount("zs", "-", "+") == ["ZLEXCOUNT", "zs", "-", "+"]
    end
  end

  describe "ZMPOP" do
    test "basic" do
      assert SortedSet.zmpop(2, ["zs1", "zs2"], "MIN") ==
               ["ZMPOP", "2", "zs1", "zs2", "MIN"]
    end

    test "with count" do
      assert SortedSet.zmpop(1, ["zs"], "MAX", count: 3) ==
               ["ZMPOP", "1", "zs", "MAX", "COUNT", "3"]
    end
  end

  describe "ZMSCORE" do
    test "basic" do
      assert SortedSet.zmscore("zs", ["a", "b"]) == ["ZMSCORE", "zs", "a", "b"]
    end
  end

  describe "ZPOPMAX" do
    test "without count" do
      assert SortedSet.zpopmax("zs") == ["ZPOPMAX", "zs"]
    end

    test "with count" do
      assert SortedSet.zpopmax("zs", 3) == ["ZPOPMAX", "zs", "3"]
    end
  end

  describe "ZPOPMIN" do
    test "without count" do
      assert SortedSet.zpopmin("zs") == ["ZPOPMIN", "zs"]
    end

    test "with count" do
      assert SortedSet.zpopmin("zs", 2) == ["ZPOPMIN", "zs", "2"]
    end
  end

  describe "ZRANDMEMBER" do
    test "basic" do
      assert SortedSet.zrandmember("zs") == ["ZRANDMEMBER", "zs"]
    end

    test "with count and withscores" do
      assert SortedSet.zrandmember("zs", count: 3, withscores: true) ==
               ["ZRANDMEMBER", "zs", "3", "WITHSCORES"]
    end
  end

  describe "ZRANGEBYLEX" do
    test "basic" do
      assert SortedSet.zrangebylex("zs", "-", "+") == ["ZRANGEBYLEX", "zs", "-", "+"]
    end

    test "with limit" do
      assert SortedSet.zrangebylex("zs", "-", "+", limit: {0, 10}) ==
               ["ZRANGEBYLEX", "zs", "-", "+", "LIMIT", "0", "10"]
    end
  end

  describe "ZRANGEBYSCORE" do
    test "basic" do
      assert SortedSet.zrangebyscore("zs", "-inf", "+inf") ==
               ["ZRANGEBYSCORE", "zs", "-inf", "+inf"]
    end

    test "with withscores and limit" do
      assert SortedSet.zrangebyscore("zs", "0", "100", withscores: true, limit: {0, 10}) ==
               ["ZRANGEBYSCORE", "zs", "0", "100", "WITHSCORES", "LIMIT", "0", "10"]
    end
  end

  describe "ZRANGESTORE" do
    test "basic" do
      assert SortedSet.zrangestore("dst", "src", "0", "-1") ==
               ["ZRANGESTORE", "dst", "src", "0", "-1"]
    end

    test "with byscore and rev" do
      assert SortedSet.zrangestore("dst", "src", "0", "100", byscore: true, rev: true) ==
               ["ZRANGESTORE", "dst", "src", "0", "100", "BYSCORE", "REV"]
    end
  end

  describe "ZREVRANGE" do
    test "basic" do
      assert SortedSet.zrevrange("zs", 0, -1) == ["ZREVRANGE", "zs", "0", "-1"]
    end

    test "with withscores" do
      assert SortedSet.zrevrange("zs", 0, -1, withscores: true) ==
               ["ZREVRANGE", "zs", "0", "-1", "WITHSCORES"]
    end
  end

  describe "ZREVRANGEBYSCORE" do
    test "basic" do
      assert SortedSet.zrevrangebyscore("zs", "+inf", "-inf") ==
               ["ZREVRANGEBYSCORE", "zs", "+inf", "-inf"]
    end
  end

  describe "ZREVRANK" do
    test "basic" do
      assert SortedSet.zrevrank("zs", "a") == ["ZREVRANK", "zs", "a"]
    end
  end

  describe "ZSCAN" do
    test "basic" do
      assert SortedSet.zscan("zs", 0) == ["ZSCAN", "zs", "0"]
    end

    test "with match and count" do
      assert SortedSet.zscan("zs", 0, match: "a*", count: 100) ==
               ["ZSCAN", "zs", "0", "MATCH", "a*", "COUNT", "100"]
    end
  end

  describe "ZUNION" do
    test "basic" do
      assert SortedSet.zunion(2, ["zs1", "zs2"]) == ["ZUNION", "2", "zs1", "zs2"]
    end
  end

  describe "ZUNIONSTORE" do
    test "basic" do
      assert SortedSet.zunionstore("dest", 2, ["zs1", "zs2"]) ==
               ["ZUNIONSTORE", "dest", "2", "zs1", "zs2"]
    end
  end

  describe "ZREMRANGEBYLEX" do
    test "basic" do
      assert SortedSet.zremrangebylex("zs", "[a", "[z") == ["ZREMRANGEBYLEX", "zs", "[a", "[z"]
    end
  end

  describe "ZREMRANGEBYRANK" do
    test "basic" do
      assert SortedSet.zremrangebyrank("zs", 0, 1) == ["ZREMRANGEBYRANK", "zs", "0", "1"]
    end
  end

  describe "ZREMRANGEBYSCORE" do
    test "basic" do
      assert SortedSet.zremrangebyscore("zs", "-inf", "+inf") ==
               ["ZREMRANGEBYSCORE", "zs", "-inf", "+inf"]
    end
  end
end

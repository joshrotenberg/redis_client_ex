defmodule Redis.Commands.HashExpandedTest do
  use ExUnit.Case, async: true

  alias Redis.Commands.Hash

  describe "HGET" do
    test "basic" do
      assert Hash.hget("h", "field") == ["HGET", "h", "field"]
    end
  end

  describe "HSET" do
    test "basic" do
      assert Hash.hset("h", [{"f1", "v1"}, {"f2", "v2"}]) ==
               ["HSET", "h", "f1", "v1", "f2", "v2"]
    end
  end

  describe "HGETALL" do
    test "basic" do
      assert Hash.hgetall("h") == ["HGETALL", "h"]
    end
  end

  describe "HDEL" do
    test "basic" do
      assert Hash.hdel("h", ["f1", "f2"]) == ["HDEL", "h", "f1", "f2"]
    end
  end

  describe "HINCRBY" do
    test "basic" do
      assert Hash.hincrby("h", "counter", 5) == ["HINCRBY", "h", "counter", "5"]
    end
  end

  describe "HKEYS" do
    test "basic" do
      assert Hash.hkeys("h") == ["HKEYS", "h"]
    end
  end

  describe "HVALS" do
    test "basic" do
      assert Hash.hvals("h") == ["HVALS", "h"]
    end
  end

  describe "HLEN" do
    test "basic" do
      assert Hash.hlen("h") == ["HLEN", "h"]
    end
  end

  describe "HEXISTS" do
    test "basic" do
      assert Hash.hexists("h", "field") == ["HEXISTS", "h", "field"]
    end
  end

  describe "HINCRBYFLOAT" do
    test "basic" do
      assert Hash.hincrbyfloat("h", "price", 1.5) == ["HINCRBYFLOAT", "h", "price", "1.5"]
    end
  end

  describe "HMGET" do
    test "basic" do
      assert Hash.hmget("h", ["f1", "f2", "f3"]) == ["HMGET", "h", "f1", "f2", "f3"]
    end
  end

  describe "HRANDFIELD" do
    test "without options" do
      assert Hash.hrandfield("h") == ["HRANDFIELD", "h"]
    end

    test "with count" do
      assert Hash.hrandfield("h", count: 3) == ["HRANDFIELD", "h", "3"]
    end

    test "with count and WITHVALUES" do
      assert Hash.hrandfield("h", count: 3, withvalues: true) ==
               ["HRANDFIELD", "h", "3", "WITHVALUES"]
    end
  end

  describe "HSCAN" do
    test "basic" do
      assert Hash.hscan("h", 0) == ["HSCAN", "h", "0"]
    end

    test "with match and count" do
      assert Hash.hscan("h", 0, match: "f*", count: 100) ==
               ["HSCAN", "h", "0", "MATCH", "f*", "COUNT", "100"]
    end
  end

  describe "HSETNX" do
    test "basic" do
      assert Hash.hsetnx("h", "field", "value") == ["HSETNX", "h", "field", "value"]
    end
  end

  describe "HSTRLEN" do
    test "basic" do
      assert Hash.hstrlen("h", "field") == ["HSTRLEN", "h", "field"]
    end
  end

  describe "HMSET (deprecated)" do
    test "basic" do
      assert Hash.hmset("h", [{"f1", "v1"}, {"f2", "v2"}]) ==
               ["HMSET", "h", "f1", "v1", "f2", "v2"]
    end
  end

  describe "hash field expiration (7.4+)" do
    test "HEXPIRE" do
      assert Hash.hexpire("h", 60, ["f1", "f2"]) ==
               ["HEXPIRE", "h", "60", "FIELDS", "2", "f1", "f2"]
    end

    test "HEXPIRE with NX" do
      assert Hash.hexpire("h", 60, ["f1"], nx: true) ==
               ["HEXPIRE", "h", "60", "NX", "FIELDS", "1", "f1"]
    end

    test "HEXPIRE with GT" do
      assert Hash.hexpire("h", 60, ["f1"], gt: true) ==
               ["HEXPIRE", "h", "60", "GT", "FIELDS", "1", "f1"]
    end

    test "HPEXPIRE" do
      assert Hash.hpexpire("h", 5_000, ["f1"]) ==
               ["HPEXPIRE", "h", "5000", "FIELDS", "1", "f1"]
    end

    test "HEXPIREAT" do
      assert Hash.hexpireat("h", 1_700_000_000, ["f1"]) ==
               ["HEXPIREAT", "h", "1700000000", "FIELDS", "1", "f1"]
    end

    test "HPEXPIREAT" do
      assert Hash.hpexpireat("h", 1_700_000_000_000, ["f1"]) ==
               ["HPEXPIREAT", "h", "1700000000000", "FIELDS", "1", "f1"]
    end

    test "HTTL" do
      assert Hash.httl("h", ["f1", "f2"]) == ["HTTL", "h", "FIELDS", "2", "f1", "f2"]
    end

    test "HPTTL" do
      assert Hash.hpttl("h", ["f1"]) == ["HPTTL", "h", "FIELDS", "1", "f1"]
    end

    test "HEXPIRETIME" do
      assert Hash.hexpiretime("h", ["f1"]) == ["HEXPIRETIME", "h", "FIELDS", "1", "f1"]
    end

    test "HPEXPIRETIME" do
      assert Hash.hpexpiretime("h", ["f1"]) == ["HPEXPIRETIME", "h", "FIELDS", "1", "f1"]
    end

    test "HPERSIST" do
      assert Hash.hpersist("h", ["f1", "f2"]) == ["HPERSIST", "h", "FIELDS", "2", "f1", "f2"]
    end
  end

  describe "Redis 8.0+ hash commands" do
    test "HGETEX" do
      assert Hash.hgetex("h", ["f1", "f2"]) == ["HGETEX", "h", "FIELDS", "2", "f1", "f2"]
    end

    test "HGETEX with EX" do
      assert Hash.hgetex("h", ["f1"], ex: 60) ==
               ["HGETEX", "h", "FIELDS", "1", "f1", "EX", "60"]
    end

    test "HGETEX with PERSIST" do
      assert Hash.hgetex("h", ["f1"], persist: true) ==
               ["HGETEX", "h", "FIELDS", "1", "f1", "PERSIST"]
    end

    test "HSETEX" do
      assert Hash.hsetex("h", [{"f1", "v1"}, {"f2", "v2"}], ex: 60) ==
               ["HSETEX", "h", "FIELDS", "2", "f1", "v1", "f2", "v2", "EX", "60"]
    end

    test "HGETDEL" do
      assert Hash.hgetdel("h", ["f1", "f2"]) == ["HGETDEL", "h", "FIELDS", "2", "f1", "f2"]
    end
  end
end

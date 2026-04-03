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

  # ---------------------------------------------------------------------------
  # Hash field expiration commands
  # ---------------------------------------------------------------------------

  describe "HEXPIRE" do
    test "basic" do
      assert Hash.hexpire("h", 60, ["f1", "f2"]) ==
               ["HEXPIRE", "h", "60", "FIELDS", "2", "f1", "f2"]
    end

    test "single field" do
      assert Hash.hexpire("h", 10, ["f1"]) ==
               ["HEXPIRE", "h", "10", "FIELDS", "1", "f1"]
    end

    test "with NX option" do
      assert Hash.hexpire("h", 60, ["f1"], nx: true) ==
               ["HEXPIRE", "h", "60", "NX", "FIELDS", "1", "f1"]
    end

    test "with XX option" do
      assert Hash.hexpire("h", 60, ["f1"], xx: true) ==
               ["HEXPIRE", "h", "60", "XX", "FIELDS", "1", "f1"]
    end

    test "with GT option" do
      assert Hash.hexpire("h", 60, ["f1"], gt: true) ==
               ["HEXPIRE", "h", "60", "GT", "FIELDS", "1", "f1"]
    end

    test "with LT option" do
      assert Hash.hexpire("h", 60, ["f1"], lt: true) ==
               ["HEXPIRE", "h", "60", "LT", "FIELDS", "1", "f1"]
    end
  end

  describe "HPEXPIRE" do
    test "basic" do
      assert Hash.hpexpire("h", 5000, ["f1", "f2"]) ==
               ["HPEXPIRE", "h", "5000", "FIELDS", "2", "f1", "f2"]
    end

    test "with NX option" do
      assert Hash.hpexpire("h", 5000, ["f1"], nx: true) ==
               ["HPEXPIRE", "h", "5000", "NX", "FIELDS", "1", "f1"]
    end

    test "with XX option" do
      assert Hash.hpexpire("h", 5000, ["f1"], xx: true) ==
               ["HPEXPIRE", "h", "5000", "XX", "FIELDS", "1", "f1"]
    end

    test "with GT option" do
      assert Hash.hpexpire("h", 5000, ["f1"], gt: true) ==
               ["HPEXPIRE", "h", "5000", "GT", "FIELDS", "1", "f1"]
    end

    test "with LT option" do
      assert Hash.hpexpire("h", 5000, ["f1"], lt: true) ==
               ["HPEXPIRE", "h", "5000", "LT", "FIELDS", "1", "f1"]
    end
  end

  describe "HEXPIREAT" do
    test "basic" do
      assert Hash.hexpireat("h", 1_893_456_000, ["f1"]) ==
               ["HEXPIREAT", "h", "1893456000", "FIELDS", "1", "f1"]
    end

    test "with NX option" do
      assert Hash.hexpireat("h", 1_893_456_000, ["f1"], nx: true) ==
               ["HEXPIREAT", "h", "1893456000", "NX", "FIELDS", "1", "f1"]
    end

    test "with GT option" do
      assert Hash.hexpireat("h", 1_893_456_000, ["f1"], gt: true) ==
               ["HEXPIREAT", "h", "1893456000", "GT", "FIELDS", "1", "f1"]
    end
  end

  describe "HPEXPIREAT" do
    test "basic" do
      assert Hash.hpexpireat("h", 1_893_456_000_000, ["f1", "f2"]) ==
               ["HPEXPIREAT", "h", "1893456000000", "FIELDS", "2", "f1", "f2"]
    end

    test "with LT option" do
      assert Hash.hpexpireat("h", 1_893_456_000_000, ["f1"], lt: true) ==
               ["HPEXPIREAT", "h", "1893456000000", "LT", "FIELDS", "1", "f1"]
    end
  end

  describe "HTTL" do
    test "basic" do
      assert Hash.httl("h", ["f1", "f2"]) ==
               ["HTTL", "h", "FIELDS", "2", "f1", "f2"]
    end

    test "single field" do
      assert Hash.httl("h", ["f1"]) ==
               ["HTTL", "h", "FIELDS", "1", "f1"]
    end
  end

  describe "HPTTL" do
    test "basic" do
      assert Hash.hpttl("h", ["f1", "f2"]) ==
               ["HPTTL", "h", "FIELDS", "2", "f1", "f2"]
    end
  end

  describe "HEXPIRETIME" do
    test "basic" do
      assert Hash.hexpiretime("h", ["f1", "f2"]) ==
               ["HEXPIRETIME", "h", "FIELDS", "2", "f1", "f2"]
    end
  end

  describe "HPEXPIRETIME" do
    test "basic" do
      assert Hash.hpexpiretime("h", ["f1"]) ==
               ["HPEXPIRETIME", "h", "FIELDS", "1", "f1"]
    end
  end

  describe "HPERSIST" do
    test "basic" do
      assert Hash.hpersist("h", ["f1", "f2"]) ==
               ["HPERSIST", "h", "FIELDS", "2", "f1", "f2"]
    end

    test "single field" do
      assert Hash.hpersist("h", ["f1"]) ==
               ["HPERSIST", "h", "FIELDS", "1", "f1"]
    end
  end

  # ---------------------------------------------------------------------------
  # Redis 8.0+ commands
  # ---------------------------------------------------------------------------

  describe "HGETEX" do
    test "without options" do
      assert Hash.hgetex("h", ["f1", "f2"]) ==
               ["HGETEX", "h", "FIELDS", "2", "f1", "f2"]
    end

    test "single field" do
      assert Hash.hgetex("h", ["f1"]) ==
               ["HGETEX", "h", "FIELDS", "1", "f1"]
    end

    test "with EX" do
      assert Hash.hgetex("h", ["f1", "f2"], ex: 60) ==
               ["HGETEX", "h", "FIELDS", "2", "f1", "f2", "EX", "60"]
    end

    test "with PX" do
      assert Hash.hgetex("h", ["f1"], px: 5000) ==
               ["HGETEX", "h", "FIELDS", "1", "f1", "PX", "5000"]
    end

    test "with EXAT" do
      assert Hash.hgetex("h", ["f1"], exat: 1_893_456_000) ==
               ["HGETEX", "h", "FIELDS", "1", "f1", "EXAT", "1893456000"]
    end

    test "with PXAT" do
      assert Hash.hgetex("h", ["f1"], pxat: 1_893_456_000_000) ==
               ["HGETEX", "h", "FIELDS", "1", "f1", "PXAT", "1893456000000"]
    end

    test "with PERSIST" do
      assert Hash.hgetex("h", ["f1", "f2"], persist: true) ==
               ["HGETEX", "h", "FIELDS", "2", "f1", "f2", "PERSIST"]
    end
  end

  describe "HSETEX" do
    test "with EX" do
      assert Hash.hsetex("h", [{"f1", "v1"}, {"f2", "v2"}], ex: 60) ==
               ["HSETEX", "h", "EX", "60", "FIELDS", "2", "f1", "v1", "f2", "v2"]
    end

    test "with PX" do
      assert Hash.hsetex("h", [{"f1", "v1"}], px: 5000) ==
               ["HSETEX", "h", "PX", "5000", "FIELDS", "1", "f1", "v1"]
    end

    test "with EXAT" do
      assert Hash.hsetex("h", [{"f1", "v1"}], exat: 1_893_456_000) ==
               ["HSETEX", "h", "EXAT", "1893456000", "FIELDS", "1", "f1", "v1"]
    end

    test "with PXAT" do
      assert Hash.hsetex("h", [{"f1", "v1"}], pxat: 1_893_456_000_000) ==
               ["HSETEX", "h", "PXAT", "1893456000000", "FIELDS", "1", "f1", "v1"]
    end

    test "without expiry options" do
      assert Hash.hsetex("h", [{"f1", "v1"}, {"f2", "v2"}]) ==
               ["HSETEX", "h", "FIELDS", "2", "f1", "v1", "f2", "v2"]
    end
  end

  describe "HGETDEL" do
    test "single field" do
      assert Hash.hgetdel("h", ["f1"]) ==
               ["HGETDEL", "h", "FIELDS", "1", "f1"]
    end

    test "multiple fields" do
      assert Hash.hgetdel("h", ["f1", "f2", "f3"]) ==
               ["HGETDEL", "h", "FIELDS", "3", "f1", "f2", "f3"]
    end
  end
end

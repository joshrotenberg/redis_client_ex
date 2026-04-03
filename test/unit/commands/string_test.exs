defmodule Redis.Commands.StringExpandedTest do
  use ExUnit.Case, async: true

  alias Redis.Commands.String, as: S

  describe "GET" do
    test "basic" do
      assert S.get("key") == ["GET", "key"]
    end
  end

  describe "SET" do
    test "basic" do
      assert S.set("key", "value") == ["SET", "key", "value"]
    end

    test "with EX" do
      assert S.set("key", "val", ex: 60) == ["SET", "key", "val", "EX", "60"]
    end

    test "with PX and NX" do
      assert S.set("key", "val", px: 5000, nx: true) == ["SET", "key", "val", "PX", "5000", "NX"]
    end

    test "with XX and GET" do
      assert S.set("key", "val", xx: true, get: true) == ["SET", "key", "val", "XX", "GET"]
    end
  end

  describe "APPEND" do
    test "basic" do
      assert S.append("key", "value") == ["APPEND", "key", "value"]
    end
  end

  describe "DECRBY" do
    test "basic" do
      assert S.decrby("key", 5) == ["DECRBY", "key", "5"]
    end
  end

  describe "DECR" do
    test "basic" do
      assert S.decr("key") == ["DECR", "key"]
    end
  end

  describe "GETDEL" do
    test "basic" do
      assert S.getdel("key") == ["GETDEL", "key"]
    end
  end

  describe "GETEX" do
    test "without options" do
      assert S.getex("key") == ["GETEX", "key"]
    end

    test "with EX" do
      assert S.getex("key", ex: 100) == ["GETEX", "key", "EX", "100"]
    end

    test "with PX" do
      assert S.getex("key", px: 5000) == ["GETEX", "key", "PX", "5000"]
    end

    test "with EXAT" do
      assert S.getex("key", exat: 1_672_531_200) == ["GETEX", "key", "EXAT", "1672531200"]
    end

    test "with PXAT" do
      assert S.getex("key", pxat: 1_672_531_200_000) == ["GETEX", "key", "PXAT", "1672531200000"]
    end

    test "with PERSIST" do
      assert S.getex("key", persist: true) == ["GETEX", "key", "PERSIST"]
    end
  end

  describe "GETRANGE" do
    test "basic" do
      assert S.getrange("key", 0, 5) == ["GETRANGE", "key", "0", "5"]
    end
  end

  describe "INCR" do
    test "basic" do
      assert S.incr("key") == ["INCR", "key"]
    end
  end

  describe "INCRBY" do
    test "basic" do
      assert S.incrby("key", 10) == ["INCRBY", "key", "10"]
    end
  end

  describe "INCRBYFLOAT" do
    test "basic" do
      assert S.incrbyfloat("key", 1.5) == ["INCRBYFLOAT", "key", "1.5"]
    end
  end

  describe "MGET" do
    test "basic" do
      assert S.mget(["k1", "k2"]) == ["MGET", "k1", "k2"]
    end
  end

  describe "MSET" do
    test "basic" do
      assert S.mset([{"k1", "v1"}, {"k2", "v2"}]) == ["MSET", "k1", "v1", "k2", "v2"]
    end
  end

  describe "MSETNX" do
    test "basic" do
      assert S.msetnx([{"k1", "v1"}, {"k2", "v2"}]) == ["MSETNX", "k1", "v1", "k2", "v2"]
    end
  end

  describe "SETEX" do
    test "basic" do
      assert S.setex("key", 60, "val") == ["SETEX", "key", "60", "val"]
    end
  end

  describe "PSETEX" do
    test "basic" do
      assert S.psetex("key", 5000, "val") == ["PSETEX", "key", "5000", "val"]
    end
  end

  describe "SETNX" do
    test "basic" do
      assert S.setnx("key", "val") == ["SETNX", "key", "val"]
    end
  end

  describe "SETRANGE" do
    test "basic" do
      assert S.setrange("key", 5, "val") == ["SETRANGE", "key", "5", "val"]
    end
  end

  describe "STRLEN" do
    test "basic" do
      assert S.strlen("key") == ["STRLEN", "key"]
    end
  end

  describe "GETSET" do
    test "basic" do
      assert S.getset("key", "newval") == ["GETSET", "key", "newval"]
    end
  end

  describe "LCS" do
    test "basic" do
      assert S.lcs("k1", "k2") == ["LCS", "k1", "k2"]
    end

    test "with LEN" do
      assert S.lcs("k1", "k2", len: true) == ["LCS", "k1", "k2", "LEN"]
    end

    test "with IDX and MINMATCHLEN and WITHMATCHLEN" do
      assert S.lcs("k1", "k2", idx: true, minmatchlen: 3, withmatchlen: true) ==
               ["LCS", "k1", "k2", "IDX", "MINMATCHLEN", "3", "WITHMATCHLEN"]
    end
  end

  describe "SUBSTR (deprecated)" do
    test "basic" do
      assert S.substr("key", 0, 5) == ["SUBSTR", "key", "0", "5"]
    end
  end

  # ---------------------------------------------------------------------------
  # Redis 8.0+ commands
  # ---------------------------------------------------------------------------

  describe "SET with IFEQ/IFNE (8.0+)" do
    test "with IFEQ" do
      assert S.set("key", "new", ifeq: "old") ==
               ["SET", "key", "new", "IFEQ", "old"]
    end

    test "with IFNE" do
      assert S.set("key", "new", ifne: "old") ==
               ["SET", "key", "new", "IFNE", "old"]
    end

    test "with IFEQ and EX" do
      assert S.set("key", "new", ex: 60, ifeq: "old") ==
               ["SET", "key", "new", "EX", "60", "IFEQ", "old"]
    end

    test "with IFEQ and GET" do
      assert S.set("key", "new", ifeq: "old", get: true) ==
               ["SET", "key", "new", "IFEQ", "old", "GET"]
    end
  end

  describe "DELEX (GETDEL with conditions, 8.0+)" do
    test "without options" do
      assert S.delex("key") == ["GETDEL", "key"]
    end

    test "with IFEQ" do
      assert S.delex("key", ifeq: "expected") ==
               ["GETDEL", "key", "IFEQ", "expected"]
    end

    test "with IFNE" do
      assert S.delex("key", ifne: "unexpected") ==
               ["GETDEL", "key", "IFNE", "unexpected"]
    end
  end

  describe "DIGEST (8.0+)" do
    test "basic" do
      assert S.digest("key") == ["DIGEST", "key"]
    end
  end

  describe "MSETEX (8.0+)" do
    test "with EX" do
      assert S.msetex([{"k1", "v1"}, {"k2", "v2"}], ex: 60) ==
               ["MSETEX", "EX", "60", "k1", "v1", "k2", "v2"]
    end

    test "with PX" do
      assert S.msetex([{"k1", "v1"}], px: 5000) ==
               ["MSETEX", "PX", "5000", "k1", "v1"]
    end

    test "with EXAT" do
      assert S.msetex([{"k1", "v1"}], exat: 1_893_456_000) ==
               ["MSETEX", "EXAT", "1893456000", "k1", "v1"]
    end

    test "with PXAT" do
      assert S.msetex([{"k1", "v1"}], pxat: 1_893_456_000_000) ==
               ["MSETEX", "PXAT", "1893456000000", "k1", "v1"]
    end

    test "without expiry options" do
      assert S.msetex([{"k1", "v1"}, {"k2", "v2"}]) ==
               ["MSETEX", "k1", "v1", "k2", "v2"]
    end
  end
end

defmodule RedisEx.CommandsTest do
  use ExUnit.Case, async: true

  alias RedisEx.Commands.{String, Hash, List, Set, SortedSet, Key, Stream, Server}

  describe "String commands" do
    test "GET" do
      assert String.get("mykey") == ["GET", "mykey"]
    end

    test "SET with options" do
      assert String.set("k", "v") == ["SET", "k", "v"]
      assert String.set("k", "v", ex: 60) == ["SET", "k", "v", "EX", "60"]
      assert String.set("k", "v", px: 5000, nx: true) == ["SET", "k", "v", "PX", "5000", "NX"]
    end

    test "MGET" do
      assert String.mget(["a", "b", "c"]) == ["MGET", "a", "b", "c"]
    end

    test "INCR" do
      assert String.incr("counter") == ["INCR", "counter"]
    end
  end

  describe "Hash commands" do
    test "HSET" do
      assert Hash.hset("h", [{"f1", "v1"}, {"f2", "v2"}]) == ["HSET", "h", "f1", "v1", "f2", "v2"]
    end

    test "HGETALL" do
      assert Hash.hgetall("h") == ["HGETALL", "h"]
    end
  end

  describe "List commands" do
    test "LPUSH" do
      assert List.lpush("l", ["a", "b"]) == ["LPUSH", "l", "a", "b"]
    end

    test "LRANGE" do
      assert List.lrange("l", 0, -1) == ["LRANGE", "l", "0", "-1"]
    end
  end

  describe "Set commands" do
    test "SADD" do
      assert Set.sadd("s", ["a", "b"]) == ["SADD", "s", "a", "b"]
    end

    test "SMEMBERS" do
      assert Set.smembers("s") == ["SMEMBERS", "s"]
    end
  end

  describe "SortedSet commands" do
    test "ZADD" do
      assert SortedSet.zadd("z", [{1.0, "a"}, {2.0, "b"}]) ==
               ["ZADD", "z", "1.0", "a", "2.0", "b"]
    end

    test "ZADD with options" do
      assert SortedSet.zadd("z", [{1.0, "a"}], nx: true, gt: true) ==
               ["ZADD", "z", "NX", "GT", "1.0", "a"]
    end
  end

  describe "Key commands" do
    test "DEL" do
      assert Key.del(["a", "b"]) == ["DEL", "a", "b"]
    end

    test "SCAN" do
      assert Key.scan(0, match: "user:*", count: 100) ==
               ["SCAN", "0", "MATCH", "user:*", "COUNT", "100"]
    end
  end

  describe "Stream commands" do
    test "XADD" do
      assert Stream.xadd("s", "*", [{"field", "value"}]) ==
               ["XADD", "s", "*", "field", "value"]
    end

    test "XADD with MAXLEN" do
      assert Stream.xadd("s", "*", [{"f", "v"}], maxlen: 1000) ==
               ["XADD", "s", "MAXLEN", "~", "1000", "*", "f", "v"]
    end
  end

  describe "Server commands" do
    test "PING" do
      assert Server.ping() == ["PING"]
      assert Server.ping("hello") == ["PING", "hello"]
    end

    test "INFO" do
      assert Server.info() == ["INFO"]
      assert Server.info("server") == ["INFO", "server"]
    end
  end
end

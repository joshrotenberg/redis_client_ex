defmodule Redis.Commands.StreamExpandedTest do
  use ExUnit.Case, async: true

  alias Redis.Commands.Stream

  describe "XADD" do
    test "basic with default id" do
      assert Stream.xadd("stream", [{"field", "value"}]) ==
               ["XADD", "stream", "*", "field", "value"]
    end

    test "with explicit id" do
      assert Stream.xadd("stream", "1-0", [{"f", "v"}]) ==
               ["XADD", "stream", "1-0", "f", "v"]
    end

    test "with maxlen" do
      assert Stream.xadd("stream", "*", [{"f", "v"}], maxlen: 1000) ==
               ["XADD", "stream", "MAXLEN", "~", "1000", "*", "f", "v"]
    end
  end

  describe "XLEN" do
    test "basic" do
      assert Stream.xlen("stream") == ["XLEN", "stream"]
    end
  end

  describe "XRANGE" do
    test "basic" do
      assert Stream.xrange("stream") == ["XRANGE", "stream", "-", "+"]
    end

    test "with count" do
      assert Stream.xrange("stream", "-", "+", count: 10) ==
               ["XRANGE", "stream", "-", "+", "COUNT", "10"]
    end
  end

  describe "XREAD" do
    test "basic" do
      assert Stream.xread(streams: [{"s1", "0"}, {"s2", "0"}]) ==
               ["XREAD", "STREAMS", "s1", "s2", "0", "0"]
    end

    test "with count and block" do
      cmd = Stream.xread(count: 10, block: 5000, streams: [{"s1", "$"}])
      assert cmd == ["XREAD", "COUNT", "10", "BLOCK", "5000", "STREAMS", "s1", "$"]
    end
  end

  describe "XACK" do
    test "basic" do
      assert Stream.xack("stream", "group", ["1-0", "2-0"]) ==
               ["XACK", "stream", "group", "1-0", "2-0"]
    end
  end

  describe "XDEL" do
    test "basic" do
      assert Stream.xdel("stream", ["1-0", "2-0"]) == ["XDEL", "stream", "1-0", "2-0"]
    end
  end

  describe "XREVRANGE" do
    test "basic" do
      assert Stream.xrevrange("stream") == ["XREVRANGE", "stream", "+", "-"]
    end

    test "with count" do
      assert Stream.xrevrange("stream", "+", "-", count: 5) ==
               ["XREVRANGE", "stream", "+", "-", "COUNT", "5"]
    end
  end

  describe "XTRIM" do
    test "with maxlen" do
      assert Stream.xtrim("stream", maxlen: 1000) ==
               ["XTRIM", "stream", "MAXLEN", "~", "1000"]
    end

    test "with minid" do
      assert Stream.xtrim("stream", minid: "1-0") ==
               ["XTRIM", "stream", "MINID", "~", "1-0"]
    end
  end

  describe "XCLAIM" do
    test "basic" do
      assert Stream.xclaim("stream", "group", "consumer", 60_000, ["1-0", "2-0"]) ==
               ["XCLAIM", "stream", "group", "consumer", "60000", "1-0", "2-0"]
    end

    test "with idle and force and justid" do
      cmd = Stream.xclaim("stream", "g", "c", 0, ["1-0"], idle: 5000, force: true, justid: true)
      assert "IDLE" in cmd
      assert "FORCE" in cmd
      assert "JUSTID" in cmd
    end
  end

  describe "XAUTOCLAIM" do
    test "basic" do
      assert Stream.xautoclaim("stream", "group", "consumer", 60_000, "0-0") ==
               ["XAUTOCLAIM", "stream", "group", "consumer", "60000", "0-0"]
    end

    test "with count and justid" do
      cmd = Stream.xautoclaim("stream", "g", "c", 0, "0-0", count: 10, justid: true)
      assert cmd == ["XAUTOCLAIM", "stream", "g", "c", "0", "0-0", "COUNT", "10", "JUSTID"]
    end
  end

  describe "XPENDING" do
    test "basic" do
      assert Stream.xpending("stream", "group") == ["XPENDING", "stream", "group"]
    end

    test "with range and count" do
      assert Stream.xpending("stream", "group", start: "-", end: "+", count: 10) ==
               ["XPENDING", "stream", "group", "-", "+", "10"]
    end

    test "with idle and consumer" do
      cmd =
        Stream.xpending("stream", "group",
          idle: 5000,
          start: "-",
          end: "+",
          count: 10,
          consumer: "c1"
        )

      assert "IDLE" in cmd
      assert "c1" in cmd
    end
  end

  describe "XREADGROUP" do
    test "basic" do
      cmd = Stream.xreadgroup("group", "consumer", streams: [{"s1", ">"}])
      assert cmd == ["XREADGROUP", "GROUP", "group", "consumer", "STREAMS", "s1", ">"]
    end

    test "with count, block, noack" do
      cmd =
        Stream.xreadgroup("g", "c", count: 10, block: 5000, noack: true, streams: [{"s1", ">"}])

      assert "COUNT" in cmd
      assert "BLOCK" in cmd
      assert "NOACK" in cmd
    end
  end

  describe "XGROUP CREATE" do
    test "basic" do
      assert Stream.xgroup_create("stream", "group") ==
               ["XGROUP", "CREATE", "stream", "group", "$"]
    end

    test "with explicit id" do
      assert Stream.xgroup_create("stream", "group", "0") ==
               ["XGROUP", "CREATE", "stream", "group", "0"]
    end

    test "with mkstream" do
      assert Stream.xgroup_create("stream", "group", "$", mkstream: true) ==
               ["XGROUP", "CREATE", "stream", "group", "$", "MKSTREAM"]
    end
  end

  describe "XGROUP CREATECONSUMER" do
    test "basic" do
      assert Stream.xgroup_createconsumer("stream", "group", "consumer") ==
               ["XGROUP", "CREATECONSUMER", "stream", "group", "consumer"]
    end
  end

  describe "XGROUP DELCONSUMER" do
    test "basic" do
      assert Stream.xgroup_delconsumer("stream", "group", "consumer") ==
               ["XGROUP", "DELCONSUMER", "stream", "group", "consumer"]
    end
  end

  describe "XGROUP DESTROY" do
    test "basic" do
      assert Stream.xgroup_destroy("stream", "group") ==
               ["XGROUP", "DESTROY", "stream", "group"]
    end
  end

  describe "XGROUP SETID" do
    test "basic" do
      assert Stream.xgroup_setid("stream", "group", "0") ==
               ["XGROUP", "SETID", "stream", "group", "0"]
    end
  end

  describe "XINFO CONSUMERS" do
    test "basic" do
      assert Stream.xinfo_consumers("stream", "group") ==
               ["XINFO", "CONSUMERS", "stream", "group"]
    end
  end

  describe "XINFO GROUPS" do
    test "basic" do
      assert Stream.xinfo_groups("stream") == ["XINFO", "GROUPS", "stream"]
    end
  end

  describe "XINFO STREAM" do
    test "basic" do
      assert Stream.xinfo_stream("stream") == ["XINFO", "STREAM", "stream"]
    end

    test "with FULL" do
      assert Stream.xinfo_stream("stream", full: true) ==
               ["XINFO", "STREAM", "stream", "FULL"]
    end
  end

  describe "XSETID" do
    test "basic" do
      assert Stream.xsetid("stream", "1-0") == ["XSETID", "stream", "1-0"]
    end

    test "with entriesadded and maxdeletedid" do
      assert Stream.xsetid("stream", "1-0", entriesadded: 100, maxdeletedid: "0-5") ==
               ["XSETID", "stream", "1-0", "ENTRIESADDED", "100", "MAXDELETEDID", "0-5"]
    end
  end
end

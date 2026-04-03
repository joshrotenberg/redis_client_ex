defmodule Redis.Commands.KeyExpandedTest do
  use ExUnit.Case, async: true

  alias Redis.Commands.Key

  describe "DEL" do
    test "basic" do
      assert Key.del(["k1", "k2"]) == ["DEL", "k1", "k2"]
    end
  end

  describe "EXISTS" do
    test "basic" do
      assert Key.exists(["k1", "k2"]) == ["EXISTS", "k1", "k2"]
    end
  end

  describe "EXPIRE" do
    test "basic" do
      assert Key.expire("key", 60) == ["EXPIRE", "key", "60"]
    end

    test "with NX" do
      assert Key.expire("key", 60, nx: true) == ["EXPIRE", "key", "60", "NX"]
    end
  end

  describe "TTL" do
    test "basic" do
      assert Key.ttl("key") == ["TTL", "key"]
    end
  end

  describe "TYPE" do
    test "basic" do
      assert Key.type("key") == ["TYPE", "key"]
    end
  end

  describe "SCAN" do
    test "basic" do
      assert Key.scan(0) == ["SCAN", "0"]
    end

    test "with match, count, type" do
      assert Key.scan(0, match: "user:*", count: 100, type: "string") ==
               ["SCAN", "0", "MATCH", "user:*", "COUNT", "100", "TYPE", "string"]
    end
  end

  describe "COPY" do
    test "basic" do
      assert Key.copy("src", "dst") == ["COPY", "src", "dst"]
    end

    test "with db and replace" do
      assert Key.copy("src", "dst", db: 1, replace: true) ==
               ["COPY", "src", "dst", "DB", "1", "REPLACE"]
    end
  end

  describe "DUMP" do
    test "basic" do
      assert Key.dump("key") == ["DUMP", "key"]
    end
  end

  describe "EXPIREAT" do
    test "basic" do
      assert Key.expireat("key", 1_672_531_200) == ["EXPIREAT", "key", "1672531200"]
    end

    test "with NX" do
      assert Key.expireat("key", 1_672_531_200, nx: true) ==
               ["EXPIREAT", "key", "1672531200", "NX"]
    end
  end

  describe "EXPIRETIME" do
    test "basic" do
      assert Key.expiretime("key") == ["EXPIRETIME", "key"]
    end
  end

  describe "KEYS" do
    test "basic" do
      assert Key.keys("*") == ["KEYS", "*"]
    end
  end

  describe "OBJECT ENCODING" do
    test "basic" do
      assert Key.object_encoding("key") == ["OBJECT", "ENCODING", "key"]
    end
  end

  describe "OBJECT FREQ" do
    test "basic" do
      assert Key.object_freq("key") == ["OBJECT", "FREQ", "key"]
    end
  end

  describe "OBJECT IDLETIME" do
    test "basic" do
      assert Key.object_idletime("key") == ["OBJECT", "IDLETIME", "key"]
    end
  end

  describe "PERSIST" do
    test "basic" do
      assert Key.persist("key") == ["PERSIST", "key"]
    end
  end

  describe "PEXPIRE" do
    test "basic" do
      assert Key.pexpire("key", 5000) == ["PEXPIRE", "key", "5000"]
    end

    test "with NX" do
      assert Key.pexpire("key", 5000, nx: true) == ["PEXPIRE", "key", "5000", "NX"]
    end
  end

  describe "PEXPIREAT" do
    test "basic" do
      assert Key.pexpireat("key", 1_672_531_200_000) == ["PEXPIREAT", "key", "1672531200000"]
    end

    test "with NX" do
      assert Key.pexpireat("key", 1_672_531_200_000, nx: true) ==
               ["PEXPIREAT", "key", "1672531200000", "NX"]
    end
  end

  describe "PEXPIRETIME" do
    test "basic" do
      assert Key.pexpiretime("key") == ["PEXPIRETIME", "key"]
    end
  end

  describe "PTTL" do
    test "basic" do
      assert Key.pttl("key") == ["PTTL", "key"]
    end
  end

  describe "RANDOMKEY" do
    test "basic" do
      assert Key.randomkey() == ["RANDOMKEY"]
    end
  end

  describe "RENAME" do
    test "basic" do
      assert Key.rename("old", "new") == ["RENAME", "old", "new"]
    end
  end

  describe "RENAMENX" do
    test "basic" do
      assert Key.renamenx("old", "new") == ["RENAMENX", "old", "new"]
    end
  end

  describe "RESTORE" do
    test "basic" do
      assert Key.restore("key", 0, "data") == ["RESTORE", "key", "0", "data"]
    end

    test "with replace and absttl" do
      assert Key.restore("key", 0, "data", replace: true, absttl: true) ==
               ["RESTORE", "key", "0", "data", "REPLACE", "ABSTTL"]
    end

    test "with idletime and freq" do
      assert Key.restore("key", 0, "data", idletime: 100, freq: 5) ==
               ["RESTORE", "key", "0", "data", "IDLETIME", "100", "FREQ", "5"]
    end
  end

  describe "SORT" do
    test "basic" do
      assert Key.sort("key") == ["SORT", "key"]
    end

    test "with by, limit, get, desc, alpha, store" do
      cmd =
        Key.sort("key",
          by: "weight_*",
          limit: {0, 10},
          get: ["#", "obj_*"],
          desc: true,
          alpha: true,
          store: "dest"
        )

      assert cmd == [
               "SORT",
               "key",
               "BY",
               "weight_*",
               "LIMIT",
               "0",
               "10",
               "GET",
               "#",
               "GET",
               "obj_*",
               "DESC",
               "ALPHA",
               "STORE",
               "dest"
             ]
    end
  end

  describe "SORT_RO" do
    test "basic" do
      assert Key.sort_ro("key") == ["SORT_RO", "key"]
    end

    test "with options" do
      cmd = Key.sort_ro("key", by: "nosort", alpha: true, asc: true)
      assert cmd == ["SORT_RO", "key", "BY", "nosort", "ASC", "ALPHA"]
    end
  end

  describe "TOUCH" do
    test "basic" do
      assert Key.touch(["k1", "k2"]) == ["TOUCH", "k1", "k2"]
    end
  end

  describe "UNLINK" do
    test "basic" do
      assert Key.unlink(["k1", "k2"]) == ["UNLINK", "k1", "k2"]
    end
  end

  describe "WAIT" do
    test "basic" do
      assert Key.wait(1, 5000) == ["WAIT", "1", "5000"]
    end
  end

  describe "MIGRATE" do
    test "basic" do
      assert Key.migrate("127.0.0.1", 6379, "key", 0, 5000) ==
               ["MIGRATE", "127.0.0.1", "6379", "key", "0", "5000"]
    end

    test "with copy and replace" do
      assert Key.migrate("host", 6379, "key", 0, 1000, copy: true, replace: true) ==
               ["MIGRATE", "host", "6379", "key", "0", "1000", "COPY", "REPLACE"]
    end

    test "with auth" do
      assert Key.migrate("host", 6379, "key", 0, 1000, auth: "pass") ==
               ["MIGRATE", "host", "6379", "key", "0", "1000", "AUTH", "pass"]
    end

    test "with auth2" do
      assert Key.migrate("host", 6379, "key", 0, 1000, auth2: {"user", "pass"}) ==
               ["MIGRATE", "host", "6379", "key", "0", "1000", "AUTH2", "user", "pass"]
    end

    test "with keys" do
      assert Key.migrate("host", 6379, "", 0, 1000, keys: ["k1", "k2"]) ==
               ["MIGRATE", "host", "6379", "", "0", "1000", "KEYS", "k1", "k2"]
    end
  end
end

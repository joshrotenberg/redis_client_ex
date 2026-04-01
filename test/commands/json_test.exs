defmodule Redis.Commands.JSONTest do
  use ExUnit.Case, async: true

  alias Redis.Commands.JSON

  describe "core" do
    test "SET with map" do
      cmd = JSON.set("key", %{name: "Alice"})
      assert ["JSON.SET", "key", "$", json] = cmd
      assert json =~ "Alice"
    end

    test "SET with path and NX" do
      cmd = JSON.set("key", 42, path: "$.age", nx: true)
      assert cmd == ["JSON.SET", "key", "$.age", "42", "NX"]
    end

    test "SET raw JSON" do
      cmd = JSON.set("key", ~s({"raw":true}), raw: true)
      assert cmd == ["JSON.SET", "key", "$", ~s({"raw":true})]
    end

    test "GET default path" do
      assert JSON.get("key") == ["JSON.GET", "key", "$"]
    end

    test "GET multiple paths" do
      assert JSON.get("key", paths: ["$.a", "$.b"]) == ["JSON.GET", "key", "$.a", "$.b"]
    end

    test "MGET" do
      assert JSON.mget(["k1", "k2"], "$.name") == ["JSON.MGET", "k1", "k2", "$.name"]
    end

    test "DEL" do
      assert JSON.del("key", "$.old") == ["JSON.DEL", "key", "$.old"]
    end

    test "TYPE" do
      assert JSON.type("key") == ["JSON.TYPE", "key", "$"]
    end

    test "TOGGLE" do
      assert JSON.toggle("key", "$.active") == ["JSON.TOGGLE", "key", "$.active"]
    end
  end

  describe "numeric" do
    test "NUMINCRBY" do
      assert JSON.numincrby("key", 5, "$.counter") == ["JSON.NUMINCRBY", "key", "$.counter", "5"]
    end

    test "NUMMULTBY" do
      assert JSON.nummultby("key", 2.5, "$.val") == ["JSON.NUMMULTBY", "key", "$.val", "2.5"]
    end
  end

  describe "array" do
    test "ARRAPPEND" do
      cmd = JSON.arrappend("key", ["hello", 42], "$.items")
      assert ["JSON.ARRAPPEND", "key", "$.items", "\"hello\"", "42"] = cmd
    end

    test "ARRLEN" do
      assert JSON.arrlen("key", "$.items") == ["JSON.ARRLEN", "key", "$.items"]
    end

    test "ARRPOP" do
      assert JSON.arrpop("key", "$.items") == ["JSON.ARRPOP", "key", "$.items", "-1"]
    end

    test "ARRINDEX" do
      cmd = JSON.arrindex("key", "needle", "$.items")
      assert ["JSON.ARRINDEX", "key", "$.items", "\"needle\""] = cmd
    end
  end

  describe "object" do
    test "OBJKEYS" do
      assert JSON.objkeys("key") == ["JSON.OBJKEYS", "key", "$"]
    end

    test "OBJLEN" do
      assert JSON.objlen("key", "$.nested") == ["JSON.OBJLEN", "key", "$.nested"]
    end
  end

  describe "merge" do
    test "MERGE" do
      cmd = JSON.merge("key", %{new: "field"})
      assert ["JSON.MERGE", "key", "$", json] = cmd
      assert json =~ "new"
    end
  end
end

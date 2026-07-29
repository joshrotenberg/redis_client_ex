defmodule Redis.Cluster.RouterTest do
  use ExUnit.Case, async: true

  alias Redis.Cluster.Router

  describe "slot/1" do
    test "returns a slot in range 0-16383" do
      slot = Router.slot("mykey")
      assert slot >= 0 and slot < 16_384
    end

    test "same key always returns same slot" do
      assert Router.slot("foo") == Router.slot("foo")
    end

    test "different keys can map to different slots" do
      # These are different enough to very likely hash differently
      slots = Enum.map(1..100, &Router.slot("key:#{&1}")) |> Enum.uniq()
      assert length(slots) > 1
    end

    test "hash tags override key hashing" do
      # {user}.name and {user}.email should hash to same slot
      assert Router.slot("{user}.name") == Router.slot("{user}.email")
    end

    test "empty hash tag is ignored" do
      # {} should not be treated as a hash tag
      refute Router.slot("{}key") == Router.slot("{user}key")
    end

    test "known CRC16 values" do
      # Verified against redis-cli CLUSTER KEYSLOT
      assert Router.slot("foo") == 12_182
      assert Router.slot("bar") == 5061
      assert Router.slot("hello") == 866
    end
  end

  describe "keys_from_command/1" do
    test "extracts keys from common multi-key commands" do
      assert Router.keys_from_command(["MGET", "a", "b"]) == ["a", "b"]
      assert Router.keys_from_command(["MSET", "a", "1", "b", "2"]) == ["a", "b"]
      assert Router.keys_from_command(["RENAME", "old", "new"]) == ["old", "new"]
    end

    test "extracts declared keys from scripts and functions" do
      assert Router.keys_from_command(["EVAL", "return 1", "2", "a", "b", "arg"]) == [
               "a",
               "b"
             ]

      assert Router.keys_from_command(["FCALL", "my_fn", "1", "key", "arg"]) == ["key"]
    end

    test "extracts stream keys from XREAD variants" do
      assert Router.keys_from_command([
               "XREAD",
               "COUNT",
               "2",
               "STREAMS",
               "stream:a",
               "stream:b",
               "0",
               "0"
             ]) == ["stream:a", "stream:b"]

      assert Router.keys_from_command([
               "XREADGROUP",
               "GROUP",
               "g",
               "c",
               "STREAMS",
               "stream:a",
               ">"
             ]) == ["stream:a"]
    end

    test "routes option-bearing stream reads by keys after STREAMS" do
      stream = "events:{6eo}set"

      xread = [
        "XREAD",
        "COUNT",
        "1",
        "BLOCK",
        "10",
        "STREAMS",
        stream,
        "0-0"
      ]

      xreadgroup = [
        "XREADGROUP",
        "GROUP",
        "workers",
        "one",
        "COUNT",
        "1",
        "BLOCK",
        "10",
        "NOACK",
        "STREAMS",
        stream,
        ">"
      ]

      assert Router.key_from_command(xread) == stream
      assert Router.key_from_command(xreadgroup) == stream
      assert Router.slot_for_command(xread) == {:ok, Router.slot(stream)}
      refute Router.slot(stream) == Router.slot("COUNT")
    end

    test "recognizes key-less commands with arguments" do
      assert Router.keys_from_command(["SCAN", "0", "MATCH", "*"]) == []
      assert Router.keys_from_command(["CLIENT", "SETNAME", "app"]) == []
      assert Router.keys_from_command(["MEMORY", "STATS"]) == []
      assert Router.keys_from_command(["MEMORY", "USAGE", "key"]) == ["key"]
    end
  end

  describe "slot_for_command/1" do
    test "accepts multi-key commands whose keys share a hash slot" do
      assert {:ok, _slot} = Router.slot_for_command(["MGET", "{user}.name", "{user}.email"])
    end

    test "rejects a multi-key command spanning slots" do
      assert {:error, :cross_slot} = Router.slot_for_command(["MGET", "key:a", "key:b"])

      assert {:error, :cross_slot} =
               Router.slot_for_command([
                 "XREAD",
                 "COUNT",
                 "1",
                 "STREAMS",
                 "events:{06S}set",
                 "events:{6eo}set",
                 "0-0",
                 "0-0"
               ])
    end

    test "reports key-less commands" do
      assert {:error, :no_key} = Router.slot_for_command(["SCAN", "0"])
    end
  end

  describe "validate_pipeline/1" do
    test "distinguishes empty from key-less pipelines" do
      assert {:error, :empty} = Router.validate_pipeline([])
      assert {:error, :no_key} = Router.validate_pipeline([["PING"], ["SCAN", "0"]])
    end

    test "rejects a single cross-slot command" do
      assert {:error, :cross_slot} = Router.validate_pipeline([["MGET", "key:a", "key:b"]])
    end
  end
end

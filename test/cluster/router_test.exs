defmodule Redis.Cluster.RouterTest do
  use ExUnit.Case, async: true

  alias Redis.Cluster.Router

  describe "slot/1" do
    test "returns a slot in range 0-16383" do
      slot = Router.slot("mykey")
      assert slot >= 0 and slot < 16384
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
      assert Router.slot("foo") == 12182
      assert Router.slot("bar") == 5061
      assert Router.slot("hello") == 866
    end
  end
end

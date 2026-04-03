defmodule Redis.Commands.PubSubCmdsTest do
  use ExUnit.Case, async: true

  alias Redis.Commands.PubSub

  describe "PUBLISH" do
    test "basic" do
      assert PubSub.publish("channel", "hello") == ["PUBLISH", "channel", "hello"]
    end
  end

  describe "SPUBLISH" do
    test "basic" do
      assert PubSub.spublish("shard", "msg") == ["SPUBLISH", "shard", "msg"]
    end
  end

  describe "PUBSUB CHANNELS" do
    test "without pattern" do
      assert PubSub.pubsub_channels() == ["PUBSUB", "CHANNELS"]
    end

    test "with pattern" do
      assert PubSub.pubsub_channels(pattern: "news.*") == ["PUBSUB", "CHANNELS", "news.*"]
    end
  end

  describe "PUBSUB NUMSUB" do
    test "without channels" do
      assert PubSub.pubsub_numsub() == ["PUBSUB", "NUMSUB"]
    end

    test "with channels" do
      assert PubSub.pubsub_numsub(["ch1", "ch2"]) == ["PUBSUB", "NUMSUB", "ch1", "ch2"]
    end
  end

  describe "PUBSUB NUMPAT" do
    test "basic" do
      assert PubSub.pubsub_numpat() == ["PUBSUB", "NUMPAT"]
    end
  end

  describe "PUBSUB SHARDCHANNELS" do
    test "without pattern" do
      assert PubSub.pubsub_shardchannels() == ["PUBSUB", "SHARDCHANNELS"]
    end

    test "with pattern" do
      assert PubSub.pubsub_shardchannels(pattern: "shard.*") == [
               "PUBSUB",
               "SHARDCHANNELS",
               "shard.*"
             ]
    end
  end

  describe "PUBSUB SHARDNUMSUB" do
    test "without channels" do
      assert PubSub.pubsub_shardnumsub() == ["PUBSUB", "SHARDNUMSUB"]
    end

    test "with channels" do
      assert PubSub.pubsub_shardnumsub(["s1", "s2"]) == ["PUBSUB", "SHARDNUMSUB", "s1", "s2"]
    end
  end
end

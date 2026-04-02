defmodule Redis.Commands.PubSub do
  @moduledoc """
  Command builders for Redis Pub/Sub introspection and publishing.

  This module provides pure functions that return Redis command lists for
  publishing messages and inspecting Pub/Sub state. These commands can be
  issued over a regular connection (unlike SUBSCRIBE/PSUBSCRIBE which require
  a dedicated Pub/Sub connection).

  All functions return a command list (e.g. `["PUBLISH", "chan", "msg"]`) and
  are intended for use with `Redis.command/2` or `Redis.pipeline/2`.

  ## Examples

      # Publish a message to a channel
      Redis.command(conn, PubSub.publish("events", "user_signed_up"))

      # List active channels matching a pattern
      Redis.command(conn, PubSub.pubsub_channels(pattern: "events:*"))

      # Get subscriber counts for specific channels
      Redis.command(conn, PubSub.pubsub_numsub(["events:login", "events:logout"]))

      # Publish to a shard channel (Redis 7+)
      Redis.command(conn, PubSub.spublish("orders:{us-east}", "new_order"))
  """

  @doc """
  PUBLISH -- post a message to a channel.

  Returns the number of clients that received the message.

      PubSub.publish("notifications", "hello")
      #=> ["PUBLISH", "notifications", "hello"]
  """
  @spec publish(String.t(), String.t()) :: [String.t()]
  def publish(channel, message), do: ["PUBLISH", channel, message]

  @doc """
  SPUBLISH -- post a message to a shard channel (Redis 7+).

  Similar to `publish/2` but targets shard channels, which are routed only
  to the cluster node owning the shard.

      PubSub.spublish("orders:{us-east}", "new_order")
      #=> ["SPUBLISH", "orders:{us-east}", "new_order"]
  """
  @spec spublish(String.t(), String.t()) :: [String.t()]
  def spublish(shardchannel, message), do: ["SPUBLISH", shardchannel, message]

  @doc """
  PUBSUB CHANNELS -- list active channels, optionally filtered by a glob pattern.

      PubSub.pubsub_channels()                        #=> ["PUBSUB", "CHANNELS"]
      PubSub.pubsub_channels(pattern: "events:*")     #=> ["PUBSUB", "CHANNELS", "events:*"]
  """
  @spec pubsub_channels(keyword()) :: [String.t()]
  def pubsub_channels(opts \\ []) do
    cmd = ["PUBSUB", "CHANNELS"]
    if opts[:pattern], do: cmd ++ [opts[:pattern]], else: cmd
  end

  @doc """
  PUBSUB NUMSUB -- get the subscriber count for the given channels.

  Returns a flat list of channel/count pairs.

      PubSub.pubsub_numsub(["ch1", "ch2"])
      #=> ["PUBSUB", "NUMSUB", "ch1", "ch2"]
  """
  @spec pubsub_numsub([String.t()]) :: [String.t()]
  def pubsub_numsub(channels \\ []) when is_list(channels) do
    ["PUBSUB", "NUMSUB" | channels]
  end

  @spec pubsub_numpat() :: [String.t()]
  def pubsub_numpat, do: ["PUBSUB", "NUMPAT"]

  @spec pubsub_shardchannels(keyword()) :: [String.t()]
  def pubsub_shardchannels(opts \\ []) do
    cmd = ["PUBSUB", "SHARDCHANNELS"]
    if opts[:pattern], do: cmd ++ [opts[:pattern]], else: cmd
  end

  @spec pubsub_shardnumsub([String.t()]) :: [String.t()]
  def pubsub_shardnumsub(channels \\ []) when is_list(channels) do
    ["PUBSUB", "SHARDNUMSUB" | channels]
  end
end

defmodule Redis.Commands.PubSub do
  @moduledoc """
  Command builders for Redis pub/sub operations usable from regular connections.
  """

  @spec publish(String.t(), String.t()) :: [String.t()]
  def publish(channel, message), do: ["PUBLISH", channel, message]

  @spec spublish(String.t(), String.t()) :: [String.t()]
  def spublish(shardchannel, message), do: ["SPUBLISH", shardchannel, message]

  @spec pubsub_channels(keyword()) :: [String.t()]
  def pubsub_channels(opts \\ []) do
    cmd = ["PUBSUB", "CHANNELS"]
    if opts[:pattern], do: cmd ++ [opts[:pattern]], else: cmd
  end

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

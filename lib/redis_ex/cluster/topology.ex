defmodule RedisEx.Cluster.Topology do
  @moduledoc """
  Parses CLUSTER SLOTS responses into a slot-to-node mapping.
  """

  @type node_addr :: {String.t(), non_neg_integer()}

  @doc """
  Parses the response from CLUSTER SLOTS into a list of
  `{slot_start, slot_end, primary_host, primary_port}` tuples.

  CLUSTER SLOTS returns an array of:
    [start_slot, end_slot, [master_host, master_port, ...], [replica_host, replica_port, ...], ...]
  """
  @spec parse_slots(list()) :: [{non_neg_integer(), non_neg_integer(), String.t(), non_neg_integer()}]
  def parse_slots(slots_response) when is_list(slots_response) do
    Enum.flat_map(slots_response, fn
      [start_slot, end_slot, [host, port | _] | _replicas] when is_integer(start_slot) ->
        # Host might be empty string for the node we're connected to
        host = if host == "", do: "127.0.0.1", else: host
        [{start_slot, end_slot, host, port}]

      _ ->
        []
    end)
  end

  @doc """
  Builds an ETS-friendly list of `{slot, {host, port}}` entries from parsed slot ranges.
  """
  @spec build_slot_map([{non_neg_integer(), non_neg_integer(), String.t(), non_neg_integer()}]) ::
          [{non_neg_integer(), {String.t(), non_neg_integer()}}]
  def build_slot_map(parsed_slots) do
    Enum.flat_map(parsed_slots, fn {start_slot, end_slot, host, port} ->
      for slot <- start_slot..end_slot do
        {slot, {host, port}}
      end
    end)
  end
end

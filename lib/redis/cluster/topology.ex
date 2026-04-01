defmodule Redis.Cluster.Topology do
  @moduledoc """
  Parses CLUSTER SLOTS responses into slot-to-node mappings.
  """

  @type node_addr :: {String.t(), non_neg_integer()}

  @doc """
  Parses the response from CLUSTER SLOTS into a list of
  `{slot_start, slot_end, primary_host, primary_port}` tuples.
  """
  @spec parse_slots(list()) :: [{non_neg_integer(), non_neg_integer(), String.t(), non_neg_integer()}]
  def parse_slots(slots_response) when is_list(slots_response) do
    Enum.flat_map(slots_response, fn
      [start_slot, end_slot, [host, port | _] | _replicas] when is_integer(start_slot) ->
        host = if host == "", do: "127.0.0.1", else: host
        [{start_slot, end_slot, host, port}]

      _ ->
        []
    end)
  end

  @doc """
  Parses CLUSTER SLOTS into a richer format that includes replicas.
  Returns `[{slot_start, slot_end, {primary_host, primary_port}, [{replica_host, replica_port}]}]`
  """
  @spec parse_slots_with_replicas(list()) ::
          [{non_neg_integer(), non_neg_integer(), node_addr(), [node_addr()]}]
  def parse_slots_with_replicas(slots_response) when is_list(slots_response) do
    Enum.flat_map(slots_response, fn
      [start_slot, end_slot, [host, port | _] | rest] when is_integer(start_slot) ->
        host = if host == "", do: "127.0.0.1", else: host
        primary = {host, port}

        replicas =
          rest
          |> Enum.filter(&is_list/1)
          |> Enum.map(fn
            [rhost, rport | _] ->
              rhost = if rhost == "", do: "127.0.0.1", else: rhost
              {rhost, rport}
          end)

        [{start_slot, end_slot, primary, replicas}]

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

  @doc """
  Builds a replica map: `{slot => [{replica_host, replica_port}]}` from enriched topology.
  """
  @spec build_replica_map([{non_neg_integer(), non_neg_integer(), node_addr(), [node_addr()]}]) ::
          [{non_neg_integer(), [node_addr()]}]
  def build_replica_map(parsed_slots) do
    Enum.flat_map(parsed_slots, fn {start_slot, end_slot, _primary, replicas} ->
      if replicas != [] do
        for slot <- start_slot..end_slot do
          {slot, replicas}
        end
      else
        []
      end
    end)
  end
end

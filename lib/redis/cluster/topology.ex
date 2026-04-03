defmodule Redis.Cluster.Topology do
  @moduledoc """
  Parses cluster topology responses into slot-to-node mappings.

  Supports both `CLUSTER SHARDS` (Redis 7.0+, preferred) and
  `CLUSTER SLOTS` (deprecated, fallback for Redis 6.x).
  """

  @type node_addr :: {String.t(), non_neg_integer()}

  @doc """
  Parses the response from CLUSTER SLOTS into a list of
  `{slot_start, slot_end, primary_host, primary_port}` tuples.
  """
  @spec parse_slots(list()) :: [
          {non_neg_integer(), non_neg_integer(), String.t(), non_neg_integer()}
        ]
  def parse_slots(slots_response) when is_list(slots_response) do
    Enum.flat_map(slots_response, fn
      [start_slot, end_slot, [host, port | _] | _replicas] when is_integer(start_slot) ->
        [{start_slot, end_slot, normalize_host(host), port}]

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
        host = normalize_host(host)
        primary = {host, port}
        replicas = parse_replicas(rest)
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
    parsed_slots
    |> Enum.filter(fn {_start, _end, _primary, replicas} -> replicas != [] end)
    |> Enum.flat_map(fn {start_slot, end_slot, _primary, replicas} ->
      for slot <- start_slot..end_slot do
        {slot, replicas}
      end
    end)
  end

  # -------------------------------------------------------------------
  # CLUSTER SHARDS parsing (Redis 7.0+)
  # -------------------------------------------------------------------

  @doc """
  Parses the response from CLUSTER SHARDS into the same format as `parse_slots/1`.

  CLUSTER SHARDS returns a list of shard maps:

      [%{"slots" => [0, 5460], "nodes" => [%{"ip" => "127.0.0.1", "port" => 7000, "role" => "master", ...}]}]
  """
  @spec parse_shards(list()) :: [
          {non_neg_integer(), non_neg_integer(), String.t(), non_neg_integer()}
        ]
  def parse_shards(shards_response) when is_list(shards_response) do
    Enum.flat_map(shards_response, &parse_shard/1)
  end

  def parse_shards(_), do: []

  @doc """
  Parses CLUSTER SHARDS with replica info, same format as `parse_slots_with_replicas/1`.
  """
  @spec parse_shards_with_replicas(list()) ::
          [{non_neg_integer(), non_neg_integer(), node_addr(), [node_addr()]}]
  def parse_shards_with_replicas(shards_response) when is_list(shards_response) do
    Enum.flat_map(shards_response, &parse_shard_with_replicas/1)
  end

  def parse_shards_with_replicas(_), do: []

  defp parse_shard(shard) when is_map(shard) do
    slots = Map.get(shard, "slots", [])
    nodes = Map.get(shard, "nodes", [])

    case find_master(nodes) do
      {host, port} ->
        slot_ranges(slots)
        |> Enum.map(fn {start_slot, end_slot} ->
          {start_slot, end_slot, normalize_host(host), port}
        end)

      nil ->
        []
    end
  end

  defp parse_shard(_), do: []

  defp parse_shard_with_replicas(shard) when is_map(shard) do
    slots = Map.get(shard, "slots", [])
    nodes = Map.get(shard, "nodes", [])

    case find_master(nodes) do
      {host, port} ->
        primary = {normalize_host(host), port}
        replicas = find_replicas(nodes)

        slot_ranges(slots)
        |> Enum.map(fn {start_slot, end_slot} ->
          {start_slot, end_slot, primary, replicas}
        end)

      nil ->
        []
    end
  end

  defp parse_shard_with_replicas(_), do: []

  defp find_master(nodes) do
    Enum.find_value(nodes, fn
      %{"role" => "master", "ip" => ip, "port" => port} when is_integer(port) ->
        host = Map.get(%{"ip" => ip}, "endpoint", ip) |> then(&(&1 || ip))
        {host, port}

      %{"role" => "master", "ip" => ip, "port" => port} ->
        {ip, port}

      _ ->
        nil
    end)
  end

  defp find_replicas(nodes) do
    nodes
    |> Enum.filter(&(Map.get(&1, "role") == "replica"))
    |> Enum.map(fn node ->
      host = Map.get(node, "endpoint") || Map.get(node, "ip", "127.0.0.1")
      port = Map.get(node, "port")
      {normalize_host(host), port}
    end)
  end

  # Slot ranges come as flat list [start1, end1, start2, end2, ...]
  defp slot_ranges(slots) do
    slots
    |> Enum.chunk_every(2)
    |> Enum.map(fn
      [start_slot, end_slot] -> {start_slot, end_slot}
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  # -------------------------------------------------------------------
  # Shared helpers
  # -------------------------------------------------------------------

  defp normalize_host(""), do: "127.0.0.1"
  defp normalize_host(host), do: host

  defp parse_replicas(rest) do
    rest
    |> Enum.filter(&is_list/1)
    |> Enum.map(fn [rhost, rport | _] -> {normalize_host(rhost), rport} end)
  end
end

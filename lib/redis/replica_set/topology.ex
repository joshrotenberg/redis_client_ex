defmodule Redis.ReplicaSet.Topology do
  @moduledoc false

  alias Redis.Connection

  @type node_address :: {String.t(), non_neg_integer()}

  @spec discover(GenServer.server(), timeout()) ::
          {:ok, [node_address()]} | {:error, term()}
  def discover(primary, timeout \\ 5_000) do
    case Connection.command(primary, ["INFO", "REPLICATION"], timeout: timeout) do
      {:ok, info} when is_binary(info) -> parse_info(info)
      {:ok, _unexpected} -> {:error, :invalid_replication_info}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  @spec parse_info(binary()) :: {:ok, [node_address()]} | {:error, term()}
  def parse_info(info) when is_binary(info) do
    fields =
      info
      |> String.split(~r/\r?\n/, trim: true)
      |> Enum.reject(&String.starts_with?(&1, "#"))

    if Enum.any?(fields, &(&1 in ["role:master", "role:primary"])) do
      replicas =
        fields
        |> Enum.flat_map(&parse_replica_line/1)
        |> Enum.uniq()

      {:ok, replicas}
    else
      {:error, :not_primary}
    end
  end

  def parse_info(_info), do: {:error, :invalid_replication_info}

  @doc false
  @spec parse_sentinel_replicas(term()) :: [node_address()]
  def parse_sentinel_replicas(replicas) when is_list(replicas) do
    replicas
    |> Enum.flat_map(fn replica ->
      replica
      |> flat_list_to_map()
      |> sentinel_replica_address()
    end)
    |> Enum.uniq()
  end

  def parse_sentinel_replicas(_replicas), do: []

  defp parse_replica_line(line) do
    case String.split(line, ":", parts: 2) do
      [label, attributes] ->
        if String.match?(label, ~r/\A(?:slave|replica)\d+\z/) do
          attributes
          |> parse_attributes(",")
          |> info_replica_address()
        else
          []
        end

      _ ->
        []
    end
  end

  defp info_replica_address(%{"ip" => host, "port" => port, "state" => "online"}) do
    address(host, port)
  end

  defp info_replica_address(_attributes), do: []

  defp sentinel_replica_address(attributes) do
    flags = attributes |> Map.get("flags", "") |> String.split(",")
    link_status = Map.get(attributes, "master-link-status")
    unavailable_flags = ["s_down", "o_down", "disconnected"]

    if Enum.any?(flags, &(&1 in unavailable_flags)) or link_status not in [nil, "ok"] do
      []
    else
      address(Map.get(attributes, "ip"), Map.get(attributes, "port"))
    end
  end

  defp address(host, port) when is_binary(host) and host != "" and is_binary(port) do
    case Integer.parse(port) do
      {port, ""} when port in 1..65_535 -> [{host, port}]
      _ -> []
    end
  end

  defp address(_host, _port), do: []

  defp parse_attributes(data, separator) do
    data
    |> String.split(separator)
    |> Enum.reduce(%{}, fn field, attributes ->
      case String.split(field, "=", parts: 2) do
        [key, value] -> Map.put(attributes, key, value)
        _ -> attributes
      end
    end)
  end

  defp flat_list_to_map(list) when is_list(list) do
    list
    |> Enum.chunk_every(2)
    |> Map.new(fn
      [key, value] -> {key, value}
      [key] -> {key, nil}
    end)
  end

  defp flat_list_to_map(map) when is_map(map), do: map
  defp flat_list_to_map(_list), do: %{}
end

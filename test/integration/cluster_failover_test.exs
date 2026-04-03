defmodule Redis.ClusterFailoverTest do
  use ExUnit.Case, async: false

  alias Redis.Cluster
  alias Redis.Cluster.Router
  alias RedisServerWrapper.{Chaos, Server}

  @moduletag timeout: 120_000
  @moduletag :cluster_failover

  @base_port 7400

  setup_all do
    {:ok, cluster_srv} =
      RedisServerWrapper.Cluster.start_link(
        masters: 3,
        replicas_per_master: 1,
        base_port: @base_port
      )

    assert RedisServerWrapper.Cluster.healthy?(cluster_srv)

    nodes = for i <- 0..2, do: {"127.0.0.1", @base_port + i}
    {:ok, cluster} = Cluster.start_link(nodes: nodes)

    on_exit(fn ->
      try do
        Cluster.stop(cluster)
      catch
        :exit, _ -> :ok
      end

      try do
        RedisServerWrapper.Cluster.stop(cluster_srv)
      catch
        :exit, _ -> :ok
      end

      Process.sleep(1000)
    end)

    {:ok, cluster: cluster, cluster_srv: cluster_srv}
  end

  describe "failover recovery" do
    test "client recovers after clean failover (CLUSTER FAILOVER on replica)", %{
      cluster: cluster,
      cluster_srv: cluster_srv
    } do
      # Write data
      assert {:ok, "OK"} = Cluster.command(cluster, ["SET", "{failover}.key", "before"])
      assert {:ok, "before"} = Cluster.command(cluster, ["GET", "{failover}.key"])

      # Find the replica of the master owning {failover} slots
      replica = find_replica_of_key(cluster_srv, "{failover}.key")
      replica_info = Server.info(replica)
      IO.puts("Triggering clean failover on replica port #{replica_info.port}")

      # Clean failover: replica syncs from master, then swaps roles
      {:ok, "OK"} = Server.run(replica, ["CLUSTER", "FAILOVER"])
      Process.sleep(5000)

      # Verify the replica was promoted
      {:ok, role_output} = Server.run(replica, ["ROLE"])
      role = role_output |> String.split("\n") |> hd()
      IO.puts("Replica role: #{role}")
      assert role == "master"

      # Refresh client topology
      :ok = Cluster.refresh(cluster)
      Process.sleep(2000)

      # Reads should work via the new master
      assert {:ok, "before"} = Cluster.command(cluster, ["GET", "{failover}.key"])

      # Writes should work
      assert {:ok, "OK"} = Cluster.command(cluster, ["SET", "{failover}.key", "after"])
      assert {:ok, "after"} = Cluster.command(cluster, ["GET", "{failover}.key"])
    end

    test "client recovers after master kill + forced failover", %{
      cluster: cluster,
      cluster_srv: cluster_srv
    } do
      assert {:ok, "OK"} = Cluster.command(cluster, ["SET", "{kill}.key", "before"])

      # Ensure replication
      {:ok, replicas} = Cluster.command(cluster, ["WAIT", "1", "5000"])
      IO.puts("WAIT confirmed by #{inspect(replicas)} replica(s)")

      # Kill master
      {:ok, killed} = Chaos.kill_master(cluster_srv, "{kill}.key")
      killed_info = Server.info(killed)
      IO.puts("Killed master on port #{killed_info.port}")

      # Wait for failure detection
      Process.sleep(8000)

      # Force-promote the replica
      replica = find_replica_of_dead(cluster_srv, killed, killed_info.port)
      replica_info = Server.info(replica)
      IO.puts("Promoting replica on port #{replica_info.port}")
      {:ok, "OK"} = Chaos.trigger_failover(replica)
      Process.sleep(5000)

      # Refresh and verify
      :ok = Cluster.refresh(cluster)
      Process.sleep(2000)

      result = Cluster.command(cluster, ["GET", "{kill}.key"])
      IO.puts("GET after forced failover: #{inspect(result)}")
      assert {:ok, "before"} = result
    end

    test "client survives node freeze and resume", %{
      cluster: cluster,
      cluster_srv: cluster_srv
    } do
      assert {:ok, "OK"} = Cluster.command(cluster, ["SET", "{freeze}.key", "value"])

      # Find the master owning this key's slot and freeze a DIFFERENT node
      slot = Router.slot("{freeze}")
      all_nodes = RedisServerWrapper.Cluster.nodes(cluster_srv)
      {master_port, _} = find_master_for_slot(all_nodes, slot)

      target =
        Enum.find(all_nodes, fn n ->
          info = Server.info(n)
          info.port != master_port
        end)

      {:ok, os_pid} = Chaos.freeze_node(target)

      # Commands to the unfrozen master should still work
      assert {:ok, "value"} = Cluster.command(cluster, ["GET", "{freeze}.key"])

      Chaos.resume_node(os_pid)
      Process.sleep(1000)

      assert {:ok, "value"} = Cluster.command(cluster, ["GET", "{freeze}.key"])
    end

    test "client handles MOVED redirect transparently", %{cluster: cluster} do
      for i <- 1..20 do
        key = "{moved_test}:#{i}"
        assert {:ok, "OK"} = Cluster.command(cluster, ["SET", key, "val#{i}"])
      end

      Cluster.refresh(cluster)

      for i <- 1..20 do
        key = "{moved_test}:#{i}"
        expected = "val#{i}"
        assert {:ok, ^expected} = Cluster.command(cluster, ["GET", key])
      end
    end
  end

  # -------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------

  # Find the replica of the master owning a key (master is alive)
  defp find_replica_of_key(cluster_srv, key) do
    slot = Router.slot(key)
    nodes = RedisServerWrapper.Cluster.nodes(cluster_srv)
    {master_port, master_id} = find_master_for_slot(nodes, slot)

    Enum.find(nodes, fn n ->
      Server.info(n).port != master_port and node_is_slave_of?(n, master_id)
    end) || raise "No replica found for slot #{slot}"
  end

  defp node_is_slave_of?(node, master_id) do
    case get_myself_line(node) do
      nil -> false
      line -> String.contains?(Enum.at(line, 2), "slave") and Enum.at(line, 3) == master_id
    end
  end

  defp get_myself_line(node) do
    case Server.run(node, ["CLUSTER", "NODES"]) do
      {:ok, output} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.find(&String.contains?(&1, "myself"))
        |> case do
          nil -> nil
          line -> String.split(line)
        end

      _ ->
        nil
    end
  end

  defp find_master_for_slot(nodes, target_slot) do
    Enum.find_value(nodes, fn n ->
      case Server.run(n, ["CLUSTER", "NODES"]) do
        {:ok, output} -> parse_master_for_slot(output, target_slot)
        _ -> nil
      end
    end)
  end

  defp parse_master_for_slot(output, target_slot) do
    output
    |> String.split("\n", trim: true)
    |> Enum.find_value(&extract_master_if_owns_slot(&1, target_slot))
  end

  defp extract_master_if_owns_slot(line, target_slot) do
    parts = String.split(line)

    with true <- length(parts) >= 9,
         true <- String.contains?(Enum.at(parts, 2), "master"),
         {port, id} <- parse_node_addr(parts),
         true <- slot_in_ranges?(target_slot, Enum.drop(parts, 8)) do
      {port, id}
    else
      _ -> nil
    end
  end

  defp parse_node_addr(parts) do
    id = hd(parts)
    [host_port | _] = String.split(Enum.at(parts, 1), "@")
    [_host, port_str] = String.split(host_port, ":")
    {String.to_integer(port_str), id}
  end

  # Find the replica of a dead master (master already killed)
  defp find_replica_of_dead(cluster_srv, killed, dead_port) do
    surviving = RedisServerWrapper.Cluster.nodes(cluster_srv) |> Enum.reject(&(&1 == killed))

    # Query CLUSTER NODES from any reachable surviving node
    cn = get_cluster_nodes_from_any(surviving)

    dead_id =
      cn
      |> String.split("\n", trim: true)
      |> Enum.find_value(fn line ->
        if String.contains?(line, ":#{dead_port}@"), do: line |> String.split() |> hd()
      end)

    replica_port =
      cn
      |> String.split("\n", trim: true)
      |> Enum.find_value(fn line ->
        parts = String.split(line)

        if length(parts) >= 4 and String.contains?(Enum.at(parts, 2), "slave") and
             Enum.at(parts, 3) == dead_id do
          Enum.at(parts, 1) |> parse_port_from_addr()
        end
      end)

    Enum.find(surviving, fn n ->
      try do
        Server.info(n).port == replica_port
      catch
        :exit, _ -> false
      end
    end) || raise "Could not find replica of dead master on port #{dead_port}"
  end

  defp get_cluster_nodes_from_any(nodes) do
    Enum.find_value(nodes, fn n ->
      try do
        case Server.run(n, ["CLUSTER", "NODES"]) do
          {:ok, output} -> output
          _ -> nil
        end
      catch
        :exit, _ -> nil
      end
    end) || raise "No reachable nodes"
  end

  defp parse_port_from_addr(addr) do
    [host_port | _] = String.split(addr, "@")
    [_host, port_str] = String.split(host_port, ":")
    String.to_integer(port_str)
  end

  defp slot_in_ranges?(slot, ranges) do
    Enum.any?(ranges, fn range ->
      case String.split(range, "-") do
        [s, e] -> slot >= String.to_integer(s) and slot <= String.to_integer(e)
        [s] -> String.to_integer(s) == slot
        _ -> false
      end
    end)
  end
end

defmodule Redis.ClusterFailoverTest do
  use ExUnit.Case, async: false

  alias Redis.Cluster
  alias Redis.Cluster.Router
  alias Redis.Connection

  @moduletag timeout: 120_000
  @moduletag :cluster_failover

  # 3 masters + 1 replica each = 6 nodes
  @base_port 7400
  @masters 3
  @replicas 1

  setup_all do
    {:ok, cluster_srv} =
      RedisServerWrapper.Cluster.start_link(
        masters: @masters,
        replicas_per_master: @replicas,
        base_port: @base_port
      )

    assert RedisServerWrapper.Cluster.healthy?(cluster_srv)

    nodes =
      for i <- 0..(@masters - 1) do
        {"127.0.0.1", @base_port + i}
      end

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
    test "client recovers after a master node is killed", %{
      cluster: cluster,
      cluster_srv: cluster_srv
    } do
      # Write some data
      assert {:ok, "OK"} = Cluster.command(cluster, ["SET", "{failover}.key", "before"])
      assert {:ok, "before"} = Cluster.command(cluster, ["GET", "{failover}.key"])

      # Find which node owns the slot for {failover}
      slot = Router.slot("{failover}")
      IO.puts("Slot for {failover}: #{slot}")

      # Get all node pids from the wrapper
      node_pids = RedisServerWrapper.Cluster.nodes(cluster_srv)
      IO.puts("Cluster has #{length(node_pids)} nodes")

      # Find the master for this slot by checking each node
      master_port = find_master_port_for_slot(cluster_srv, slot)
      IO.puts("Master for slot #{slot} is on port #{master_port}")

      # Find the node pid for that port and kill it
      master_pid = find_node_pid_for_port(node_pids, master_port)
      IO.puts("Killing master on port #{master_port}")
      RedisServerWrapper.Server.stop(master_pid)

      # Wait for cluster to detect the failure and promote a replica.
      # cluster-node-timeout defaults to 5000ms in the wrapper, so the
      # replica should be promoted within ~15s.
      IO.puts("Waiting for failover...")
      wait_for_cluster_healthy(cluster_srv, master_port, 30_000)

      # Force topology refresh on the client so it discovers the new master
      IO.puts("Refreshing client topology...")
      refresh_result = Cluster.refresh(cluster)
      IO.puts("Refresh result: #{inspect(refresh_result)}")

      info = Cluster.info(cluster)
      IO.puts("Cluster nodes after refresh: #{inspect(info.nodes)}")
      Process.sleep(2000)

      # The client should now be able to read the data via the promoted replica
      result = Cluster.command(cluster, ["GET", "{failover}.key"])
      IO.puts("After failover GET result: #{inspect(result)}")
      assert {:ok, "before"} = result

      # Writing should also work
      assert {:ok, "OK"} = Cluster.command(cluster, ["SET", "{failover}.key", "after"])
      assert {:ok, "after"} = Cluster.command(cluster, ["GET", "{failover}.key"])
    end

    test "client handles MOVED redirect transparently", %{cluster: cluster} do
      # First ensure the cluster is healthy (may be recovering from previous test)
      Process.sleep(2000)
      Cluster.refresh(cluster)

      # Write data
      for i <- 1..20 do
        key = "{moved_test}:#{i}"
        assert {:ok, "OK"} = Cluster.command(cluster, ["SET", key, "val#{i}"])
      end

      # Force a topology refresh (may cause stale routing temporarily)
      Cluster.refresh(cluster)

      # Reads should still work even with possibly stale routing
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

  defp wait_for_cluster_healthy(cluster_srv, dead_port, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait_healthy(cluster_srv, dead_port, deadline)
  end

  defp do_wait_healthy(cluster_srv, dead_port, deadline) do
    Process.sleep(2000)

    if System.monotonic_time(:millisecond) >= deadline do
      IO.puts("Cluster failover timed out")
      :timeout
    else
      if failover_complete?(cluster_srv, dead_port) do
        IO.puts("Cluster failover check complete")
        :ok
      else
        do_wait_healthy(cluster_srv, dead_port, deadline)
      end
    end
  end

  defp failover_complete?(cluster_srv, dead_port) do
    cluster_srv
    |> RedisServerWrapper.Cluster.nodes()
    |> Enum.any?(fn pid -> surviving_node_sees_failover?(pid, dead_port) end)
  end

  defp surviving_node_sees_failover?(pid, dead_port) do
    info = RedisServerWrapper.Server.info(pid)
    if info.port == dead_port, do: false, else: check_node_cluster_state(pid, dead_port)
  catch
    :exit, _ -> false
  end

  defp check_node_cluster_state(pid, dead_port) do
    with {:ok, nodes_output} <- RedisServerWrapper.Server.run(pid, ["CLUSTER", "NODES"]),
         {:ok, info_output} <- RedisServerWrapper.Server.run(pid, ["CLUSTER", "INFO"]) do
      dead_marked_fail =
        nodes_output
        |> String.split("\n", trim: true)
        |> Enum.all?(fn line ->
          if String.contains?(line, ":#{dead_port}@") and String.contains?(line, "master") do
            String.contains?(line, "fail")
          else
            true
          end
        end)

      dead_marked_fail and String.contains?(info_output, "cluster_state:ok")
    else
      _ -> false
    end
  end

  defp find_master_port_for_slot(cluster_srv, target_slot) do
    # Use redis-cli CLUSTER SLOTS to find which node owns the slot
    case RedisServerWrapper.Cluster.run(cluster_srv, ["CLUSTER", "SLOTS"]) do
      {:ok, output} ->
        parse_cluster_slots_for_port(output, target_slot)

      _ ->
        # Fallback: try each node directly
        node_pids = RedisServerWrapper.Cluster.nodes(cluster_srv)

        Enum.find_value(node_pids, fn pid ->
          info = RedisServerWrapper.Server.info(pid)
          port = info.port

          case RedisServerWrapper.Server.run(pid, ["CLUSTER", "SLOTS"]) do
            {:ok, _} -> port
            _ -> nil
          end
        end) || @base_port
    end
  end

  defp parse_cluster_slots_for_port(_output, target_slot) do
    # CLUSTER SLOTS output is complex — simplify by connecting directly
    # and using CLUSTER MYID + CLUSTER NODES
    # For now, use a simpler approach: connect to each node and check
    {:ok, conn} = Connection.start_link(port: @base_port)

    case Connection.command(conn, ["CLUSTER", "NODES"]) do
      {:ok, nodes_str} when is_binary(nodes_str) ->
        port = parse_nodes_for_slot(nodes_str, target_slot)
        Connection.stop(conn)
        port

      _ ->
        Connection.stop(conn)
        @base_port
    end
  end

  defp parse_nodes_for_slot(nodes_str, target_slot) do
    nodes_str
    |> String.split("\n", trim: true)
    |> Enum.find_value(fn line ->
      parts = String.split(line)
      # Format: <id> <ip:port@cport> <flags> <master> <ping> <pong> <epoch> <link> <slots...>
      if length(parts) >= 9 and "master" in String.split(Enum.at(parts, 2), ",") do
        addr = Enum.at(parts, 1)
        [host_port | _] = String.split(addr, "@")
        [_host, port_str] = String.split(host_port, ":")
        port = String.to_integer(port_str)

        slots = Enum.drop(parts, 8)

        if slot_in_ranges?(target_slot, slots) do
          port
        end
      end
    end) || @base_port
  end

  defp slot_in_ranges?(slot, ranges) do
    Enum.any?(ranges, fn range ->
      case String.split(range, "-") do
        [start_str, end_str] ->
          slot >= String.to_integer(start_str) and slot <= String.to_integer(end_str)

        [single] ->
          String.to_integer(single) == slot

        _ ->
          false
      end
    end)
  end

  defp find_node_pid_for_port(node_pids, target_port) do
    Enum.find(node_pids, fn pid ->
      info = RedisServerWrapper.Server.info(pid)
      info.port == target_port
    end)
  end
end

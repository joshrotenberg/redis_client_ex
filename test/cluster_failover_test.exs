defmodule Redis.ClusterFailoverTest do
  use ExUnit.Case, async: false

  alias Redis.Cluster
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
    test "client recovers after master kill + forced failover", %{
      cluster: cluster,
      cluster_srv: cluster_srv
    } do
      # Write data
      assert {:ok, "OK"} = Cluster.command(cluster, ["SET", "{failover}.key", "before"])
      assert {:ok, "before"} = Cluster.command(cluster, ["GET", "{failover}.key"])

      # Kill the master owning this key's slot
      {:ok, killed} = Chaos.kill_master(cluster_srv, "{failover}.key")
      killed_info = Server.info(killed)

      # Wait for the cluster to detect the failure
      Process.sleep(8000)

      # Find and promote the replica of the dead master
      promote_replica(cluster_srv, killed, killed_info.port)
      Process.sleep(5000)

      # Refresh client topology to discover the promoted replica
      :ok = Cluster.refresh(cluster)
      Process.sleep(2000)

      # Reads should work via the promoted replica
      assert {:ok, "before"} = Cluster.command(cluster, ["GET", "{failover}.key"])

      # Writes should also work
      assert {:ok, "OK"} = Cluster.command(cluster, ["SET", "{failover}.key", "after"])
      assert {:ok, "after"} = Cluster.command(cluster, ["GET", "{failover}.key"])
    end

    test "client survives node freeze and resume", %{
      cluster: cluster,
      cluster_srv: cluster_srv
    } do
      assert {:ok, "OK"} = Cluster.command(cluster, ["SET", "{freeze}.key", "value"])

      # Freeze a random node briefly
      nodes = RedisServerWrapper.Cluster.nodes(cluster_srv)
      target = List.last(nodes)
      {:ok, os_pid} = Chaos.freeze_node(target)

      # Commands to other slots should still work
      assert {:ok, "value"} = Cluster.command(cluster, ["GET", "{freeze}.key"])

      # Resume
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

  defp promote_replica(cluster_srv, killed, dead_port) do
    surviving = RedisServerWrapper.Cluster.nodes(cluster_srv) |> Enum.reject(&(&1 == killed))

    # Get the dead master's node ID from CLUSTER NODES
    {:ok, cn} = Server.run(hd(surviving), ["CLUSTER", "NODES"])

    dead_master_id =
      cn
      |> String.split("\n", trim: true)
      |> Enum.find_value(fn line ->
        if String.contains?(line, ":#{dead_port}@") do
          line |> String.split() |> hd()
        end
      end)

    # Find the replica referencing this master ID
    replica =
      Enum.find(surviving, fn n ->
        case Server.run(n, ["CLUSTER", "NODES"]) do
          {:ok, output} ->
            lines = String.split(output, "\n", trim: true)
            myself = Enum.find(lines, &String.contains?(&1, "myself"))

            if myself do
              parts = String.split(myself)
              String.contains?(Enum.at(parts, 2), "slave") and Enum.at(parts, 3) == dead_master_id
            end

          _ ->
            false
        end
      end)

    if replica do
      {:ok, "OK"} = Server.run(replica, ["CLUSTER", "FAILOVER", "FORCE"])
      :ok
    else
      raise "Could not find replica of dead master #{dead_port}"
    end
  end
end

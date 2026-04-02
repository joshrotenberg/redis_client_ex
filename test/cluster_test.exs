defmodule Redis.ClusterTest do
  use ExUnit.Case, async: false

  alias Redis.Cluster
  alias Redis.Cluster.Router

  @moduletag timeout: 60_000

  describe "Router" do
    test "slot_for_command" do
      assert {:ok, _slot} = Router.slot_for_command(["GET", "mykey"])
      assert {:error, :no_key} = Router.slot_for_command(["PING"])
    end

    test "validate_pipeline same slot" do
      assert {:ok, _slot} =
               Router.validate_pipeline([
                 ["SET", "{user}.name", "alice"],
                 ["SET", "{user}.email", "a@b.com"]
               ])
    end

    test "validate_pipeline cross slot" do
      assert {:error, :cross_slot} =
               Router.validate_pipeline([
                 ["SET", "key1", "v1"],
                 ["SET", "key2", "v2"]
               ])
    end

    test "key_from_command" do
      assert Router.key_from_command(["SET", "mykey", "val"]) == "mykey"
      assert Router.key_from_command(["GET", "mykey"]) == "mykey"
      assert Router.key_from_command(["PING"]) == nil
    end
  end

  # --- Integration tests require a real cluster ---

  setup_all do
    {:ok, cluster_srv} =
      RedisServerWrapper.Cluster.start_link(
        masters: 3,
        base_port: 7300
      )

    assert RedisServerWrapper.Cluster.healthy?(cluster_srv)

    {:ok, cluster} =
      Cluster.start_link(nodes: [{"127.0.0.1", 7300}, {"127.0.0.1", 7301}, {"127.0.0.1", 7302}])

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

    {:ok, cluster: cluster}
  end

  describe "Cluster integration" do
    test "SET and GET routed to correct node", %{cluster: cluster} do
      assert {:ok, "OK"} = Cluster.command(cluster, ["SET", "hello", "cluster"])
      assert {:ok, "cluster"} = Cluster.command(cluster, ["GET", "hello"])
    end

    test "commands route to different nodes", %{cluster: cluster} do
      for i <- 1..20 do
        key = "test:key:#{i}"
        assert {:ok, "OK"} = Cluster.command(cluster, ["SET", key, "val#{i}"])
      end

      for i <- 1..20 do
        key = "test:key:#{i}"
        expected = "val#{i}"
        assert {:ok, ^expected} = Cluster.command(cluster, ["GET", key])
      end
    end

    test "INCR across cluster", %{cluster: cluster} do
      assert {:ok, 1} = Cluster.command(cluster, ["INCR", "ctr:a"])
      assert {:ok, 2} = Cluster.command(cluster, ["INCR", "ctr:a"])
      assert {:ok, 1} = Cluster.command(cluster, ["INCR", "ctr:b"])
    end

    test "hash tag routes to same slot", %{cluster: cluster} do
      assert {:ok, "OK"} = Cluster.command(cluster, ["SET", "{usr}.name", "alice"])
      assert {:ok, "OK"} = Cluster.command(cluster, ["SET", "{usr}.email", "a@b.com"])
      assert {:ok, "alice"} = Cluster.command(cluster, ["GET", "{usr}.name"])
      assert {:ok, "a@b.com"} = Cluster.command(cluster, ["GET", "{usr}.email"])
    end

    test "pipeline same slot", %{cluster: cluster} do
      {:ok, results} =
        Cluster.pipeline(cluster, [
          ["SET", "{pp}.a", "1"],
          ["SET", "{pp}.b", "2"],
          ["GET", "{pp}.a"],
          ["GET", "{pp}.b"]
        ])

      assert results == ["OK", "OK", "1", "2"]
    end

    test "pipeline cross slot succeeds with auto-splitting", %{cluster: cluster} do
      # These keys will (almost certainly) hash to different slots
      commands = [
        ["SET", "xslot:alpha", "a"],
        ["SET", "xslot:beta", "b"],
        ["SET", "xslot:gamma", "c"]
      ]

      assert {:ok, results} = Cluster.pipeline(cluster, commands)
      assert results == ["OK", "OK", "OK"]

      # Verify the values were actually written
      assert {:ok, "a"} = Cluster.command(cluster, ["GET", "xslot:alpha"])
      assert {:ok, "b"} = Cluster.command(cluster, ["GET", "xslot:beta"])
      assert {:ok, "c"} = Cluster.command(cluster, ["GET", "xslot:gamma"])
    end

    test "pipeline with mixed key-less commands", %{cluster: cluster} do
      commands = [
        ["SET", "mixed:key1", "val1"],
        ["PING"],
        ["SET", "mixed:key2", "val2"],
        ["PING"]
      ]

      assert {:ok, results} = Cluster.pipeline(cluster, commands)
      assert Enum.at(results, 0) == "OK"
      assert Enum.at(results, 1) == "PONG"
      assert Enum.at(results, 2) == "OK"
      assert Enum.at(results, 3) == "PONG"
    end

    test "cross-slot pipeline preserves result ordering", %{cluster: cluster} do
      # Set up keys across different slots
      keys = for i <- 1..10, do: "order:#{i}"
      set_commands = for {k, i} <- Enum.with_index(keys, 1), do: ["SET", k, "v#{i}"]

      assert {:ok, set_results} = Cluster.pipeline(cluster, set_commands)
      assert Enum.all?(set_results, &(&1 == "OK"))

      # Now GET them all in a pipeline and verify ordering
      get_commands = for k <- keys, do: ["GET", k]
      assert {:ok, get_results} = Cluster.pipeline(cluster, get_commands)

      expected = for i <- 1..10, do: "v#{i}"
      assert get_results == expected
    end

    test "key-less commands work", %{cluster: cluster} do
      assert {:ok, "PONG"} = Cluster.command(cluster, ["PING"])
    end

    test "info returns cluster state", %{cluster: cluster} do
      info = Cluster.info(cluster)
      assert length(info.nodes) >= 3
      assert info.slot_coverage == 16_384
    end

    test "refresh updates topology", %{cluster: cluster} do
      assert :ok = Cluster.refresh(cluster)
    end
  end
end

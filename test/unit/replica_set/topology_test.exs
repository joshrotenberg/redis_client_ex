defmodule Redis.ReplicaSet.TopologyTest do
  use ExUnit.Case, async: true

  alias Redis.ReplicaSet.Topology

  describe "parse_info/1" do
    test "extracts online replicas from primary INFO REPLICATION" do
      info = """
      # Replication
      role:master
      connected_slaves:3
      slave0:ip=127.0.0.1,port=6380,state=online,offset=10,lag=0
      slave1:ip=redis-two,port=6381,state=sync,offset=0,lag=1
      replica2:ip=redis-three,port=6382,state=online,offset=10,lag=0
      """

      assert {:ok, replicas} = Topology.parse_info(info)
      assert {"127.0.0.1", 6380} in replicas
      assert {"redis-three", 6382} in replicas
      refute {"redis-two", 6381} in replicas
    end

    test "rejects replication info from a replica" do
      assert {:error, :not_primary} =
               Topology.parse_info("role:slave\r\nmaster_host:127.0.0.1\r\n")
    end

    test "skips invalid addresses and unknown fields" do
      info = """
      role:master
      future_field:value
      slave0:ip=,port=6380,state=online
      slave1:ip=host,port=invalid,state=online
      """

      assert {:ok, []} = Topology.parse_info(info)
    end
  end

  describe "parse_sentinel_replicas/1" do
    test "keeps only reachable replicas with healthy primary links" do
      replicas = [
        [
          "ip",
          "127.0.0.1",
          "port",
          "6380",
          "flags",
          "slave",
          "master-link-status",
          "ok"
        ],
        [
          "ip",
          "127.0.0.1",
          "port",
          "6381",
          "flags",
          "slave,s_down",
          "master-link-status",
          "down"
        ]
      ]

      assert Topology.parse_sentinel_replicas(replicas) == [{"127.0.0.1", 6380}]
    end
  end
end

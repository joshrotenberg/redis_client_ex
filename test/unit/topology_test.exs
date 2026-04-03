defmodule Redis.Cluster.TopologyTest do
  use ExUnit.Case, async: true

  alias Redis.Cluster.Topology

  describe "parse_slots/1" do
    test "parses basic RESP3 slot response" do
      # RESP3 format: [[start, end, [host, port, id, %{}]], ...]
      slots = [
        [0, 5_460, ["127.0.0.1", 7000, "abc123", %{}]],
        [5_461, 10_922, ["127.0.0.1", 7001, "def456", %{}]],
        [10_923, 16_383, ["127.0.0.1", 7002, "ghi789", %{}]]
      ]

      parsed = Topology.parse_slots(slots)

      assert length(parsed) == 3
      assert {0, 5_460, "127.0.0.1", 7000} in parsed
      assert {5_461, 10_922, "127.0.0.1", 7001} in parsed
      assert {10_923, 16_383, "127.0.0.1", 7002} in parsed
    end

    test "normalizes empty host to 127.0.0.1" do
      slots = [[0, 5_460, ["", 7000, "abc", %{}]]]

      [{_, _, host, _}] = Topology.parse_slots(slots)
      assert host == "127.0.0.1"
    end

    test "handles slots with replicas" do
      slots = [
        [
          0,
          5_460,
          ["127.0.0.1", 7000, "master1", %{}],
          ["127.0.0.1", 7003, "replica1", %{}]
        ]
      ]

      parsed = Topology.parse_slots(slots)
      assert [{0, 5_460, "127.0.0.1", 7000}] = parsed
    end

    test "returns empty list for empty input" do
      assert Topology.parse_slots([]) == []
    end

    test "skips malformed entries" do
      slots = [
        [0, 5_460, ["127.0.0.1", 7000, "abc", %{}]],
        :garbage,
        "not a slot"
      ]

      assert [{0, 5_460, "127.0.0.1", 7000}] = Topology.parse_slots(slots)
    end
  end

  describe "parse_slots_with_replicas/1" do
    test "includes replica info" do
      slots = [
        [
          0,
          5_460,
          ["127.0.0.1", 7000, "master1", %{}],
          ["127.0.0.1", 7003, "replica1", %{}],
          ["127.0.0.1", 7004, "replica2", %{}]
        ]
      ]

      [{start, stop, primary, replicas}] = Topology.parse_slots_with_replicas(slots)

      assert start == 0
      assert stop == 5_460
      assert primary == {"127.0.0.1", 7000}
      assert length(replicas) == 2
      assert {"127.0.0.1", 7003} in replicas
      assert {"127.0.0.1", 7004} in replicas
    end

    test "handles no replicas" do
      slots = [[0, 5_460, ["127.0.0.1", 7000, "master1", %{}]]]

      [{_, _, _, replicas}] = Topology.parse_slots_with_replicas(slots)
      assert replicas == []
    end
  end

  describe "build_slot_map/1" do
    test "expands ranges to individual slot entries" do
      parsed = [{0, 2, "127.0.0.1", 7000}]

      slot_map = Topology.build_slot_map(parsed)

      assert length(slot_map) == 3
      assert {0, {"127.0.0.1", 7000}} in slot_map
      assert {1, {"127.0.0.1", 7000}} in slot_map
      assert {2, {"127.0.0.1", 7000}} in slot_map
    end

    test "handles multiple ranges" do
      parsed = [
        {0, 1, "host1", 7000},
        {2, 3, "host2", 7001}
      ]

      slot_map = Topology.build_slot_map(parsed)

      assert length(slot_map) == 4
      assert {0, {"host1", 7000}} in slot_map
      assert {2, {"host2", 7001}} in slot_map
    end

    test "handles single-slot range" do
      parsed = [{100, 100, "127.0.0.1", 7000}]

      slot_map = Topology.build_slot_map(parsed)
      assert [{100, {"127.0.0.1", 7000}}] = slot_map
    end
  end

  describe "build_replica_map/1" do
    test "builds replica entries for slots with replicas" do
      parsed = [
        {0, 1, {"127.0.0.1", 7000}, [{"127.0.0.1", 7003}]},
        {2, 3, {"127.0.0.1", 7001}, []}
      ]

      replica_map = Topology.build_replica_map(parsed)

      # Only slots 0-1 have replicas
      assert length(replica_map) == 2
      assert {0, [{"127.0.0.1", 7003}]} in replica_map
      assert {1, [{"127.0.0.1", 7003}]} in replica_map
    end

    test "returns empty for no replicas" do
      parsed = [{0, 2, {"127.0.0.1", 7000}, []}]

      assert Topology.build_replica_map(parsed) == []
    end
  end

  describe "parse_shards/1" do
    test "parses CLUSTER SHARDS response" do
      shards = [
        %{
          "slots" => [0, 5_460],
          "nodes" => [
            %{
              "id" => "abc123",
              "ip" => "127.0.0.1",
              "port" => 7000,
              "endpoint" => "127.0.0.1",
              "role" => "master",
              "health" => "online"
            },
            %{
              "id" => "def456",
              "ip" => "127.0.0.1",
              "port" => 7003,
              "endpoint" => "127.0.0.1",
              "role" => "replica",
              "health" => "online"
            }
          ]
        },
        %{
          "slots" => [5_461, 10_922],
          "nodes" => [
            %{
              "id" => "ghi789",
              "ip" => "127.0.0.1",
              "port" => 7001,
              "role" => "master",
              "health" => "online"
            }
          ]
        }
      ]

      parsed = Topology.parse_shards(shards)

      assert length(parsed) == 2
      assert {0, 5_460, "127.0.0.1", 7000} in parsed
      assert {5_461, 10_922, "127.0.0.1", 7001} in parsed
    end

    test "handles multiple slot ranges per shard" do
      shards = [
        %{
          "slots" => [0, 100, 200, 300],
          "nodes" => [
            %{"ip" => "127.0.0.1", "port" => 7000, "role" => "master"}
          ]
        }
      ]

      parsed = Topology.parse_shards(shards)
      assert {0, 100, "127.0.0.1", 7000} in parsed
      assert {200, 300, "127.0.0.1", 7000} in parsed
    end

    test "normalizes empty host" do
      shards = [
        %{
          "slots" => [0, 100],
          "nodes" => [%{"ip" => "", "port" => 7000, "role" => "master"}]
        }
      ]

      [{_, _, host, _}] = Topology.parse_shards(shards)
      assert host == "127.0.0.1"
    end

    test "returns empty for missing master" do
      shards = [
        %{
          "slots" => [0, 100],
          "nodes" => [
            %{"ip" => "127.0.0.1", "port" => 7003, "role" => "replica"}
          ]
        }
      ]

      assert Topology.parse_shards(shards) == []
    end

    test "returns empty for invalid input" do
      assert Topology.parse_shards(:invalid) == []
      assert Topology.parse_shards([]) == []
    end
  end

  describe "parse_shards_with_replicas/1" do
    test "includes replica info" do
      shards = [
        %{
          "slots" => [0, 5_460],
          "nodes" => [
            %{
              "ip" => "127.0.0.1",
              "port" => 7000,
              "endpoint" => "127.0.0.1",
              "role" => "master"
            },
            %{
              "ip" => "127.0.0.1",
              "port" => 7003,
              "endpoint" => "127.0.0.1",
              "role" => "replica"
            },
            %{
              "ip" => "127.0.0.1",
              "port" => 7004,
              "endpoint" => "127.0.0.1",
              "role" => "replica"
            }
          ]
        }
      ]

      [{start_slot, end_slot, primary, replicas}] =
        Topology.parse_shards_with_replicas(shards)

      assert start_slot == 0
      assert end_slot == 5_460
      assert primary == {"127.0.0.1", 7000}
      assert length(replicas) == 2
      assert {"127.0.0.1", 7003} in replicas
      assert {"127.0.0.1", 7004} in replicas
    end
  end
end

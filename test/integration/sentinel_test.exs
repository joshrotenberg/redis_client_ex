defmodule Redis.SentinelTest do
  use ExUnit.Case, async: false

  alias Redis.Sentinel

  @moduletag timeout: 60_000
  @moduletag :sentinel

  setup_all do
    {:ok, sentinel_srv} =
      RedisServerWrapper.Sentinel.start_link(
        master_port: 6500,
        replicas: 1,
        sentinels: 3,
        sentinel_base_port: 26_400
      )

    assert RedisServerWrapper.Sentinel.healthy?(sentinel_srv)

    on_exit(fn ->
      try do
        RedisServerWrapper.Sentinel.stop(sentinel_srv)
      catch
        :exit, _ -> :ok
      end

      Process.sleep(1000)
    end)

    {:ok, sentinel_srv: sentinel_srv}
  end

  describe "Sentinel client" do
    test "connects to primary via sentinel" do
      {:ok, conn} =
        Sentinel.start_link(
          sentinels: [{"127.0.0.1", 26_400}, {"127.0.0.1", 26_401}, {"127.0.0.1", 26_402}],
          group: "mymaster"
        )

      assert {:ok, "PONG"} = Sentinel.command(conn, ["PING"])

      info = Sentinel.info(conn)
      assert info.group == "mymaster"
      assert info.role == :primary
      assert info.connected == true
      assert info.current_addr == {"127.0.0.1", 6500}

      Sentinel.stop(conn)
    end

    test "SET and GET through sentinel" do
      {:ok, conn} =
        Sentinel.start_link(
          sentinels: [{"127.0.0.1", 26_400}],
          group: "mymaster"
        )

      assert {:ok, "OK"} = Sentinel.command(conn, ["SET", "sentinel_key", "sentinel_value"])
      assert {:ok, "sentinel_value"} = Sentinel.command(conn, ["GET", "sentinel_key"])

      Sentinel.stop(conn)
    end

    test "pipeline through sentinel" do
      {:ok, conn} =
        Sentinel.start_link(
          sentinels: [{"127.0.0.1", 26_400}],
          group: "mymaster"
        )

      {:ok, results} =
        Sentinel.pipeline(conn, [
          ["SET", "sp_a", "1"],
          ["SET", "sp_b", "2"],
          ["GET", "sp_a"]
        ])

      assert results == ["OK", "OK", "1"]

      Sentinel.stop(conn)
    end

    test "transaction through sentinel" do
      {:ok, conn} =
        Sentinel.start_link(
          sentinels: [{"127.0.0.1", 26_400}],
          group: "mymaster"
        )

      {:ok, results} =
        Sentinel.transaction(conn, [
          ["INCR", "st_counter"],
          ["INCR", "st_counter"]
        ])

      assert results == [1, 2]

      Sentinel.stop(conn)
    end

    test "routes eligible reads to replicas and writes to the primary" do
      {:ok, conn} =
        Sentinel.start_link(
          sentinels: [{"127.0.0.1", 26_400}, {"127.0.0.1", 26_401}],
          group: "mymaster",
          read_preference: :replica,
          read_only_commands: ["ROLE"],
          topology_refresh_interval: nil
        )

      eventually(fn ->
        Sentinel.refresh(conn) == :ok and Sentinel.info(conn).connected_replicas != []
      end)

      assert {:ok, [replica_role | _]} = Sentinel.command(conn, ["ROLE"])
      assert replica_role in ["slave", "replica"]

      key = "sentinel:replica-routing:#{System.unique_integer([:positive])}"
      assert {:ok, "OK"} = Sentinel.command(conn, ["SET", key, "value"])
      eventually(fn -> Sentinel.command(conn, ["GET", key]) == {:ok, "value"} end)

      info = Sentinel.info(conn)
      assert info.read_preference == :replica
      assert {"127.0.0.1", 6501} in info.replica_addrs
      assert {"127.0.0.1", 6501} in info.connected_replicas

      Sentinel.stop(conn)
    end

    test "rejects a fixed replica role combined with read preference routing" do
      Process.flag(:trap_exit, true)

      assert {:error, :replica_role_conflicts_with_read_preference} =
               Sentinel.start_link(
                 sentinels: [{"127.0.0.1", 26_400}],
                 group: "mymaster",
                 role: :replica,
                 read_preference: :prefer_replica
               )
    end
  end

  defp eventually(predicate, attempts \\ 200)
  defp eventually(_predicate, 0), do: flunk("condition did not become true")

  defp eventually(predicate, attempts) do
    if predicate.() do
      :ok
    else
      Process.sleep(50)
      eventually(predicate, attempts - 1)
    end
  end
end

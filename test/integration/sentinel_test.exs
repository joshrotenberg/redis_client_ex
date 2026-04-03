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
  end
end

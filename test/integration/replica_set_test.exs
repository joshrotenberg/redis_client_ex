defmodule Redis.ReplicaSetTest do
  use ExUnit.Case, async: false

  alias Redis.Connection
  alias Redis.ReplicaSet

  @primary_port 6472
  @replica_port 6473

  setup_all do
    {:ok, primary} =
      RedisServerWrapper.Server.start_link(
        port: @primary_port,
        extra: [{"repl-diskless-sync-delay", "0"}]
      )

    {:ok, replica} =
      RedisServerWrapper.Server.start_link(
        port: @replica_port,
        replicaof: {"127.0.0.1", @primary_port}
      )

    {:ok, primary_connection} = Connection.start_link(port: @primary_port)
    {:ok, replica_connection} = Connection.start_link(port: @replica_port)

    eventually(
      fn ->
        with {:ok, primary_info} <-
               Connection.command(primary_connection, ["INFO", "REPLICATION"]),
             {:ok, replica_info} <-
               Connection.command(replica_connection, ["INFO", "REPLICATION"]) do
          String.contains?(primary_info, "state=online") and
            String.contains?(replica_info, "master_link_status:up")
        else
          _error -> false
        end
      end,
      200
    )

    Connection.stop(primary_connection)
    Connection.stop(replica_connection)

    on_exit(fn ->
      stop_server(replica)
      stop_server(primary)
    end)

    :ok
  end

  test "discovers replicas with INFO and routes reads to them" do
    {:ok, redis} =
      ReplicaSet.start_link(
        primary: {"127.0.0.1", @primary_port},
        read_preference: :replica,
        read_only_commands: ["ROLE"],
        topology_refresh_interval: nil
      )

    assert %{
             primary: {"127.0.0.1", @primary_port},
             replicas: replicas,
             connected_replicas: connected,
             discovery: :info
           } = ReplicaSet.info(redis)

    assert {"127.0.0.1", @replica_port} in replicas
    assert {"127.0.0.1", @replica_port} in connected
    assert {:ok, [role | _]} = ReplicaSet.command(redis, ["ROLE"])
    assert role in ["slave", "replica"]

    ReplicaSet.stop(redis)
  end

  test "keeps writes and mixed pipelines on the primary" do
    {:ok, redis} =
      ReplicaSet.start_link(
        primary: {"127.0.0.1", @primary_port},
        replicas: [{"127.0.0.1", @replica_port}],
        read_preference: :replica,
        read_only_commands: ["ROLE"]
      )

    key = "replica-set:#{System.unique_integer([:positive])}"
    assert {:ok, "OK"} = ReplicaSet.command(redis, ["SET", key, "value"])
    eventually(fn -> ReplicaSet.command(redis, ["GET", key]) == {:ok, "value"} end)

    assert {:ok, ["OK", [role | _]]} =
             ReplicaSet.pipeline(redis, [
               ["SET", key, "updated"],
               ["ROLE"]
             ])

    assert role in ["master", "primary"]
    ReplicaSet.stop(redis)
  end

  test "routes all-read pipelines to a replica" do
    {:ok, redis} =
      ReplicaSet.start_link(
        primary: {"127.0.0.1", @primary_port},
        replicas: [{"127.0.0.1", @replica_port}],
        read_preference: :prefer_replica,
        read_only_commands: ["ROLE"]
      )

    assert {:ok, [[role | _]]} = ReplicaSet.pipeline(redis, [["ROLE"]])
    assert role in ["slave", "replica"]
    ReplicaSet.stop(redis)
  end

  test "master preference and missing replicas use the primary" do
    {:ok, master_only} =
      ReplicaSet.start_link(
        primary: {"127.0.0.1", @primary_port},
        replicas: [{"127.0.0.1", @replica_port}],
        read_preference: :master,
        read_only_commands: ["ROLE"]
      )

    assert {:ok, [master_role | _]} = ReplicaSet.command(master_only, ["ROLE"])
    assert master_role in ["master", "primary"]
    ReplicaSet.stop(master_only)

    {:ok, fallback} =
      ReplicaSet.start_link(
        primary: {"127.0.0.1", 6398},
        replicas: [],
        read_preference: :replica,
        read_only_commands: ["ROLE"]
      )

    assert {:ok, [fallback_role | _]} = ReplicaSet.command(fallback, ["ROLE"])
    assert fallback_role in ["master", "primary"]
    ReplicaSet.stop(fallback)
  end

  test "updates topology without restarting the router" do
    {:ok, redis} =
      ReplicaSet.start_link(
        primary: {"127.0.0.1", @primary_port},
        replicas: [],
        read_preference: :replica,
        read_only_commands: ["ROLE"]
      )

    assert :ok =
             ReplicaSet.update_topology(
               redis,
               {"127.0.0.1", @primary_port},
               [{"127.0.0.1", @replica_port}]
             )

    assert {:ok, [role | _]} = ReplicaSet.command(redis, ["ROLE"])
    assert role in ["slave", "replica"]
    ReplicaSet.stop(redis)
  end

  test "rejects invalid read preferences" do
    Process.flag(:trap_exit, true)

    assert {:error, {:invalid_read_preference, :nearest}} =
             ReplicaSet.start_link(
               primary: {"127.0.0.1", @primary_port},
               read_preference: :nearest
             )
  end

  defp eventually(predicate, attempts \\ 100)
  defp eventually(_predicate, 0), do: flunk("condition did not become true")

  defp eventually(predicate, attempts) do
    if predicate.() do
      :ok
    else
      Process.sleep(20)
      eventually(predicate, attempts - 1)
    end
  end

  defp stop_server(server) do
    if Process.alive?(server) do
      RedisServerWrapper.Server.stop(server)
    end
  catch
    :exit, _reason -> :ok
  end
end

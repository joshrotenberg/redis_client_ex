defmodule Redis.ResponseIntegrationTest do
  use ExUnit.Case, async: false

  alias Redis.Connection
  alias Redis.Response.{Client, Stream, StreamEntry}

  setup do
    {:ok, conn} = Connection.start_link(port: 6398)
    {:ok, resp2} = Connection.start_link(port: 6398, protocol: :resp2)

    Connection.command(conn, ["FLUSHDB"])

    %{conn: conn, resp2: resp2}
  end

  test "raw remains the default and typed HGETALL is protocol-independent", %{
    conn: conn,
    resp2: resp2
  } do
    assert {:ok, 2} =
             Connection.command(conn, ["HSET", "typed:hash", "name", "Ada", "role", "admin"])

    assert {:ok, ["name", "Ada", "role", "admin"]} =
             Connection.command(resp2, ["HGETALL", "typed:hash"])

    expected = %{"name" => "Ada", "role" => "admin"}

    assert {:ok, ^expected} =
             Connection.command(resp2, ["HGETALL", "typed:hash"], response: :typed)

    assert {:ok, ^expected} =
             Connection.command(conn, ["HGETALL", "typed:hash"], response: :typed)
  end

  test "INFO and CLIENT LIST have structured typed replies", %{conn: conn} do
    assert {:ok, %{"redis_version" => version}} =
             Connection.command(conn, ["INFO", "server"], response: :typed)

    assert is_binary(version)

    assert {:ok, clients} =
             Connection.command(conn, ["CLIENT", "LIST"], response: :typed)

    assert Enum.all?(clients, &match?(%Client{}, &1))
    assert Enum.any?(clients, &(&1.lib_name == "redis_client_ex"))
  end

  test "stream replies are normalized for ranges and reads", %{conn: conn} do
    assert {:ok, id} =
             Connection.command(conn, ["XADD", "typed:events", "*", "event", "created"])

    assert {:ok, [%StreamEntry{id: ^id, fields: %{"event" => "created"}}]} =
             Connection.command(
               conn,
               ["XRANGE", "typed:events", "-", "+"],
               response: :typed
             )

    assert {:ok,
            [
              %Stream{
                name: "typed:events",
                entries: [%StreamEntry{id: ^id, fields: %{"event" => "created"}}]
              }
            ]} =
             Connection.command(
               conn,
               ["XREAD", "STREAMS", "typed:events", "0"],
               response: :typed
             )
  end

  test "pipelines and top-level helpers parse each known reply", %{conn: conn} do
    assert {:ok, ["OK", 1, %{"name" => "Ada"}]} =
             Redis.pipeline_typed(conn, [
               ["SET", "typed:key", "value"],
               ["HSET", "typed:user", "name", "Ada"],
               ["HGETALL", "typed:user"]
             ])

    assert {:ok, %MapSet{} = members} =
             Redis.command_typed(conn, ["SMEMBERS", "typed:set"])

    assert MapSet.size(members) == 0

    assert {:ok, [1, %{"field" => "value"}]} =
             Redis.transaction_typed(conn, [
               ["HSET", "typed:transaction", "field", "value"],
               ["HGETALL", "typed:transaction"]
             ])
  end
end

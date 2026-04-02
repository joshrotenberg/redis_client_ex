defmodule Redis.Commands.JSONIntegrationTest do
  use ExUnit.Case, async: false

  alias Redis.Commands.JSON
  alias Redis.Connection

  # Requires Redis Stack (JSON module)
  # Connects to port from REDIS_STACK_PORT env var, or 6379 (Docker service in CI)

  @moduletag :redis_stack

  @stack_port String.to_integer(System.get_env("REDIS_STACK_PORT") || "6379")

  setup do
    {:ok, conn} = Connection.start_link(port: @stack_port)

    on_exit(fn ->
      Connection.command(conn, ["DEL", "json:test", "json:arr", "json:num", "json:obj"])
      Connection.stop(conn)
    end)

    {:ok, conn: conn}
  end

  describe "JSON.SET and JSON.GET" do
    test "round-trips a map", %{conn: conn} do
      cmd = JSON.set("json:test", %{name: "Alice", age: 30})
      assert {:ok, "OK"} = Connection.command(conn, cmd)

      assert {:ok, result} = Connection.command(conn, JSON.get("json:test"))
      decoded = Jason.decode!(result)
      assert [%{"name" => "Alice", "age" => 30}] = decoded
    end

    test "SET with NX only sets if not exists", %{conn: conn} do
      assert {:ok, "OK"} = Connection.command(conn, JSON.set("json:test", %{a: 1}))
      assert {:ok, nil} = Connection.command(conn, JSON.set("json:test", %{a: 2}, nx: true))

      assert {:ok, result} = Connection.command(conn, JSON.get("json:test"))
      assert [%{"a" => 1}] = Jason.decode!(result)
    end

    test "SET with path", %{conn: conn} do
      assert {:ok, "OK"} = Connection.command(conn, JSON.set("json:test", %{name: "Alice"}))

      assert {:ok, "OK"} =
               Connection.command(conn, JSON.set("json:test", 30, path: "$.age"))

      assert {:ok, result} = Connection.command(conn, JSON.get("json:test"))
      assert [%{"name" => "Alice", "age" => 30}] = Jason.decode!(result)
    end

    test "GET multiple paths", %{conn: conn} do
      assert {:ok, "OK"} =
               Connection.command(conn, JSON.set("json:test", %{name: "Alice", age: 30}))

      assert {:ok, result} =
               Connection.command(conn, JSON.get("json:test", paths: ["$.name", "$.age"]))

      decoded = Jason.decode!(result)
      assert %{"$.name" => ["Alice"], "$.age" => [30]} = decoded
    end
  end

  describe "JSON array operations" do
    test "ARRAPPEND and ARRLEN", %{conn: conn} do
      assert {:ok, "OK"} = Connection.command(conn, JSON.set("json:arr", %{items: [1, 2]}))

      assert {:ok, _} = Connection.command(conn, JSON.arrappend("json:arr", [3, 4], "$.items"))

      assert {:ok, result} = Connection.command(conn, JSON.arrlen("json:arr", "$.items"))
      assert [4] = result
    end

    test "ARRPOP", %{conn: conn} do
      assert {:ok, "OK"} = Connection.command(conn, JSON.set("json:arr", %{items: [1, 2, 3]}))

      assert {:ok, _} = Connection.command(conn, JSON.arrpop("json:arr", "$.items"))

      assert {:ok, result} = Connection.command(conn, JSON.arrlen("json:arr", "$.items"))
      assert [2] = result
    end
  end

  describe "JSON numeric operations" do
    test "NUMINCRBY", %{conn: conn} do
      assert {:ok, "OK"} = Connection.command(conn, JSON.set("json:num", %{counter: 10}))

      assert {:ok, result} =
               Connection.command(conn, JSON.numincrby("json:num", 5, "$.counter"))

      assert "[15]" = result
    end
  end

  describe "JSON object operations" do
    test "OBJKEYS and OBJLEN", %{conn: conn} do
      assert {:ok, "OK"} =
               Connection.command(conn, JSON.set("json:obj", %{a: 1, b: 2, c: 3}))

      assert {:ok, keys} = Connection.command(conn, JSON.objkeys("json:obj"))
      assert [inner] = keys
      assert length(inner) == 3

      assert {:ok, [3]} = Connection.command(conn, JSON.objlen("json:obj"))
    end
  end

  describe "JSON DEL and TYPE" do
    test "DEL removes a path", %{conn: conn} do
      assert {:ok, "OK"} =
               Connection.command(conn, JSON.set("json:test", %{name: "Alice", age: 30}))

      assert {:ok, 1} = Connection.command(conn, JSON.del("json:test", "$.age"))

      assert {:ok, result} = Connection.command(conn, JSON.get("json:test"))
      decoded = Jason.decode!(result)
      assert [%{"name" => "Alice"}] = decoded
    end

    test "TYPE returns the type", %{conn: conn} do
      assert {:ok, "OK"} = Connection.command(conn, JSON.set("json:test", %{name: "Alice"}))

      assert {:ok, [type]} = Connection.command(conn, JSON.type("json:test"))
      assert type == "object"
    end
  end
end

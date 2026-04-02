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
    suffix = :erlang.unique_integer([:positive])

    on_exit(fn ->
      case Connection.start_link(port: @stack_port) do
        {:ok, cleanup} ->
          for key <- [
                "json:test:#{suffix}",
                "json:arr:#{suffix}",
                "json:num:#{suffix}",
                "json:obj:#{suffix}"
              ] do
            Connection.command(cleanup, ["DEL", key])
          end

          Connection.stop(cleanup)

        _ ->
          :ok
      end
    end)

    {:ok, conn: conn, s: suffix}
  end

  describe "JSON.SET and JSON.GET" do
    test "round-trips a map", %{conn: conn, s: s} do
      cmd = JSON.set("json:test:#{s}", %{name: "Alice", age: 30})
      assert {:ok, "OK"} = Connection.command(conn, cmd)

      assert {:ok, result} = Connection.command(conn, JSON.get("json:test:#{s}"))
      decoded = Jason.decode!(result)
      assert [%{"name" => "Alice", "age" => 30}] = decoded
    end

    test "SET with NX only sets if not exists", %{conn: conn, s: s} do
      assert {:ok, "OK"} = Connection.command(conn, JSON.set("json:test:#{s}", %{a: 1}))

      assert {:ok, nil} =
               Connection.command(conn, JSON.set("json:test:#{s}", %{a: 2}, nx: true))

      assert {:ok, result} = Connection.command(conn, JSON.get("json:test:#{s}"))
      assert [%{"a" => 1}] = Jason.decode!(result)
    end

    test "SET with path", %{conn: conn, s: s} do
      assert {:ok, "OK"} =
               Connection.command(conn, JSON.set("json:test:#{s}", %{name: "Alice"}))

      assert {:ok, "OK"} =
               Connection.command(conn, JSON.set("json:test:#{s}", 30, path: "$.age"))

      assert {:ok, result} = Connection.command(conn, JSON.get("json:test:#{s}"))
      assert [%{"name" => "Alice", "age" => 30}] = Jason.decode!(result)
    end

    test "GET multiple paths", %{conn: conn, s: s} do
      assert {:ok, "OK"} =
               Connection.command(conn, JSON.set("json:test:#{s}", %{name: "Alice", age: 30}))

      assert {:ok, result} =
               Connection.command(
                 conn,
                 JSON.get("json:test:#{s}", paths: ["$.name", "$.age"])
               )

      decoded = Jason.decode!(result)
      assert %{"$.name" => ["Alice"], "$.age" => [30]} = decoded
    end
  end

  describe "JSON array operations" do
    test "ARRAPPEND and ARRLEN", %{conn: conn, s: s} do
      assert {:ok, "OK"} =
               Connection.command(conn, JSON.set("json:arr:#{s}", %{items: [1, 2]}))

      assert {:ok, _} =
               Connection.command(conn, JSON.arrappend("json:arr:#{s}", [3, 4], "$.items"))

      assert {:ok, [4]} = Connection.command(conn, JSON.arrlen("json:arr:#{s}", "$.items"))
    end

    test "ARRPOP", %{conn: conn, s: s} do
      assert {:ok, "OK"} =
               Connection.command(conn, JSON.set("json:arr:#{s}", %{items: [1, 2, 3]}))

      assert {:ok, _} = Connection.command(conn, JSON.arrpop("json:arr:#{s}", "$.items"))

      assert {:ok, [2]} = Connection.command(conn, JSON.arrlen("json:arr:#{s}", "$.items"))
    end
  end

  describe "JSON numeric operations" do
    test "NUMINCRBY", %{conn: conn, s: s} do
      assert {:ok, "OK"} =
               Connection.command(conn, JSON.set("json:num:#{s}", %{counter: 10}))

      assert {:ok, result} =
               Connection.command(conn, JSON.numincrby("json:num:#{s}", 5, "$.counter"))

      # RESP3 returns a list, RESP2 returns a string
      assert result == [15] or result == "[15]"
    end
  end

  describe "JSON object operations" do
    test "OBJKEYS and OBJLEN", %{conn: conn, s: s} do
      assert {:ok, "OK"} =
               Connection.command(conn, JSON.set("json:obj:#{s}", %{a: 1, b: 2, c: 3}))

      assert {:ok, keys} = Connection.command(conn, JSON.objkeys("json:obj:#{s}"))
      assert [inner] = keys
      assert length(inner) == 3

      assert {:ok, [3]} = Connection.command(conn, JSON.objlen("json:obj:#{s}"))
    end
  end

  describe "JSON DEL and TYPE" do
    test "DEL removes a path", %{conn: conn, s: s} do
      assert {:ok, "OK"} =
               Connection.command(conn, JSON.set("json:test:#{s}", %{name: "Alice", age: 30}))

      assert {:ok, 1} = Connection.command(conn, JSON.del("json:test:#{s}", "$.age"))

      assert {:ok, result} = Connection.command(conn, JSON.get("json:test:#{s}"))
      decoded = Jason.decode!(result)
      assert [%{"name" => "Alice"}] = decoded
    end

    test "TYPE returns the type", %{conn: conn, s: s} do
      assert {:ok, "OK"} =
               Connection.command(conn, JSON.set("json:test:#{s}", %{name: "Alice"}))

      assert {:ok, [type]} = Connection.command(conn, JSON.type("json:test:#{s}"))
      assert type == "object"
    end
  end
end

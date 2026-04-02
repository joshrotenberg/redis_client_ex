defmodule Redis.Commands.SearchIntegrationTest do
  use ExUnit.Case, async: false

  alias Redis.Commands.Search
  alias Redis.Connection

  # Requires Redis Stack (Search module)
  # Connects to port from REDIS_STACK_PORT env var, or 6379 (Docker service in CI)

  @moduletag :redis_stack

  @stack_port String.to_integer(System.get_env("REDIS_STACK_PORT") || "6379")

  setup do
    {:ok, conn} = Connection.start_link(port: @stack_port)

    # Use unique index names per test to avoid collisions
    suffix = :erlang.unique_integer([:positive])
    idx = "idx:test:#{suffix}"
    idx_json = "idx:json:#{suffix}"

    on_exit(fn ->
      # Start a fresh connection for cleanup since the test one may have died
      case Connection.start_link(port: @stack_port) do
        {:ok, cleanup} ->
          Connection.command(cleanup, Search.dropindex(idx, dd: true))
          Connection.command(cleanup, Search.dropindex(idx_json, dd: true))

          for i <- 1..3 do
            Connection.command(cleanup, ["DEL", "user:#{suffix}:#{i}"])
          end

          for i <- 1..2 do
            Connection.command(cleanup, ["DEL", "doc:#{suffix}:#{i}"])
          end

          Connection.command(cleanup, ["DEL", "ac:test:#{suffix}"])
          Connection.stop(cleanup)

        _ ->
          :ok
      end
    end)

    {:ok, conn: conn, idx: idx, idx_json: idx_json, suffix: suffix}
  end

  describe "hash index" do
    test "create, populate, and search", %{conn: conn, idx: idx, suffix: s} do
      cmd =
        Search.create(idx, :hash,
          prefix: "user:#{s}:",
          schema: [
            {"name", :text},
            {"age", :numeric, sortable: true},
            {"city", :tag}
          ]
        )

      assert {:ok, "OK"} = Connection.command(conn, cmd)

      for {name, age, city, i} <- [
            {"Alice", "30", "NYC", 1},
            {"Bob", "25", "LA", 2},
            {"Charlie", "35", "NYC", 3}
          ] do
        assert {:ok, _} =
                 Connection.command(conn, [
                   "HSET",
                   "user:#{s}:#{i}",
                   "name",
                   name,
                   "age",
                   age,
                   "city",
                   city
                 ])
      end

      Process.sleep(200)

      # Search by text -- RESP3 returns a map with "total_results" key
      assert {:ok, result} = Connection.command(conn, Search.search(idx, "@name:Alice"))
      assert %{"total_results" => count} = result
      assert count >= 1

      # Search by tag
      assert {:ok, result} = Connection.command(conn, Search.search(idx, "@city:{NYC}"))
      assert %{"total_results" => count} = result
      assert count >= 2

      # Search with sort
      assert {:ok, result} =
               Connection.command(
                 conn,
                 Search.search(idx, "*", sortby: {"age", :asc}, limit: {0, 10})
               )

      assert %{"total_results" => count} = result
      assert count >= 3
    end

    test "INFO returns index metadata", %{conn: conn, idx: idx} do
      assert {:ok, "OK"} =
               Connection.command(
                 conn,
                 Search.create(idx, :hash, prefix: "user:", schema: [{"name", :text}])
               )

      assert {:ok, info} = Connection.command(conn, Search.info(idx))
      # RESP3 returns a map
      assert is_map(info)
      assert Map.has_key?(info, "index_name")
    end

    test "_LIST includes created index", %{conn: conn, idx: idx} do
      assert {:ok, "OK"} =
               Connection.command(
                 conn,
                 Search.create(idx, :hash, prefix: "user:", schema: [{"name", :text}])
               )

      assert {:ok, indexes} = Connection.command(conn, Search.list())
      # RESP3 may return a set or list
      indexes = if is_struct(indexes, MapSet), do: MapSet.to_list(indexes), else: indexes
      assert idx in indexes
    end

    test "DROPINDEX removes the index", %{conn: conn, idx: idx} do
      assert {:ok, "OK"} =
               Connection.command(
                 conn,
                 Search.create(idx, :hash, prefix: "user:", schema: [{"name", :text}])
               )

      assert {:ok, "OK"} = Connection.command(conn, Search.dropindex(idx))
    end
  end

  describe "JSON index" do
    test "create and search JSON documents", %{conn: conn, idx_json: idx, suffix: s} do
      cmd =
        Search.create(idx, :json,
          prefix: "doc:#{s}:",
          schema: [
            {"$.title", :text, as: "title"},
            {"$.score", :numeric, as: "score", sortable: true}
          ]
        )

      assert {:ok, "OK"} = Connection.command(conn, cmd)

      assert {:ok, "OK"} =
               Connection.command(conn, [
                 "JSON.SET",
                 "doc:#{s}:1",
                 "$",
                 ~s({"title":"Redis Guide","score":95})
               ])

      assert {:ok, "OK"} =
               Connection.command(conn, [
                 "JSON.SET",
                 "doc:#{s}:2",
                 "$",
                 ~s({"title":"Elixir Handbook","score":88})
               ])

      Process.sleep(200)

      assert {:ok, result} = Connection.command(conn, Search.search(idx, "@title:Redis"))
      assert %{"total_results" => count} = result
      assert count >= 1
    end
  end

  describe "aggregate" do
    test "basic aggregation", %{conn: conn, idx: idx, suffix: s} do
      assert {:ok, "OK"} =
               Connection.command(
                 conn,
                 Search.create(idx, :hash,
                   prefix: "user:#{s}:",
                   schema: [
                     {"name", :text},
                     {"age", :numeric, sortable: true},
                     {"city", :tag}
                   ]
                 )
               )

      Connection.command(conn, [
        "HSET",
        "user:#{s}:1",
        "name",
        "Alice",
        "age",
        "30",
        "city",
        "NYC"
      ])

      Connection.command(conn, [
        "HSET",
        "user:#{s}:2",
        "name",
        "Bob",
        "age",
        "25",
        "city",
        "NYC"
      ])

      Process.sleep(200)

      cmd =
        Search.aggregate(idx, "*",
          groupby: ["@city"],
          reduce: [{"COUNT", 0, as: "count"}]
        )

      assert {:ok, result} = Connection.command(conn, cmd)
      # RESP3 returns a map with "results" key
      assert is_map(result)
      assert Map.has_key?(result, "results")
    end
  end

  describe "suggestions" do
    test "SUGADD and SUGGET", %{conn: conn, suffix: s} do
      key = "ac:test:#{s}"
      assert {:ok, _} = Connection.command(conn, Search.sugadd(key, "hello", 1.0))
      assert {:ok, _} = Connection.command(conn, Search.sugadd(key, "help", 1.0))
      assert {:ok, _} = Connection.command(conn, Search.sugadd(key, "world", 1.0))

      assert {:ok, suggestions} = Connection.command(conn, Search.sugget(key, "hel"))
      assert is_list(suggestions)
      assert [_ | _] = suggestions
    end

    test "SUGLEN", %{conn: conn, suffix: s} do
      key = "ac:test:#{s}"
      Connection.command(conn, Search.sugadd(key, "hello", 1.0))
      Connection.command(conn, Search.sugadd(key, "world", 1.0))

      assert {:ok, len} = Connection.command(conn, Search.suglen(key))
      assert len >= 2
    end
  end

  describe "TAGVALS" do
    test "returns tag values from indexed data", %{conn: conn, idx: idx, suffix: s} do
      assert {:ok, "OK"} =
               Connection.command(
                 conn,
                 Search.create(idx, :hash,
                   prefix: "user:#{s}:",
                   schema: [{"city", :tag}]
                 )
               )

      Connection.command(conn, ["HSET", "user:#{s}:1", "city", "NYC"])
      Connection.command(conn, ["HSET", "user:#{s}:2", "city", "LA"])

      Process.sleep(200)

      assert {:ok, tags} = Connection.command(conn, Search.tagvals(idx, "city"))
      # RESP3 may return a set
      tags = if is_struct(tags, MapSet), do: MapSet.to_list(tags), else: tags
      assert is_list(tags)
      assert length(tags) >= 2
    end
  end
end

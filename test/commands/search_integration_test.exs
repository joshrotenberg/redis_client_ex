defmodule Redis.Commands.SearchIntegrationTest do
  use ExUnit.Case, async: false

  alias Redis.Commands.Search
  alias Redis.Connection

  # Uses redis-server on port 6398 from test_helper.exs
  # Requires Redis Stack (Search module)

  @moduletag :redis_stack

  setup do
    {:ok, conn} = Connection.start_link(port: 6398)

    # Clean up indexes and keys
    on_exit(fn ->
      Connection.command(conn, Search.dropindex("idx:test", dd: true))
      Connection.command(conn, Search.dropindex("idx:json", dd: true))
      Connection.command(conn, ["DEL", "user:1", "user:2", "user:3", "doc:1", "doc:2"])
      Connection.command(conn, Search.sugdel("ac:test", "hello"))
      Connection.command(conn, Search.sugdel("ac:test", "help"))
      Connection.command(conn, Search.sugdel("ac:test", "world"))
      Connection.stop(conn)
    end)

    {:ok, conn: conn}
  end

  describe "hash index" do
    test "create, populate, and search", %{conn: conn} do
      # Create index
      cmd =
        Search.create("idx:test", :hash,
          prefix: "user:",
          schema: [
            {"name", :text},
            {"age", :numeric, sortable: true},
            {"city", :tag}
          ]
        )

      assert {:ok, "OK"} = Connection.command(conn, cmd)

      # Populate data
      assert {:ok, _} =
               Connection.command(conn, [
                 "HSET",
                 "user:1",
                 "name",
                 "Alice",
                 "age",
                 "30",
                 "city",
                 "NYC"
               ])

      assert {:ok, _} =
               Connection.command(conn, [
                 "HSET",
                 "user:2",
                 "name",
                 "Bob",
                 "age",
                 "25",
                 "city",
                 "LA"
               ])

      assert {:ok, _} =
               Connection.command(conn, [
                 "HSET",
                 "user:3",
                 "name",
                 "Charlie",
                 "age",
                 "35",
                 "city",
                 "NYC"
               ])

      # Give the index time to build
      Process.sleep(200)

      # Search by text
      assert {:ok, result} = Connection.command(conn, Search.search("idx:test", "@name:Alice"))
      # Result format: [count, key, [field, value, ...], ...]
      assert is_list(result)
      [count | _] = result
      assert count >= 1

      # Search by tag
      assert {:ok, result} =
               Connection.command(conn, Search.search("idx:test", "@city:{NYC}"))

      [count | _] = result
      assert count >= 2

      # Search with sort
      assert {:ok, result} =
               Connection.command(
                 conn,
                 Search.search("idx:test", "*", sortby: {"age", :asc}, limit: {0, 10})
               )

      [count | _] = result
      assert count >= 3
    end

    test "INFO returns index metadata", %{conn: conn} do
      Search.create("idx:test", :hash,
        prefix: "user:",
        schema: [{"name", :text}]
      )
      |> then(&Connection.command(conn, &1))

      assert {:ok, info} = Connection.command(conn, Search.info("idx:test"))
      assert is_list(info)
    end

    test "_LIST includes created index", %{conn: conn} do
      Search.create("idx:test", :hash,
        prefix: "user:",
        schema: [{"name", :text}]
      )
      |> then(&Connection.command(conn, &1))

      assert {:ok, indexes} = Connection.command(conn, Search.list())
      assert "idx:test" in indexes
    end

    test "DROPINDEX removes the index", %{conn: conn} do
      Search.create("idx:test", :hash,
        prefix: "user:",
        schema: [{"name", :text}]
      )
      |> then(&Connection.command(conn, &1))

      assert {:ok, "OK"} = Connection.command(conn, Search.dropindex("idx:test"))
    end
  end

  describe "JSON index" do
    test "create and search JSON documents", %{conn: conn} do
      cmd =
        Search.create("idx:json", :json,
          prefix: "doc:",
          schema: [
            {"$.title", :text, as: "title"},
            {"$.score", :numeric, as: "score", sortable: true}
          ]
        )

      assert {:ok, "OK"} = Connection.command(conn, cmd)

      assert {:ok, "OK"} =
               Connection.command(conn, [
                 "JSON.SET",
                 "doc:1",
                 "$",
                 ~s({"title":"Redis Guide","score":95})
               ])

      assert {:ok, "OK"} =
               Connection.command(conn, [
                 "JSON.SET",
                 "doc:2",
                 "$",
                 ~s({"title":"Elixir Handbook","score":88})
               ])

      Process.sleep(200)

      assert {:ok, result} = Connection.command(conn, Search.search("idx:json", "@title:Redis"))
      [count | _] = result
      assert count >= 1
    end
  end

  describe "aggregate" do
    test "basic aggregation", %{conn: conn} do
      Search.create("idx:test", :hash,
        prefix: "user:",
        schema: [
          {"name", :text},
          {"age", :numeric, sortable: true},
          {"city", :tag}
        ]
      )
      |> then(&Connection.command(conn, &1))

      Connection.command(conn, [
        "HSET",
        "user:1",
        "name",
        "Alice",
        "age",
        "30",
        "city",
        "NYC"
      ])

      Connection.command(conn, [
        "HSET",
        "user:2",
        "name",
        "Bob",
        "age",
        "25",
        "city",
        "NYC"
      ])

      Process.sleep(200)

      cmd =
        Search.aggregate("idx:test", "*",
          groupby: ["@city"],
          reduce: [{"COUNT", 0, as: "count"}]
        )

      assert {:ok, result} = Connection.command(conn, cmd)
      assert is_list(result)
    end
  end

  describe "suggestions" do
    test "SUGADD and SUGGET", %{conn: conn} do
      assert {:ok, _} = Connection.command(conn, Search.sugadd("ac:test", "hello", 1.0))
      assert {:ok, _} = Connection.command(conn, Search.sugadd("ac:test", "help", 1.0))
      assert {:ok, _} = Connection.command(conn, Search.sugadd("ac:test", "world", 1.0))

      assert {:ok, suggestions} = Connection.command(conn, Search.sugget("ac:test", "hel"))
      assert is_list(suggestions)
      assert length(suggestions) >= 1
    end

    test "SUGLEN", %{conn: conn} do
      Connection.command(conn, Search.sugadd("ac:test", "hello", 1.0))
      Connection.command(conn, Search.sugadd("ac:test", "world", 1.0))

      assert {:ok, len} = Connection.command(conn, Search.suglen("ac:test"))
      assert len >= 2
    end
  end

  describe "TAGVALS" do
    test "returns tag values from indexed data", %{conn: conn} do
      Search.create("idx:test", :hash,
        prefix: "user:",
        schema: [{"city", :tag}]
      )
      |> then(&Connection.command(conn, &1))

      Connection.command(conn, ["HSET", "user:1", "city", "NYC"])
      Connection.command(conn, ["HSET", "user:2", "city", "LA"])

      Process.sleep(200)

      assert {:ok, tags} = Connection.command(conn, Search.tagvals("idx:test", "city"))
      assert is_list(tags)
    end
  end
end

defmodule Redis.SearchTest do
  use ExUnit.Case, async: false

  alias Redis.Connection
  alias Redis.Search

  @moduletag :redis_stack

  @stack_port String.to_integer(System.get_env("REDIS_STACK_PORT") || "6379")

  setup do
    {:ok, conn} = Connection.start_link(port: @stack_port)
    suffix = :erlang.unique_integer([:positive])
    idx = "idx:test:#{suffix}"
    prefix = "doc:#{suffix}:"

    on_exit(fn ->
      case Connection.start_link(port: @stack_port) do
        {:ok, cleanup} ->
          Search.drop_index(cleanup, idx, dd: true)
          Connection.stop(cleanup)

        _ ->
          :ok
      end
    end)

    {:ok, conn: conn, idx: idx, prefix: prefix, suffix: suffix}
  end

  describe "create_index/3" do
    test "creates a hash index with keyword fields", %{conn: conn, idx: idx, prefix: prefix} do
      assert :ok =
               Search.create_index(conn, idx,
                 prefix: prefix,
                 fields: [
                   name: :text,
                   age: {:numeric, sortable: true},
                   city: :tag
                 ]
               )
    end

    test "creates a JSON index", %{conn: conn, idx: idx, prefix: prefix} do
      assert :ok =
               Search.create_index(conn, idx,
                 on: :json,
                 prefix: prefix,
                 fields: [
                   title: :text,
                   score: {:numeric, sortable: true}
                 ]
               )
    end

    test "returns error for duplicate index", %{conn: conn, idx: idx, prefix: prefix} do
      :ok = Search.create_index(conn, idx, prefix: prefix, fields: [name: :text])
      assert {:error, _} = Search.create_index(conn, idx, prefix: prefix, fields: [name: :text])
    end
  end

  describe "add/5 and find/4" do
    test "adds hash documents and searches them", %{conn: conn, idx: idx, prefix: prefix} do
      :ok =
        Search.create_index(conn, idx,
          prefix: prefix,
          fields: [
            name: :text,
            age: {:numeric, sortable: true},
            city: :tag
          ]
        )

      Search.add(conn, idx, "#{prefix}1", %{name: "Alice", age: 30, city: "NYC"})
      Search.add(conn, idx, "#{prefix}2", %{name: "Bob", age: 25, city: "LA"})
      Search.add(conn, idx, "#{prefix}3", %{name: "Charlie", age: 35, city: "NYC"})

      Process.sleep(200)

      # Full-text search
      {:ok, result} = Search.find(conn, idx, "Alice")
      assert result.total >= 1
      assert Enum.any?(result.results, &(&1[:id] == "#{prefix}1"))
    end

    test "find with numeric filter", %{conn: conn, idx: idx, prefix: prefix} do
      :ok =
        Search.create_index(conn, idx,
          prefix: prefix,
          fields: [name: :text, age: {:numeric, sortable: true}]
        )

      Search.add(conn, idx, "#{prefix}1", %{name: "Alice", age: 30})
      Search.add(conn, idx, "#{prefix}2", %{name: "Bob", age: 25})
      Search.add(conn, idx, "#{prefix}3", %{name: "Charlie", age: 35})

      Process.sleep(200)

      {:ok, result} = Search.find(conn, idx, "*", where: [age: {:gt, 28}])
      assert result.total >= 2

      ids = Enum.map(result.results, & &1[:id])
      assert "#{prefix}1" in ids
      assert "#{prefix}3" in ids
    end

    test "find with tag filter", %{conn: conn, idx: idx, prefix: prefix} do
      :ok =
        Search.create_index(conn, idx,
          prefix: prefix,
          fields: [name: :text, city: :tag]
        )

      Search.add(conn, idx, "#{prefix}1", %{name: "Alice", city: "NYC"})
      Search.add(conn, idx, "#{prefix}2", %{name: "Bob", city: "LA"})

      Process.sleep(200)

      {:ok, result} = Search.find(conn, idx, "*", where: [city: {:tag, "NYC"}])
      assert result.total >= 1
      assert Enum.any?(result.results, &(&1[:id] == "#{prefix}1"))
    end

    test "find with tag OR filter", %{conn: conn, idx: idx, prefix: prefix} do
      :ok =
        Search.create_index(conn, idx,
          prefix: prefix,
          fields: [name: :text, city: :tag]
        )

      Search.add(conn, idx, "#{prefix}1", %{name: "Alice", city: "NYC"})
      Search.add(conn, idx, "#{prefix}2", %{name: "Bob", city: "LA"})
      Search.add(conn, idx, "#{prefix}3", %{name: "Charlie", city: "Chicago"})

      Process.sleep(200)

      {:ok, result} = Search.find(conn, idx, "*", where: [city: {:any, ["NYC", "LA"]}])
      assert result.total >= 2
    end

    test "find with sort and limit", %{conn: conn, idx: idx, prefix: prefix} do
      :ok =
        Search.create_index(conn, idx,
          prefix: prefix,
          fields: [name: :text, age: {:numeric, sortable: true}]
        )

      for {name, age, i} <- [{"Alice", 30, 1}, {"Bob", 25, 2}, {"Charlie", 35, 3}] do
        Search.add(conn, idx, "#{prefix}#{i}", %{name: name, age: age})
      end

      Process.sleep(200)

      {:ok, result} = Search.find(conn, idx, "*", sort: {:age, :asc}, limit: 2)
      assert length(result.results) == 2
      ages = Enum.map(result.results, &(&1["age"] || &1[:age]))
      assert ages == [25, 30]
    end

    test "find with return fields", %{conn: conn, idx: idx, prefix: prefix} do
      :ok =
        Search.create_index(conn, idx,
          prefix: prefix,
          fields: [name: :text, age: {:numeric, sortable: true}, city: :tag]
        )

      Search.add(conn, idx, "#{prefix}1", %{name: "Alice", age: 30, city: "NYC"})

      Process.sleep(200)

      {:ok, result} = Search.find(conn, idx, "*", return: [:name])
      assert [doc] = result.results
      assert doc["name"] == "Alice" or doc[:name] == "Alice"
    end

    test "find with range filter", %{conn: conn, idx: idx, prefix: prefix} do
      :ok =
        Search.create_index(conn, idx,
          prefix: prefix,
          fields: [name: :text, age: {:numeric, sortable: true}]
        )

      for {name, age, i} <- [
            {"Alice", 30, 1},
            {"Bob", 25, 2},
            {"Charlie", 35, 3},
            {"Dave", 20, 4}
          ] do
        Search.add(conn, idx, "#{prefix}#{i}", %{name: name, age: age})
      end

      Process.sleep(200)

      {:ok, result} = Search.find(conn, idx, "*", where: [age: {:between, 25, 32}])
      assert result.total >= 2
    end
  end

  describe "add_many/4" do
    test "bulk adds documents", %{conn: conn, idx: idx, prefix: prefix} do
      :ok = Search.create_index(conn, idx, prefix: prefix, fields: [name: :text])

      docs =
        for i <- 1..5 do
          {"#{prefix}#{i}", %{name: "User #{i}"}}
        end

      {:ok, _} = Search.add_many(conn, idx, docs)

      Process.sleep(200)

      {:ok, result} = Search.find(conn, idx, "*")
      assert result.total >= 5
    end
  end

  describe "aggregate/3" do
    test "groups and counts", %{conn: conn, idx: idx, prefix: prefix} do
      :ok =
        Search.create_index(conn, idx,
          prefix: prefix,
          fields: [name: :text, city: :tag]
        )

      Search.add(conn, idx, "#{prefix}1", %{name: "Alice", city: "NYC"})
      Search.add(conn, idx, "#{prefix}2", %{name: "Bob", city: "NYC"})
      Search.add(conn, idx, "#{prefix}3", %{name: "Charlie", city: "LA"})

      Process.sleep(200)

      {:ok, result} =
        Search.aggregate(conn, idx,
          group_by: :city,
          reduce: [count: "total"],
          sort: {:total, :desc}
        )

      assert result.total >= 1
      assert [_ | _] = result.results
    end
  end

  describe "coercion" do
    test "auto-coerces numeric strings when coerce: true", %{
      conn: conn,
      idx: idx,
      prefix: prefix
    } do
      :ok =
        Search.create_index(conn, idx,
          prefix: prefix,
          fields: [name: :text, age: {:numeric, sortable: true}]
        )

      Search.add(conn, idx, "#{prefix}1", %{name: "Alice", age: 30})

      Process.sleep(200)

      {:ok, result} = Search.find(conn, idx, "*", coerce: true)
      doc = hd(result.results)
      assert is_integer(doc["age"])
    end

    test "preserves strings when coerce: false", %{conn: conn, idx: idx, prefix: prefix} do
      :ok =
        Search.create_index(conn, idx,
          prefix: prefix,
          fields: [name: :text, age: {:numeric, sortable: true}]
        )

      Search.add(conn, idx, "#{prefix}1", %{name: "Alice", age: 30})

      Process.sleep(200)

      {:ok, result} = Search.find(conn, idx, "*", coerce: false)
      doc = hd(result.results)
      assert is_binary(doc["age"])
    end
  end

  describe "drop_index/3" do
    test "drops an index", %{conn: conn, idx: idx, prefix: prefix} do
      :ok = Search.create_index(conn, idx, prefix: prefix, fields: [name: :text])
      assert :ok = Search.drop_index(conn, idx)
    end
  end

  describe "Result struct" do
    test "has expected fields" do
      r = %Search.Result{total: 5, results: [%{id: "x"}]}
      assert r.total == 5
      assert [%{id: "x"}] = r.results
    end
  end
end

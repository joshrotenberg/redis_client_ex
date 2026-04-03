defmodule Redis.JSONTest do
  use ExUnit.Case, async: false

  @moduletag :redis_stack

  @stack_port String.to_integer(System.get_env("REDIS_STACK_PORT") || "6379")

  setup do
    {:ok, conn} = Redis.Connection.start_link(port: @stack_port)
    suffix = :erlang.unique_integer([:positive])
    key = "json:test:#{suffix}"

    on_exit(fn ->
      case Redis.Connection.start_link(port: @stack_port) do
        {:ok, cleanup} ->
          Redis.Connection.command(cleanup, ["DEL", key, "#{key}:2", "#{key}:3"])
          Redis.Connection.stop(cleanup)

        _ ->
          :ok
      end
    end)

    {:ok, conn: conn, key: key}
  end

  describe "set/4 and get/3" do
    test "round-trips a map", %{conn: conn, key: key} do
      assert {:ok, "OK"} = Redis.JSON.set(conn, key, %{name: "Alice", age: 30})

      {:ok, doc} = Redis.JSON.get(conn, key)
      assert doc["name"] == "Alice"
      assert doc["age"] == 30
    end

    test "get with field selection", %{conn: conn, key: key} do
      Redis.JSON.set(conn, key, %{name: "Alice", age: 30, city: "NYC"})

      {:ok, doc} = Redis.JSON.get(conn, key, fields: [:name, :age])
      assert doc["name"] == "Alice"
      assert doc["age"] == 30
      refute Map.has_key?(doc, "city")
    end

    test "get with atom_keys", %{conn: conn, key: key} do
      Redis.JSON.set(conn, key, %{name: "Alice", age: 30})

      {:ok, doc} = Redis.JSON.get(conn, key, atom_keys: true)
      assert doc[:name] == "Alice"
      assert doc[:age] == 30
    end

    test "get returns nil for missing key", %{conn: conn} do
      assert {:ok, nil} = Redis.JSON.get(conn, "nonexistent:key")
    end

    test "set with nx only sets if new", %{conn: conn, key: key} do
      assert {:ok, "OK"} = Redis.JSON.set(conn, key, %{a: 1})
      assert {:ok, nil} = Redis.JSON.set(conn, key, %{a: 2}, nx: true)

      {:ok, doc} = Redis.JSON.get(conn, key)
      assert doc["a"] == 1
    end
  end

  describe "put/4" do
    test "sets a value at an atom path", %{conn: conn, key: key} do
      Redis.JSON.set(conn, key, %{name: "Alice"})

      assert {:ok, "OK"} = Redis.JSON.put(conn, key, :status, "online")

      {:ok, doc} = Redis.JSON.get(conn, key)
      assert doc["status"] == "online"
    end

    test "sets a value at a nested list path", %{conn: conn, key: key} do
      Redis.JSON.set(conn, key, %{address: %{city: "NYC", zip: "10001"}})

      assert {:ok, "OK"} = Redis.JSON.put(conn, key, [:address, :city], "LA")

      {:ok, doc} = Redis.JSON.get(conn, key)
      assert doc["address"]["city"] == "LA"
    end
  end

  describe "merge/4" do
    test "merges fields into a document", %{conn: conn, key: key} do
      Redis.JSON.set(conn, key, %{name: "Alice", age: 30})

      assert {:ok, "OK"} = Redis.JSON.merge(conn, key, %{status: "online", age: 31})

      {:ok, doc} = Redis.JSON.get(conn, key)
      assert doc["name"] == "Alice"
      assert doc["status"] == "online"
      assert doc["age"] == 31
    end
  end

  describe "del/3" do
    test "deletes entire document", %{conn: conn, key: key} do
      Redis.JSON.set(conn, key, %{name: "Alice"})

      assert {:ok, 1} = Redis.JSON.del(conn, key)
      assert {:ok, nil} = Redis.JSON.get(conn, key)
    end

    test "deletes a specific field", %{conn: conn, key: key} do
      Redis.JSON.set(conn, key, %{name: "Alice", temp: "remove_me"})

      assert {:ok, 1} = Redis.JSON.del(conn, key, :temp)

      {:ok, doc} = Redis.JSON.get(conn, key)
      assert doc["name"] == "Alice"
      refute Map.has_key?(doc, "temp")
    end
  end

  describe "type/3" do
    test "returns type of root", %{conn: conn, key: key} do
      Redis.JSON.set(conn, key, %{name: "Alice"})
      assert {:ok, :object} = Redis.JSON.type(conn, key)
    end

    test "returns type of nested path", %{conn: conn, key: key} do
      Redis.JSON.set(conn, key, %{name: "Alice", tags: ["admin"]})
      assert {:ok, :array} = Redis.JSON.type(conn, key, :tags)
    end
  end

  describe "exists?/2" do
    test "returns true for existing key", %{conn: conn, key: key} do
      Redis.JSON.set(conn, key, %{a: 1})
      assert Redis.JSON.exists?(conn, key)
    end

    test "returns false for missing key", %{conn: conn} do
      refute Redis.JSON.exists?(conn, "nonexistent:json:key")
    end
  end

  describe "incr/4" do
    test "increments an integer", %{conn: conn, key: key} do
      Redis.JSON.set(conn, key, %{counter: 10})

      assert {:ok, 15} = Redis.JSON.incr(conn, key, :counter, 5)
    end

    test "increments a float", %{conn: conn, key: key} do
      Redis.JSON.set(conn, key, %{score: 10.0})

      {:ok, result} = Redis.JSON.incr(conn, key, :score, 1.5)
      assert_in_delta result, 11.5, 0.01
    end
  end

  describe "toggle/3" do
    test "toggles a boolean", %{conn: conn, key: key} do
      Redis.JSON.set(conn, key, %{active: true})

      assert {:ok, val} = Redis.JSON.toggle(conn, key, :active)
      # Redis returns 0/1 for toggle
      assert val in [false, 0]
    end
  end

  describe "array operations" do
    test "append adds to array", %{conn: conn, key: key} do
      Redis.JSON.set(conn, key, %{tags: ["a", "b"]})

      assert {:ok, 3} = Redis.JSON.append(conn, key, :tags, "c")

      {:ok, doc} = Redis.JSON.get(conn, key)
      assert doc["tags"] == ["a", "b", "c"]
    end

    test "append multiple values", %{conn: conn, key: key} do
      Redis.JSON.set(conn, key, %{tags: ["a"]})

      assert {:ok, 3} = Redis.JSON.append(conn, key, :tags, ["b", "c"])

      {:ok, doc} = Redis.JSON.get(conn, key)
      assert doc["tags"] == ["a", "b", "c"]
    end

    test "pop removes last element", %{conn: conn, key: key} do
      Redis.JSON.set(conn, key, %{tags: ["a", "b", "c"]})

      {:ok, popped} = Redis.JSON.pop(conn, key, :tags)
      assert popped == "c"

      {:ok, doc} = Redis.JSON.get(conn, key)
      assert doc["tags"] == ["a", "b"]
    end

    test "length returns array size", %{conn: conn, key: key} do
      Redis.JSON.set(conn, key, %{tags: ["a", "b", "c"]})

      assert {:ok, 3} = Redis.JSON.length(conn, key, :tags)
    end
  end

  describe "mget/4" do
    test "gets a field from multiple keys", %{conn: conn, key: key} do
      Redis.JSON.set(conn, "#{key}:2", %{name: "Alice"})
      Redis.JSON.set(conn, "#{key}:3", %{name: "Bob"})

      {:ok, names} = Redis.JSON.mget(conn, ["#{key}:2", "#{key}:3"], :name)
      assert names == ["Alice", "Bob"]
    end
  end

  describe "path building" do
    test "atom path", %{conn: conn, key: key} do
      Redis.JSON.set(conn, key, %{name: "Alice"})
      {:ok, doc} = Redis.JSON.get(conn, key, fields: [:name])
      assert doc["name"] == "Alice"
    end

    test "string path passthrough", %{conn: conn, key: key} do
      Redis.JSON.set(conn, key, %{nested: %{deep: "value"}})

      # Use raw JSONPath
      Redis.JSON.put(conn, key, "$.nested.deep", "updated")
      {:ok, doc} = Redis.JSON.get(conn, key)
      assert doc["nested"]["deep"] == "updated"
    end
  end
end

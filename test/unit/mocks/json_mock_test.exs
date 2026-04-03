defmodule Redis.JSON.MockTest do
  use ExUnit.Case, async: true

  # A simple GenServer that returns canned responses in order and records
  # every command it receives. Works because Redis.Connection.command/2
  # does GenServer.call(conn, {:command, args}).
  defmodule TestConn do
    use GenServer

    def start_link(responses), do: GenServer.start_link(__MODULE__, responses)

    @impl true
    def init(responses), do: {:ok, %{responses: responses, calls: []}}

    @impl true
    def handle_call({:command, args}, _from, state) do
      [response | rest] = state.responses
      {:reply, response, %{state | responses: rest, calls: state.calls ++ [args]}}
    end

    def handle_call(:calls, _from, state), do: {:reply, state.calls, state}

    def calls(pid), do: GenServer.call(pid, :calls)
  end

  describe "set/3" do
    test "encodes map and sends JSON.SET command" do
      {:ok, conn} = TestConn.start_link([{:ok, "OK"}])

      assert {:ok, "OK"} = Redis.JSON.set(conn, "doc:1", %{name: "Alice"})

      [[cmd, key, path, json]] = TestConn.calls(conn)
      assert cmd == "JSON.SET"
      assert key == "doc:1"
      assert path == "$"
      assert Jason.decode!(json) == %{"name" => "Alice"}
    end
  end

  describe "get/3" do
    test "decodes JSON response and unwraps JSONPath array" do
      doc = Jason.encode!([%{"name" => "Alice", "age" => 30}])
      {:ok, conn} = TestConn.start_link([{:ok, doc}])

      assert {:ok, %{"name" => "Alice", "age" => 30}} = Redis.JSON.get(conn, "doc:1")

      assert [["JSON.GET", "doc:1", "$"]] = TestConn.calls(conn)
    end

    test "with fields sends correct paths" do
      response = Jason.encode!(%{"$.name" => ["Alice"], "$.age" => [30]})
      {:ok, conn} = TestConn.start_link([{:ok, response}])

      assert {:ok, %{"name" => "Alice", "age" => 30}} =
               Redis.JSON.get(conn, "doc:1", fields: [:name, :age])

      assert [["JSON.GET", "doc:1", "$.name", "$.age"]] = TestConn.calls(conn)
    end

    test "with atom_keys returns atom keys" do
      doc = Jason.encode!([%{"name" => "Alice"}])
      {:ok, conn} = TestConn.start_link([{:ok, doc}])

      assert {:ok, %{name: "Alice"}} = Redis.JSON.get(conn, "doc:1", atom_keys: true)
    end

    test "returns nil for missing key" do
      {:ok, conn} = TestConn.start_link([{:ok, nil}])

      assert {:ok, nil} = Redis.JSON.get(conn, "missing")
    end
  end

  describe "put/4" do
    test "builds correct path from atom" do
      {:ok, conn} = TestConn.start_link([{:ok, "OK"}])

      assert {:ok, "OK"} = Redis.JSON.put(conn, "doc:1", :status, "online")

      [[_cmd, _key, path, json]] = TestConn.calls(conn)
      assert path == "$.status"
      assert Jason.decode!(json) == "online"
    end

    test "builds correct path from list" do
      {:ok, conn} = TestConn.start_link([{:ok, "OK"}])

      assert {:ok, "OK"} = Redis.JSON.put(conn, "doc:1", [:address, :city], "NYC")

      [[_cmd, _key, path, _json]] = TestConn.calls(conn)
      assert path == "$.address.city"
    end

    test "passes through string path as-is" do
      {:ok, conn} = TestConn.start_link([{:ok, "OK"}])

      assert {:ok, "OK"} = Redis.JSON.put(conn, "doc:1", "$.custom[0]", "val")

      [[_cmd, _key, path, _json]] = TestConn.calls(conn)
      assert path == "$.custom[0]"
    end
  end

  describe "del/3" do
    test "sends JSON.DEL command" do
      {:ok, conn} = TestConn.start_link([{:ok, 1}])

      assert {:ok, 1} = Redis.JSON.del(conn, "doc:1")

      assert [["JSON.DEL", "doc:1", "$"]] = TestConn.calls(conn)
    end
  end

  describe "incr/4" do
    test "unwraps numeric result from array" do
      {:ok, conn} = TestConn.start_link([{:ok, [31]}])

      assert {:ok, 31} = Redis.JSON.incr(conn, "doc:1", :age, 1)

      assert [["JSON.NUMINCRBY", "doc:1", "$.age", "1"]] = TestConn.calls(conn)
    end

    test "parses string numeric result" do
      {:ok, conn} = TestConn.start_link([{:ok, "42"}])

      assert {:ok, 42} = Redis.JSON.incr(conn, "doc:1", :counter, 1)
    end
  end

  describe "append/4" do
    test "sends JSON.ARRAPPEND with encoded value" do
      {:ok, conn} = TestConn.start_link([{:ok, [3]}])

      assert {:ok, 3} = Redis.JSON.append(conn, "doc:1", :tags, "admin")

      [[cmd, key, path | values]] = TestConn.calls(conn)
      assert cmd == "JSON.ARRAPPEND"
      assert key == "doc:1"
      assert path == "$.tags"
      assert values == [Jason.encode!("admin")]
    end
  end

  describe "exists?/2" do
    test "returns true when TYPE returns a type" do
      {:ok, conn} = TestConn.start_link([{:ok, ["object"]}])

      assert Redis.JSON.exists?(conn, "doc:1") == true
    end

    test "returns false when TYPE returns nil" do
      {:ok, conn} = TestConn.start_link([{:ok, nil}])

      assert Redis.JSON.exists?(conn, "doc:1") == false
    end

    test "returns false on error" do
      {:ok, conn} = TestConn.start_link([{:error, "WRONGTYPE"}])

      assert Redis.JSON.exists?(conn, "doc:1") == false
    end
  end
end

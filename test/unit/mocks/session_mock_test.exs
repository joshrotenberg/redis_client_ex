defmodule Redis.PlugSession.MockTest do
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

  defp default_opts(conn) do
    %{conn: conn, prefix: "plug:session:", ttl: 3600}
  end

  describe "init/1" do
    test "extracts options correctly" do
      opts = Redis.PlugSession.init(table: :my_redis, prefix: "sess:", ttl: 7200)

      assert opts == %{conn: :my_redis, prefix: "sess:", ttl: 7200}
    end

    test "uses default prefix and ttl" do
      opts = Redis.PlugSession.init(table: :my_redis)

      assert opts == %{conn: :my_redis, prefix: "plug:session:", ttl: 86_400}
    end
  end

  describe "put/4" do
    test "with nil sid generates a new session ID" do
      {:ok, conn} = TestConn.start_link([{:ok, "OK"}])
      opts = default_opts(conn)

      sid = Redis.PlugSession.put(nil, nil, %{user: "alice"}, opts)

      assert is_binary(sid)
      assert byte_size(sid) > 0

      [["SET", key, value, "EX", ttl]] = TestConn.calls(conn)
      assert String.starts_with?(key, "plug:session:")
      assert ttl == "3600"
      assert :erlang.binary_to_term(value) == %{user: "alice"}
    end

    test "with existing sid reuses it" do
      {:ok, conn} = TestConn.start_link([{:ok, "OK"}])
      opts = default_opts(conn)

      returned_sid = Redis.PlugSession.put(nil, "existing-sid", %{user: "bob"}, opts)

      assert returned_sid == "existing-sid"

      [["SET", key, _value, "EX", _ttl]] = TestConn.calls(conn)
      assert key == "plug:session:existing-sid"
    end

    test "TTL is set via SET EX" do
      {:ok, conn} = TestConn.start_link([{:ok, "OK"}])
      opts = %{conn: conn, prefix: "sess:", ttl: 600}

      Redis.PlugSession.put(nil, "sid-1", %{}, opts)

      [["SET", _key, _value, "EX", ttl]] = TestConn.calls(conn)
      assert ttl == "600"
    end
  end

  describe "get/3" do
    test "returns decoded session data" do
      session_data = %{"user" => "alice", "role" => "admin"}
      serialized = :erlang.term_to_binary(session_data)
      {:ok, conn} = TestConn.start_link([{:ok, serialized}])
      opts = default_opts(conn)

      {cookie, data} = Redis.PlugSession.get(nil, "my-session-id", opts)

      assert cookie == "my-session-id"
      assert data == session_data

      assert [["GET", "plug:session:my-session-id"]] = TestConn.calls(conn)
    end

    test "returns nil for missing session" do
      {:ok, conn} = TestConn.start_link([{:ok, nil}])
      opts = default_opts(conn)

      {cookie, data} = Redis.PlugSession.get(nil, "nonexistent", opts)

      assert cookie == nil
      assert data == %{}
    end

    test "returns nil for empty/nil cookie" do
      {:ok, conn} = TestConn.start_link([])
      opts = default_opts(conn)

      {cookie, data} = Redis.PlugSession.get(nil, nil, opts)

      assert cookie == nil
      assert data == %{}
      # No commands should have been sent
      assert TestConn.calls(conn) == []
    end
  end

  describe "delete/3" do
    test "sends DEL command" do
      {:ok, conn} = TestConn.start_link([{:ok, 1}])
      opts = default_opts(conn)

      assert :ok = Redis.PlugSession.delete(nil, "my-session-id", opts)

      assert [["DEL", "plug:session:my-session-id"]] = TestConn.calls(conn)
    end

    test "returns :ok for nil sid without sending command" do
      {:ok, conn} = TestConn.start_link([])
      opts = default_opts(conn)

      assert :ok = Redis.PlugSession.delete(nil, nil, opts)

      assert TestConn.calls(conn) == []
    end
  end
end

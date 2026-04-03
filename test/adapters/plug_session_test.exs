defmodule Redis.PlugSessionTest do
  use ExUnit.Case, async: false

  alias Redis.Connection

  # Uses redis-server on port 6398 from test_helper.exs

  setup do
    {:ok, conn} =
      Connection.start_link(
        port: 6398,
        name: :"session_test_#{:erlang.unique_integer([:positive])}"
      )

    opts = Redis.PlugSession.init(table: conn, prefix: "test:session:", ttl: 60)

    on_exit(fn ->
      case Connection.start_link(port: 6398) do
        {:ok, cleanup} ->
          {:ok, keys} = Connection.command(cleanup, ["KEYS", "test:session:*"])
          if is_list(keys) and keys != [], do: Connection.command(cleanup, ["DEL" | keys])
          Connection.stop(cleanup)

        _ ->
          :ok
      end
    end)

    {:ok, conn: conn, opts: opts}
  end

  describe "init/1" do
    test "extracts options" do
      opts = Redis.PlugSession.init(table: :redis, prefix: "myapp:", ttl: 3600)
      assert opts.conn == :redis
      assert opts.prefix == "myapp:"
      assert opts.ttl == 3600
    end

    test "uses defaults" do
      opts = Redis.PlugSession.init(table: :redis)
      assert opts.prefix == "plug:session:"
      assert opts.ttl == 86_400
    end
  end

  describe "get/3" do
    test "returns empty session for unknown cookie", %{opts: opts} do
      assert {nil, %{}} = Redis.PlugSession.get(nil, "nonexistent", opts)
    end

    test "returns empty session for empty cookie", %{opts: opts} do
      assert {nil, %{}} = Redis.PlugSession.get(nil, "", opts)
    end

    test "returns empty session for nil cookie", %{opts: opts} do
      assert {nil, %{}} = Redis.PlugSession.get(nil, nil, opts)
    end

    test "returns stored session data", %{conn: conn, opts: opts} do
      # Store data directly
      data = %{"user_id" => 123, "role" => "admin"}
      key = "test:session:my_sid"
      Connection.command(conn, ["SET", key, :erlang.term_to_binary(data), "EX", "60"])

      assert {"my_sid", ^data} = Redis.PlugSession.get(nil, "my_sid", opts)
    end
  end

  describe "put/4" do
    test "creates new session when sid is nil", %{conn: conn, opts: opts} do
      data = %{"user_id" => 42}

      sid = Redis.PlugSession.put(nil, nil, data, opts)

      assert is_binary(sid)
      assert byte_size(sid) > 0

      # Verify it was stored in Redis
      {:ok, stored} = Connection.command(conn, ["GET", "test:session:" <> sid])
      assert :erlang.binary_to_term(stored) == data
    end

    test "updates existing session", %{conn: conn, opts: opts} do
      # Create initial session
      sid = Redis.PlugSession.put(nil, nil, %{"count" => 1}, opts)

      # Update it
      returned_sid = Redis.PlugSession.put(nil, sid, %{"count" => 2}, opts)

      assert returned_sid == sid

      {:ok, stored} = Connection.command(conn, ["GET", "test:session:" <> sid])
      assert %{"count" => 2} = :erlang.binary_to_term(stored)
    end

    test "sets TTL on session key", %{conn: conn, opts: opts} do
      sid = Redis.PlugSession.put(nil, nil, %{"data" => true}, opts)

      {:ok, ttl} = Connection.command(conn, ["TTL", "test:session:" <> sid])
      assert ttl > 0
      assert ttl <= 60
    end

    test "refreshes TTL on update", %{conn: conn, opts: opts} do
      sid = Redis.PlugSession.put(nil, nil, %{}, opts)

      # Wait a moment
      Process.sleep(100)

      # Update should reset TTL
      Redis.PlugSession.put(nil, sid, %{"updated" => true}, opts)

      {:ok, ttl} = Connection.command(conn, ["TTL", "test:session:" <> sid])
      assert ttl > 58
    end
  end

  describe "delete/3" do
    test "removes session from Redis", %{conn: conn, opts: opts} do
      sid = Redis.PlugSession.put(nil, nil, %{"user_id" => 1}, opts)

      # Verify it exists
      {:ok, stored} = Connection.command(conn, ["GET", "test:session:" <> sid])
      assert stored != nil

      # Delete it
      assert :ok = Redis.PlugSession.delete(nil, sid, opts)

      # Verify it's gone
      {:ok, nil} = Connection.command(conn, ["GET", "test:session:" <> sid])
    end

    test "handles nil sid gracefully", %{opts: opts} do
      assert :ok = Redis.PlugSession.delete(nil, nil, opts)
    end
  end

  describe "session round-trip" do
    test "full lifecycle: create, read, update, delete", %{opts: opts} do
      # Create
      data = %{"user_id" => 123, "preferences" => %{"theme" => "dark"}}
      sid = Redis.PlugSession.put(nil, nil, data, opts)
      assert is_binary(sid)

      # Read
      {^sid, ^data} = Redis.PlugSession.get(nil, sid, opts)

      # Update
      updated = Map.put(data, "last_seen", "2026-04-02")
      ^sid = Redis.PlugSession.put(nil, sid, updated, opts)

      # Read again
      {^sid, ^updated} = Redis.PlugSession.get(nil, sid, opts)

      # Delete
      :ok = Redis.PlugSession.delete(nil, sid, opts)

      # Read after delete
      {nil, %{}} = Redis.PlugSession.get(nil, sid, opts)
    end
  end
end

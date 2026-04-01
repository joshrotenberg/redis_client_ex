defmodule Redis.ScriptTest do
  use ExUnit.Case, async: false

  alias Redis.Script
  alias Redis.Connection

  # Uses redis-server on port 6398 from test_helper.exs

  describe "Script.new/1" do
    test "computes SHA1 from source" do
      script = Script.new("return 1")
      assert is_binary(script.sha)
      assert String.length(script.sha) == 40
      assert script.source == "return 1"
    end

    test "same source produces same SHA1" do
      s1 = Script.new("return 1")
      s2 = Script.new("return 1")
      assert s1.sha == s2.sha
    end

    test "different source produces different SHA1" do
      s1 = Script.new("return 1")
      s2 = Script.new("return 2")
      refute s1.sha == s2.sha
    end
  end

  describe "Script.eval/3" do
    setup do
      {:ok, conn} = Connection.start_link(port: 6398)
      Connection.command(conn, ["SCRIPT", "FLUSH", "SYNC"])
      Connection.command(conn, ["FLUSHDB"])
      {:ok, conn: conn}
    end

    test "evaluates a simple script", %{conn: conn} do
      script = Script.new("return 42")
      assert {:ok, 42} = Script.eval(conn, script)
    end

    test "uses EVALSHA on second call (script cached)", %{conn: conn} do
      script = Script.new("return 'hello'")

      # First call: EVALSHA fails (NOSCRIPT), falls back to EVAL
      assert {:ok, "hello"} = Script.eval(conn, script)

      # Second call: EVALSHA succeeds (script now cached)
      assert {:ok, "hello"} = Script.eval(conn, script)
    end

    test "passes keys and args", %{conn: conn} do
      Connection.command(conn, ["SET", "mykey", "myvalue"])

      script = Script.new("return redis.call('GET', KEYS[1])")
      assert {:ok, "myvalue"} = Script.eval(conn, script, keys: ["mykey"])
    end

    test "passes multiple keys and args", %{conn: conn} do
      script = Script.new("redis.call('SET', KEYS[1], ARGV[1]) redis.call('SET', KEYS[2], ARGV[2]) return 'ok'")
      assert {:ok, "ok"} = Script.eval(conn, script, keys: ["k1", "k2"], args: ["v1", "v2"])

      assert {:ok, "v1"} = Connection.command(conn, ["GET", "k1"])
      assert {:ok, "v2"} = Connection.command(conn, ["GET", "k2"])
    end

    test "returns script errors", %{conn: conn} do
      script = Script.new("return redis.call('INVALID_COMMAND')")
      assert {:error, %Redis.Error{}} = Script.eval(conn, script)
    end
  end

  describe "Script.eval!/3" do
    test "returns value on success" do
      {:ok, conn} = Connection.start_link(port: 6398)
      script = Script.new("return 99")
      assert 99 = Script.eval!(conn, script)
      Connection.stop(conn)
    end

    test "raises on error" do
      {:ok, conn} = Connection.start_link(port: 6398)
      script = Script.new("return redis.call('INVALID')")

      assert_raise RuntimeError, ~r/Script error/, fn ->
        Script.eval!(conn, script)
      end

      Connection.stop(conn)
    end
  end

  describe "Script.load/2" do
    test "pre-loads script into cache" do
      {:ok, conn} = Connection.start_link(port: 6398)
      Connection.command(conn, ["SCRIPT", "FLUSH", "SYNC"])

      script = Script.new("return 'preloaded'")
      refute Script.exists?(conn, script)

      assert :ok = Script.load(conn, script)
      assert Script.exists?(conn, script)

      Connection.stop(conn)
    end
  end

  describe "Script.exists?/2" do
    test "returns false for unknown script" do
      {:ok, conn} = Connection.start_link(port: 6398)
      Connection.command(conn, ["SCRIPT", "FLUSH", "SYNC"])

      script = Script.new("return 'never_loaded_#{System.unique_integer()}'")
      refute Script.exists?(conn, script)

      Connection.stop(conn)
    end
  end
end

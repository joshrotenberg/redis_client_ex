defmodule Redis.FunctionTest do
  use ExUnit.Case, async: false

  alias Redis.Connection
  alias Redis.Function

  # Uses redis-server on port 6398 from test_helper.exs
  # Requires Redis 7.0+ with Functions support

  @lib_code """
  #!lua name=testlib
  redis.register_function('testfunc', function(keys, args)
    return redis.call('GET', keys[1])
  end)
  redis.register_function('testecho', function(keys, args)
    return args[1]
  end)
  redis.register_function('testset', function(keys, args)
    return redis.call('SET', keys[1], args[1])
  end)
  """

  @readonly_lib_code """
  #!lua name=readonlylib
  redis.register_function{
    function_name='readonly_get',
    callback=function(keys, args)
      return redis.call('GET', keys[1])
    end,
    flags={'no-writes'}
  }
  """

  setup do
    {:ok, conn} = Connection.start_link(port: 6398)

    # Clean up functions and data before each test
    Connection.command(conn, ["FUNCTION", "FLUSH", "SYNC"])
    Connection.command(conn, ["FLUSHDB"])

    {:ok, conn: conn}
  end

  describe "load/3" do
    test "loads a function library", %{conn: conn} do
      assert :ok = Function.load(conn, @lib_code)
    end

    test "returns error loading duplicate library", %{conn: conn} do
      assert :ok = Function.load(conn, @lib_code)
      assert {:error, %Redis.Error{}} = Function.load(conn, @lib_code)
    end

    test "replaces existing library with replace option", %{conn: conn} do
      assert :ok = Function.load(conn, @lib_code)
      assert :ok = Function.load(conn, @lib_code, replace: true)
    end
  end

  describe "delete/2" do
    test "deletes a loaded library", %{conn: conn} do
      Function.load(conn, @lib_code)
      assert :ok = Function.delete(conn, "testlib")
    end

    test "returns error for non-existent library", %{conn: conn} do
      assert {:error, %Redis.Error{}} = Function.delete(conn, "nonexistent")
    end
  end

  describe "call/3" do
    test "calls a function without keys or args", %{conn: conn} do
      code = """
      #!lua name=simplelib
      redis.register_function('simplefunc', function(keys, args)
        return 42
      end)
      """

      Function.load(conn, code)
      assert {:ok, 42} = Function.call(conn, "simplefunc")
    end

    test "calls a function with keys", %{conn: conn} do
      Function.load(conn, @lib_code)
      Connection.command(conn, ["SET", "mykey", "myvalue"])

      assert {:ok, "myvalue"} = Function.call(conn, "testfunc", keys: ["mykey"])
    end

    test "calls a function with keys and args", %{conn: conn} do
      Function.load(conn, @lib_code)

      assert {:ok, "OK"} = Function.call(conn, "testset", keys: ["k1"], args: ["v1"])
      assert {:ok, "v1"} = Connection.command(conn, ["GET", "k1"])
    end

    test "passes args correctly", %{conn: conn} do
      Function.load(conn, @lib_code)

      assert {:ok, "hello"} = Function.call(conn, "testecho", args: ["hello"])
    end

    test "returns error for non-existent function", %{conn: conn} do
      assert {:error, %Redis.Error{}} = Function.call(conn, "nonexistent")
    end
  end

  describe "call_ro/3" do
    test "calls a read-only function", %{conn: conn} do
      Function.load(conn, @readonly_lib_code)
      Connection.command(conn, ["SET", "rokey", "rovalue"])

      assert {:ok, "rovalue"} = Function.call_ro(conn, "readonly_get", keys: ["rokey"])
    end
  end

  describe "list/2" do
    test "lists loaded libraries", %{conn: conn} do
      Function.load(conn, @lib_code)
      {:ok, libs} = Function.list(conn)

      assert is_list(libs)
      assert libs != []
    end

    test "filters by library name", %{conn: conn} do
      Function.load(conn, @lib_code)
      {:ok, libs} = Function.list(conn, libraryname: "testlib")

      assert is_list(libs)
      assert length(libs) == 1
    end

    test "returns empty list when no libraries match", %{conn: conn} do
      {:ok, libs} = Function.list(conn, libraryname: "nonexistent")
      assert libs == []
    end
  end

  describe "flush/2" do
    test "removes all libraries", %{conn: conn} do
      Function.load(conn, @lib_code)
      assert :ok = Function.flush(conn)

      {:ok, libs} = Function.list(conn)
      assert libs == []
    end

    test "flush with sync mode", %{conn: conn} do
      Function.load(conn, @lib_code)
      assert :ok = Function.flush(conn, mode: :sync)

      {:ok, libs} = Function.list(conn)
      assert libs == []
    end
  end

  describe "dump/1 and restore/3" do
    test "dumps and restores function libraries", %{conn: conn} do
      Function.load(conn, @lib_code)

      {:ok, data} = Function.dump(conn)
      assert is_binary(data)

      # Flush then restore
      Function.flush(conn, mode: :sync)
      assert :ok = Function.restore(conn, data)

      # Verify restored function works
      Connection.command(conn, ["SET", "restored_key", "restored_value"])
      assert {:ok, "restored_value"} = Function.call(conn, "testfunc", keys: ["restored_key"])
    end

    test "restore with replace option", %{conn: conn} do
      Function.load(conn, @lib_code)
      {:ok, data} = Function.dump(conn)

      # Restore with replace (library already exists)
      assert :ok = Function.restore(conn, data, replace: true)
    end
  end

  describe "stats/1" do
    test "returns function stats", %{conn: conn} do
      {:ok, stats} = Function.stats(conn)
      assert is_map(stats) or is_list(stats)
    end
  end
end

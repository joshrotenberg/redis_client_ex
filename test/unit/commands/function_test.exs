defmodule Redis.Commands.FunctionTest do
  use ExUnit.Case, async: true

  alias Redis.Commands.Function

  describe "FCALL" do
    test "without keys or args" do
      assert Function.fcall("myfunc") == ["FCALL", "myfunc", "0"]
    end

    test "with keys and args" do
      assert Function.fcall("myfunc", ["k1"], ["a1"]) ==
               ["FCALL", "myfunc", "1", "k1", "a1"]
    end

    test "with multiple keys" do
      assert Function.fcall("myfunc", ["k1", "k2", "k3"], []) ==
               ["FCALL", "myfunc", "3", "k1", "k2", "k3"]
    end
  end

  describe "FCALL_RO" do
    test "without keys or args" do
      assert Function.fcall_ro("myfunc") == ["FCALL_RO", "myfunc", "0"]
    end

    test "with keys and args" do
      assert Function.fcall_ro("myfunc", ["k1", "k2"], ["a1"]) ==
               ["FCALL_RO", "myfunc", "2", "k1", "k2", "a1"]
    end
  end

  describe "FUNCTION LOAD" do
    test "basic" do
      assert Function.load("#!lua name=mylib\nredis.register_function('myfunc', function() end)") ==
               [
                 "FUNCTION",
                 "LOAD",
                 "#!lua name=mylib\nredis.register_function('myfunc', function() end)"
               ]
    end

    test "with replace" do
      assert Function.load("code", replace: true) ==
               ["FUNCTION", "LOAD", "REPLACE", "code"]
    end
  end

  describe "FUNCTION DELETE" do
    test "basic" do
      assert Function.delete("mylib") == ["FUNCTION", "DELETE", "mylib"]
    end
  end

  describe "FUNCTION DUMP" do
    test "basic" do
      assert Function.dump() == ["FUNCTION", "DUMP"]
    end
  end

  describe "FUNCTION RESTORE" do
    test "basic" do
      assert Function.restore("data") == ["FUNCTION", "RESTORE", "data"]
    end

    test "with flush" do
      assert Function.restore("data", flush: true) ==
               ["FUNCTION", "RESTORE", "data", "FLUSH"]
    end

    test "with append" do
      assert Function.restore("data", append: true) ==
               ["FUNCTION", "RESTORE", "data", "APPEND"]
    end

    test "with replace" do
      assert Function.restore("data", replace: true) ==
               ["FUNCTION", "RESTORE", "data", "REPLACE"]
    end
  end

  describe "FUNCTION FLUSH" do
    test "without mode" do
      assert Function.flush() == ["FUNCTION", "FLUSH"]
    end

    test "with async mode" do
      assert Function.flush(mode: :async) == ["FUNCTION", "FLUSH", "ASYNC"]
    end

    test "with sync mode" do
      assert Function.flush(mode: :sync) == ["FUNCTION", "FLUSH", "SYNC"]
    end
  end

  describe "FUNCTION LIST" do
    test "without options" do
      assert Function.list() == ["FUNCTION", "LIST"]
    end

    test "with libraryname" do
      assert Function.list(libraryname: "mylib") ==
               ["FUNCTION", "LIST", "LIBRARYNAME", "mylib"]
    end

    test "with withcode" do
      assert Function.list(withcode: true) == ["FUNCTION", "LIST", "WITHCODE"]
    end

    test "with both options" do
      assert Function.list(libraryname: "mylib", withcode: true) ==
               ["FUNCTION", "LIST", "LIBRARYNAME", "mylib", "WITHCODE"]
    end
  end

  describe "FUNCTION STATS" do
    test "basic" do
      assert Function.stats() == ["FUNCTION", "STATS"]
    end
  end
end

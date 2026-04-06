defmodule Redis.Commands.ScriptExpandedTest do
  use ExUnit.Case, async: true

  alias Redis.Commands.Script

  describe "EVAL" do
    test "without keys or args" do
      assert Script.eval("return 1") == ["EVAL", "return 1", "0"]
    end

    test "with keys and args" do
      assert Script.eval("return redis.call('GET', KEYS[1])", ["key1"], ["arg1"]) ==
               ["EVAL", "return redis.call('GET', KEYS[1])", "1", "key1", "arg1"]
    end
  end

  describe "EVALSHA" do
    test "without keys or args" do
      assert Script.evalsha("abc123") == ["EVALSHA", "abc123", "0"]
    end

    test "with keys" do
      assert Script.evalsha("abc123", ["k1", "k2"]) ==
               ["EVALSHA", "abc123", "2", "k1", "k2"]
    end
  end

  describe "EVAL_RO" do
    test "basic" do
      assert Script.eval_ro("return 1", ["k1"], ["a1"]) ==
               ["EVAL_RO", "return 1", "1", "k1", "a1"]
    end
  end

  describe "EVALSHA_RO" do
    test "basic" do
      assert Script.evalsha_ro("sha1", ["k1"]) == ["EVALSHA_RO", "sha1", "1", "k1"]
    end
  end

  describe "SCRIPT EXISTS" do
    test "basic" do
      assert Script.script_exists(["sha1", "sha2"]) == ["SCRIPT", "EXISTS", "sha1", "sha2"]
    end
  end

  describe "SCRIPT FLUSH" do
    test "without async" do
      assert Script.script_flush() == ["SCRIPT", "FLUSH"]
    end

    test "with async" do
      assert Script.script_flush(async: true) == ["SCRIPT", "FLUSH", "ASYNC"]
    end
  end

  describe "SCRIPT KILL" do
    test "basic" do
      assert Script.script_kill() == ["SCRIPT", "KILL"]
    end
  end

  describe "SCRIPT LOAD" do
    test "basic" do
      assert Script.script_load("return 1") == ["SCRIPT", "LOAD", "return 1"]
    end
  end

  describe "FCALL" do
    test "without keys or args" do
      assert Script.fcall("myfunc") == ["FCALL", "myfunc", "0"]
    end

    test "with keys and args" do
      assert Script.fcall("myfunc", ["k1"], ["a1"]) ==
               ["FCALL", "myfunc", "1", "k1", "a1"]
    end
  end

  describe "FCALL_RO" do
    test "without keys or args" do
      assert Script.fcall_ro("myfunc") == ["FCALL_RO", "myfunc", "0"]
    end

    test "with keys and args" do
      assert Script.fcall_ro("myfunc", ["k1", "k2"], ["a1"]) ==
               ["FCALL_RO", "myfunc", "2", "k1", "k2", "a1"]
    end
  end

  describe "FUNCTION LOAD" do
    test "basic" do
      assert Script.function_load(
               "#!lua name=mylib\nredis.register_function('myfunc', function() end)"
             ) ==
               [
                 "FUNCTION",
                 "LOAD",
                 "#!lua name=mylib\nredis.register_function('myfunc', function() end)"
               ]
    end

    test "with replace" do
      cmd = Script.function_load("code", replace: true)
      assert cmd == ["FUNCTION", "LOAD", "REPLACE", "code"]
    end
  end

  describe "FUNCTION DELETE" do
    test "basic" do
      assert Script.function_delete("mylib") == ["FUNCTION", "DELETE", "mylib"]
    end
  end

  describe "FUNCTION LIST" do
    test "without options" do
      assert Script.function_list() == ["FUNCTION", "LIST"]
    end

    test "with libraryname" do
      assert Script.function_list(libraryname: "mylib") ==
               ["FUNCTION", "LIST", "LIBRARYNAME", "mylib"]
    end

    test "with withcode" do
      assert Script.function_list(withcode: true) == ["FUNCTION", "LIST", "WITHCODE"]
    end
  end

  describe "FUNCTION DUMP" do
    test "basic" do
      assert Script.function_dump() == ["FUNCTION", "DUMP"]
    end
  end

  describe "FUNCTION RESTORE" do
    test "basic" do
      assert Script.function_restore("data") == ["FUNCTION", "RESTORE", "data"]
    end

    test "with flush" do
      assert Script.function_restore("data", flush: true) ==
               ["FUNCTION", "RESTORE", "data", "FLUSH"]
    end

    test "with append" do
      assert Script.function_restore("data", append: true) ==
               ["FUNCTION", "RESTORE", "data", "APPEND"]
    end

    test "with replace" do
      assert Script.function_restore("data", replace: true) ==
               ["FUNCTION", "RESTORE", "data", "REPLACE"]
    end
  end

  describe "FUNCTION FLUSH" do
    test "without mode" do
      assert Script.function_flush() == ["FUNCTION", "FLUSH"]
    end

    test "with async mode" do
      assert Script.function_flush(mode: :async) == ["FUNCTION", "FLUSH", "ASYNC"]
    end

    test "with sync mode" do
      assert Script.function_flush(mode: :sync) == ["FUNCTION", "FLUSH", "SYNC"]
    end
  end

  describe "FUNCTION STATS" do
    test "basic" do
      assert Script.function_stats() == ["FUNCTION", "STATS"]
    end
  end
end

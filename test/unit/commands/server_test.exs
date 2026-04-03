defmodule Redis.Commands.ServerExpandedTest do
  use ExUnit.Case, async: true

  alias Redis.Commands.Server

  describe "PING" do
    test "without message" do
      assert Server.ping() == ["PING"]
    end

    test "with message" do
      assert Server.ping("hello") == ["PING", "hello"]
    end
  end

  describe "INFO" do
    test "without section" do
      assert Server.info() == ["INFO"]
    end

    test "with section" do
      assert Server.info("memory") == ["INFO", "memory"]
    end
  end

  describe "DBSIZE" do
    test "basic" do
      assert Server.dbsize() == ["DBSIZE"]
    end
  end

  describe "FLUSHDB" do
    test "without async" do
      assert Server.flushdb() == ["FLUSHDB"]
    end

    test "with async" do
      assert Server.flushdb(async: true) == ["FLUSHDB", "ASYNC"]
    end
  end

  describe "ECHO" do
    test "basic" do
      assert Server.echo("hello") == ["ECHO", "hello"]
    end
  end

  describe "SHUTDOWN" do
    test "without options" do
      assert Server.shutdown() == ["SHUTDOWN"]
    end

    test "with NOSAVE" do
      assert Server.shutdown(nosave: true) == ["SHUTDOWN", "NOSAVE"]
    end

    test "with SAVE" do
      assert Server.shutdown(save: true) == ["SHUTDOWN", "SAVE"]
    end

    test "with NOW and FORCE" do
      assert Server.shutdown(now: true, force: true) == ["SHUTDOWN", "NOW", "FORCE"]
    end
  end

  describe "LATENCY" do
    test "LATEST" do
      assert Server.latency_latest() == ["LATENCY", "LATEST"]
    end

    test "HISTORY" do
      assert Server.latency_history("command") == ["LATENCY", "HISTORY", "command"]
    end

    test "RESET without events" do
      assert Server.latency_reset() == ["LATENCY", "RESET"]
    end

    test "RESET with events" do
      assert Server.latency_reset(events: ["command", "fast-command"]) ==
               ["LATENCY", "RESET", "command", "fast-command"]
    end
  end

  describe "WAITAOF" do
    test "basic" do
      assert Server.waitaof(1, 0, 5000) == ["WAITAOF", "1", "0", "5000"]
    end
  end

  describe "SLAVEOF" do
    test "basic" do
      assert Server.slaveof("host", 6379) == ["SLAVEOF", "host", "6379"]
    end
  end

  describe "CONFIG GET" do
    test "basic" do
      assert Server.config_get("maxmemory") == ["CONFIG", "GET", "maxmemory"]
    end
  end

  describe "CONFIG SET" do
    test "basic" do
      assert Server.config_set("maxmemory", "100mb") == ["CONFIG", "SET", "maxmemory", "100mb"]
    end
  end

  describe "CONFIG RESETSTAT" do
    test "basic" do
      assert Server.config_resetstat() == ["CONFIG", "RESETSTAT"]
    end
  end

  describe "CONFIG REWRITE" do
    test "basic" do
      assert Server.config_rewrite() == ["CONFIG", "REWRITE"]
    end
  end

  describe "ACL LIST" do
    test "basic" do
      assert Server.acl_list() == ["ACL", "LIST"]
    end
  end

  describe "ACL GETUSER" do
    test "basic" do
      assert Server.acl_getuser("default") == ["ACL", "GETUSER", "default"]
    end
  end

  describe "ACL SETUSER" do
    test "without rules" do
      assert Server.acl_setuser("user1") == ["ACL", "SETUSER", "user1"]
    end

    test "with rules" do
      assert Server.acl_setuser("user1", ["on", ">pass", "~*", "+@all"]) ==
               ["ACL", "SETUSER", "user1", "on", ">pass", "~*", "+@all"]
    end
  end

  describe "ACL DELUSER" do
    test "basic" do
      assert Server.acl_deluser(["user1", "user2"]) == ["ACL", "DELUSER", "user1", "user2"]
    end
  end

  describe "ACL CAT" do
    test "without category" do
      assert Server.acl_cat() == ["ACL", "CAT"]
    end

    test "with category" do
      assert Server.acl_cat("string") == ["ACL", "CAT", "string"]
    end
  end

  describe "ACL LOG" do
    test "without options" do
      assert Server.acl_log() == ["ACL", "LOG"]
    end

    test "with reset" do
      assert Server.acl_log(reset: true) == ["ACL", "LOG", "RESET"]
    end

    test "with count" do
      assert Server.acl_log(count: 10) == ["ACL", "LOG", "10"]
    end
  end

  describe "CLIENT SETNAME" do
    test "basic" do
      assert Server.client_setname("myconn") == ["CLIENT", "SETNAME", "myconn"]
    end
  end

  describe "CLIENT GETNAME" do
    test "basic" do
      assert Server.client_getname() == ["CLIENT", "GETNAME"]
    end
  end

  describe "CLIENT ID" do
    test "basic" do
      assert Server.client_id() == ["CLIENT", "ID"]
    end
  end

  describe "CLIENT INFO" do
    test "basic" do
      assert Server.client_info() == ["CLIENT", "INFO"]
    end
  end

  describe "CLIENT LIST" do
    test "without options" do
      assert Server.client_list() == ["CLIENT", "LIST"]
    end

    test "with type" do
      assert Server.client_list(type: "normal") == ["CLIENT", "LIST", "TYPE", "normal"]
    end

    test "with id" do
      assert Server.client_list(id: [1, 2]) == ["CLIENT", "LIST", "ID", "1", "2"]
    end
  end

  describe "CLIENT KILL" do
    test "by id" do
      assert Server.client_kill(id: 42) == ["CLIENT", "KILL", "ID", "42"]
    end

    test "by addr" do
      assert Server.client_kill(addr: "127.0.0.1:6379") ==
               ["CLIENT", "KILL", "ADDR", "127.0.0.1:6379"]
    end

    test "by user" do
      assert Server.client_kill(user: "default") == ["CLIENT", "KILL", "USER", "default"]
    end
  end

  describe "CLIENT TRACKING" do
    test "ON" do
      assert Server.client_tracking(true) == ["CLIENT", "TRACKING", "ON"]
    end

    test "OFF" do
      assert Server.client_tracking(false) == ["CLIENT", "TRACKING", "OFF"]
    end

    test "with redirect and bcast" do
      cmd =
        Server.client_tracking(true,
          redirect: 42,
          bcast: true,
          prefix: ["user:", "session:"],
          noloop: true
        )

      assert "REDIRECT" in cmd
      assert "BCAST" in cmd
      assert "NOLOOP" in cmd
      assert "PREFIX" in cmd
    end
  end

  describe "SLOWLOG" do
    test "GET without count" do
      assert Server.slowlog_get() == ["SLOWLOG", "GET"]
    end

    test "GET with count" do
      assert Server.slowlog_get(10) == ["SLOWLOG", "GET", "10"]
    end

    test "LEN" do
      assert Server.slowlog_len() == ["SLOWLOG", "LEN"]
    end

    test "RESET" do
      assert Server.slowlog_reset() == ["SLOWLOG", "RESET"]
    end
  end

  describe "TIME" do
    test "basic" do
      assert Server.time() == ["TIME"]
    end
  end

  describe "SAVE" do
    test "basic" do
      assert Server.save() == ["SAVE"]
    end
  end

  describe "BGSAVE" do
    test "without schedule" do
      assert Server.bgsave() == ["BGSAVE"]
    end

    test "with schedule" do
      assert Server.bgsave(schedule: true) == ["BGSAVE", "SCHEDULE"]
    end
  end

  describe "BGREWRITEAOF" do
    test "basic" do
      assert Server.bgrewriteaof() == ["BGREWRITEAOF"]
    end
  end

  describe "FLUSHALL" do
    test "without async" do
      assert Server.flushall() == ["FLUSHALL"]
    end

    test "with async" do
      assert Server.flushall(async: true) == ["FLUSHALL", "ASYNC"]
    end
  end

  describe "LASTSAVE" do
    test "basic" do
      assert Server.lastsave() == ["LASTSAVE"]
    end
  end

  describe "ROLE" do
    test "basic" do
      assert Server.role() == ["ROLE"]
    end
  end

  describe "REPLICAOF" do
    test "basic" do
      assert Server.replicaof("host", 6379) == ["REPLICAOF", "host", "6379"]
    end
  end

  describe "COMMAND COUNT" do
    test "basic" do
      assert Server.command_count() == ["COMMAND", "COUNT"]
    end
  end

  describe "COMMAND INFO" do
    test "basic" do
      assert Server.command_info(["get", "set"]) == ["COMMAND", "INFO", "get", "set"]
    end
  end

  describe "COMMAND LIST" do
    test "without filter" do
      assert Server.command_list() == ["COMMAND", "LIST"]
    end

    test "with filterby" do
      assert Server.command_list(filterby: ["MODULE", "mymod"]) ==
               ["COMMAND", "LIST", "FILTERBY", "MODULE", "mymod"]
    end
  end

  describe "DEBUG SLEEP" do
    test "basic" do
      assert Server.debug_sleep(1) == ["DEBUG", "SLEEP", "1"]
    end
  end

  describe "MEMORY USAGE" do
    test "basic" do
      assert Server.memory_usage("key") == ["MEMORY", "USAGE", "key"]
    end

    test "with samples" do
      assert Server.memory_usage("key", samples: 5) ==
               ["MEMORY", "USAGE", "key", "SAMPLES", "5"]
    end
  end

  describe "SWAPDB" do
    test "basic" do
      assert Server.swapdb(0, 1) == ["SWAPDB", "0", "1"]
    end
  end

  describe "OBJECT HELP" do
    test "basic" do
      assert Server.object_help() == ["OBJECT", "HELP"]
    end
  end
end

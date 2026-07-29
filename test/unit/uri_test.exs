defmodule Redis.URITest do
  use ExUnit.Case, async: true

  alias Redis.URI, as: RURI

  describe "parse/1" do
    test "basic host:port" do
      opts = RURI.parse("redis://localhost:6379")
      assert opts[:host] == "localhost"
      assert opts[:port] == 6379
    end

    test "default port" do
      opts = RURI.parse("redis://myhost")
      assert opts[:host] == "myhost"
      assert opts[:port] == 6379
    end

    test "password only" do
      opts = RURI.parse("redis://:secret@localhost:6379")
      assert opts[:password] == "secret"
      assert opts[:host] == "localhost"
      refute opts[:username]
    end

    test "username and password" do
      opts = RURI.parse("redis://alice:s3cret@myhost:6380")
      assert opts[:username] == "alice"
      assert opts[:password] == "s3cret"
      assert opts[:host] == "myhost"
      assert opts[:port] == 6380
    end

    test "database selection" do
      opts = RURI.parse("redis://localhost:6379/2")
      assert opts[:database] == 2
    end

    test "database 0 is omitted" do
      opts = RURI.parse("redis://localhost:6379/0")
      refute Keyword.has_key?(opts, :database)
    end

    test "rediss:// enables SSL" do
      opts = RURI.parse("rediss://localhost:6379")
      assert opts[:ssl] == true
    end

    test "valkey:// uses Redis defaults" do
      opts = RURI.parse("valkey://localhost")
      assert opts[:host] == "localhost"
      assert opts[:port] == 6379
      refute Keyword.has_key?(opts, :ssl)
    end

    test "redis:// does not set SSL" do
      opts = RURI.parse("redis://localhost:6379")
      refute Keyword.has_key?(opts, :ssl)
    end

    test "URL-encoded password" do
      opts = RURI.parse("redis://:p%40ss%3Aword@localhost")
      assert opts[:password] == "p@ss:word"
    end

    test "full URI" do
      opts = RURI.parse("rediss://admin:hunter2@redis.example.com:6380/3")
      assert opts[:host] == "redis.example.com"
      assert opts[:port] == 6380
      assert opts[:username] == "admin"
      assert opts[:password] == "hunter2"
      assert opts[:database] == 3
      assert opts[:ssl] == true
    end

    test "IPv6 host and explicit port" do
      opts = RURI.parse("redis://[::1]:6380/2")
      assert opts[:host] == "::1"
      assert opts[:port] == 6380
      assert opts[:database] == 2
    end

    test "rejects unsupported or hostless URIs" do
      assert_raise ArgumentError, fn -> RURI.parse("http://localhost:6379") end
      assert_raise ArgumentError, fn -> RURI.parse("redis://") end
      assert_raise ArgumentError, fn -> RURI.parse("localhost:6379") end
    end
  end

  describe "to_string/1" do
    test "basic" do
      assert RURI.to_string(host: "localhost", port: 6379) == "redis://localhost:6379"
    end

    test "with password" do
      assert RURI.to_string(host: "h", port: 6379, password: "pw") == "redis://:pw@h:6379"
    end

    test "with SSL" do
      assert RURI.to_string(host: "h", port: 6379, ssl: true) == "rediss://h:6379"
    end

    test "with database" do
      assert RURI.to_string(host: "h", port: 6379, database: 5) == "redis://h:6379/5"
    end

    test "with IPv6 host" do
      assert RURI.to_string(host: "::1", port: 6380) == "redis://[::1]:6380"
    end

    test "with username and no password" do
      assert RURI.to_string(host: "h", username: "alice") == "redis://alice:@h:6379"
    end
  end
end

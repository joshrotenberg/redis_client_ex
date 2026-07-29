defmodule Redis.ResponseTest do
  use ExUnit.Case, async: true

  alias Redis.Response
  alias Redis.Response.{Client, Stream, StreamEntry}

  describe "parse/2 maps and sets" do
    test "normalizes RESP2 and RESP3 HGETALL replies" do
      assert {:ok, %{"name" => "Ada", "role" => "admin"}} =
               Response.parse(["HGETALL", "user:1"], ["name", "Ada", "role", "admin"])

      response = %{"name" => "Ada"}
      assert {:ok, ^response} = Response.parse(["HGETALL", "user:1"], response)
    end

    test "normalizes CONFIG GET and set replies" do
      assert {:ok, %{"maxmemory" => "0"}} =
               Response.parse(["CONFIG", "GET", "maxmemory"], ["maxmemory", "0"])

      assert {:ok, %MapSet{} = members} =
               Response.parse(["SMEMBERS", "letters"], ["a", "b", "a"])

      assert members == MapSet.new(["a", "b"])
    end

    test "reports malformed known replies" do
      assert {:error, %Redis.ResponseError{reason: :odd_map_response}} =
               Response.parse(["HGETALL", "user:1"], ["name"])
    end

    test "passes unknown command replies through" do
      assert {:ok, "OK"} = Response.parse(["SET", "key", "value"], "OK")
    end
  end

  describe "parse/2 INFO" do
    test "returns a flat map and preserves values containing colons" do
      info = """
      # Server
      redis_version:8.0.0
      executable:/usr/local/bin/redis:server

      # Clients
      connected_clients:3
      """

      assert {:ok,
              %{
                "redis_version" => "8.0.0",
                "executable" => "/usr/local/bin/redis:server",
                "connected_clients" => "3"
              }} = Response.parse(["INFO"], info)
    end
  end

  describe "parse/2 CLIENT" do
    test "CLIENT LIST returns structs while retaining every raw attribute" do
      response =
        "id=42 addr=127.0.0.1:5000 laddr=127.0.0.1:6379 fd=8 name=worker " <>
          "age=12 idle=3 flags=N db=2 sub=1 psub=0 ssub=0 multi=-1 " <>
          "cmd=get user=default redir=-1 resp=3 lib-name=redis_client_ex lib-ver=0.7.1"

      assert {:ok,
              [
                %Client{
                  id: 42,
                  addr: "127.0.0.1:5000",
                  name: "worker",
                  age: 12,
                  idle: 3,
                  db: 2,
                  sub: 1,
                  cmd: "get",
                  user: "default",
                  resp: 3,
                  lib_name: "redis_client_ex",
                  lib_ver: "0.7.1",
                  flags: flags,
                  attributes: attributes
                }
              ]} = Response.parse(["CLIENT", "LIST"], response)

      assert flags == MapSet.new(["N"])
      assert attributes["laddr"] == "127.0.0.1:6379"
    end

    test "CLIENT INFO returns one struct" do
      assert {:ok, %Client{id: 7, name: "me"}} =
               Response.parse(["CLIENT", "INFO"], "id=7 name=me flags=N")
    end
  end

  describe "parse/2 streams" do
    test "XRANGE returns structured entries" do
      response = [
        ["1-0", ["event", "created", "actor", "ada"]],
        ["2-0", %{"event" => "updated"}]
      ]

      assert {:ok,
              [
                %StreamEntry{
                  id: "1-0",
                  fields: %{"event" => "created", "actor" => "ada"}
                },
                %StreamEntry{id: "2-0", fields: %{"event" => "updated"}}
              ]} = Response.parse(["XRANGE", "events", "-", "+"], response)
    end

    test "XREAD normalizes RESP2 replies" do
      response = [
        ["events", [["1-0", ["event", "created"]]]],
        ["audit", [["2-0", ["actor", "ada"]]]]
      ]

      assert {:ok,
              [
                %Stream{
                  name: "events",
                  entries: [%StreamEntry{id: "1-0", fields: %{"event" => "created"}}]
                },
                %Stream{
                  name: "audit",
                  entries: [%StreamEntry{id: "2-0", fields: %{"actor" => "ada"}}]
                }
              ]} =
               Response.parse(
                 ["XREAD", "STREAMS", "events", "audit", "0", "0"],
                 response
               )
    end

    test "XREAD preserves command stream order for RESP3 maps" do
      response = %{
        "audit" => [["2-0", ["actor", "ada"]]],
        "events" => [["1-0", ["event", "created"]]]
      }

      assert {:ok, [%Stream{name: "events"}, %Stream{name: "audit"}]} =
               Response.parse(
                 ["XREAD", "STREAMS", "events", "audit", "0", "0"],
                 response
               )
    end

    test "XREAD preserves nil when no streams are ready" do
      assert {:ok, nil} = Response.parse(["XREAD", "STREAMS", "events", "$"], nil)
    end

    test "XREADGROUP represents deleted pending entries with nil fields" do
      assert {:ok,
              [
                %Stream{
                  name: "events",
                  entries: [%StreamEntry{id: "1-0", fields: nil}]
                }
              ]} =
               Response.parse(
                 ["XREADGROUP", "GROUP", "workers", "one", "STREAMS", "events", "0"],
                 [["events", [["1-0", nil]]]]
               )
    end
  end

  describe "decode/3 and decode_many/3" do
    test "raw mode is the default" do
      raw = {:ok, ["name", "Ada"]}
      assert ^raw = Response.decode(raw, ["HGETALL", "user:1"], [])
    end

    test "typed mode parses one reply" do
      assert {:ok, %{"name" => "Ada"}} =
               Response.decode(
                 {:ok, ["name", "Ada"]},
                 ["HGETALL", "user:1"],
                 response: :typed
               )
    end

    test "typed pipelines preserve command errors and parse successful replies" do
      error = %Redis.Error{message: "ERR failure"}

      assert {:ok, [%{"name" => "Ada"}, ^error, "OK"]} =
               Response.decode_many(
                 {:ok, [["name", "Ada"], error, "OK"]},
                 [
                   ["HGETALL", "user:1"],
                   ["HGETALL", "missing"],
                   ["SET", "key", "value"]
                 ],
                 response: :typed
               )
    end

    test "invalid response modes return a descriptive error" do
      assert {:error, %Redis.ResponseError{reason: {:invalid_response_mode, :automatic}} = error} =
               Response.decode({:ok, "PONG"}, ["PING"], response: :automatic)

      assert Exception.message(error) =~ "expected :raw or :typed"
    end
  end
end

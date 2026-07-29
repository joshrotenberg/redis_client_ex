defmodule Redis.ReplicaSet.CommandMetadataTest do
  use ExUnit.Case, async: true

  alias Redis.ReplicaSet.CommandMetadata

  test "extracts read-only commands and subcommands from COMMAND responses" do
    response = [
      ["get", 2, MapSet.new(["readonly", "fast"]), 1, 1, 1, [], [], [], []],
      ["set", -3, MapSet.new(["write"]), 1, 1, 1, [], [], [], []],
      [
        "example",
        -2,
        MapSet.new(),
        0,
        0,
        0,
        [],
        [],
        [],
        [
          ["example|read", 2, ["readonly"], 0, 0, 0, [], [], [], []],
          ["example|write", 2, ["write"], 0, 0, 0, [], [], [], []]
        ]
      ]
    ]

    commands = CommandMetadata.from_command_response(response)

    assert CommandMetadata.read_only?(commands, ["GET", "key"])
    assert CommandMetadata.read_only?(commands, ["EXAMPLE", "READ"])
    refute CommandMetadata.read_only?(commands, ["SET", "key", "value"])
    refute CommandMetadata.read_only?(commands, ["EXAMPLE", "WRITE"])
    refute CommandMetadata.read_only?(commands, ["UNKNOWN", "key"])
  end

  test "ignores malformed command metadata" do
    assert CommandMetadata.from_command_response([:invalid, ["missing", "arity"]]) ==
             MapSet.new()
  end
end

# Protocol Encode/Decode Benchmark
#
# Run with: MIX_ENV=bench mix run bench/protocol_bench.exs
#
# Pure computation -- no Redis server needed.

alias Redis.Protocol.RESP3
alias Redis.Protocol.RESP2

IO.puts("\n=== Protocol Encode/Decode Benchmarks ===\n")

# -------------------------------------------------------------------
# Test data
# -------------------------------------------------------------------

# Encode inputs
cmd_tiny = ["PING"]
cmd_small = ["GET", "mykey"]
cmd_medium = ["SET", "mykey", String.duplicate("x", 100)]
cmd_large = ["MSET"] ++ Enum.flat_map(1..50, &["key:#{&1}", String.duplicate("v", 50)])
pipeline_10 = for _ <- 1..10, do: ["SET", "k", "v"]
pipeline_100 = for _ <- 1..100, do: ["SET", "k", "v"]

# Decode inputs - simple types
simple_string = "+OK\r\n"
simple_error = "-ERR unknown command\r\n"
integer = ":42\r\n"
double = ",3.14159\r\n"
boolean_true = "#t\r\n"
null = "_\r\n"

# Decode inputs - blob types
blob_10 = "$10\r\n" <> String.duplicate("x", 10) <> "\r\n"
blob_1k = "$1000\r\n" <> String.duplicate("x", 1000) <> "\r\n"
blob_100k = "$100000\r\n" <> String.duplicate("x", 100_000) <> "\r\n"

# Decode inputs - aggregates
array_5 = "*5\r\n" <> String.duplicate(":42\r\n", 5)
array_100 = "*100\r\n" <> String.duplicate("$5\r\nhello\r\n", 100)
array_1000 = "*1000\r\n" <> String.duplicate(":1\r\n", 1000)

map_5 = "%5\r\n" <> Enum.map_join(1..5, fn i -> "+key#{i}\r\n:#{i}\r\n" end)
map_50 = "%50\r\n" <> Enum.map_join(1..50, fn i -> "+key#{i}\r\n:#{i}\r\n" end)

# Nested: array of 10 maps with 3 fields each
nested = "*10\r\n" <> String.duplicate(
  "%3\r\n+name\r\n$5\r\nAlice\r\n+age\r\n:30\r\n+city\r\n$3\r\nNYC\r\n",
  10
)

# Mixed types
mixed = "*6\r\n+OK\r\n:42\r\n$5\r\nhello\r\n#t\r\n_\r\n,3.14\r\n"

# -------------------------------------------------------------------
# Encode benchmarks
# -------------------------------------------------------------------

IO.puts("--- Encode ---\n")

Benchee.run(
  %{
    "encode PING" => fn -> RESP3.encode(cmd_tiny) end,
    "encode GET key" => fn -> RESP3.encode(cmd_small) end,
    "encode SET (100B value)" => fn -> RESP3.encode(cmd_medium) end,
    "encode MSET (101 args)" => fn -> RESP3.encode(cmd_large) end,
    "encode pipeline (10 cmds)" => fn -> RESP3.encode_pipeline(pipeline_10) end,
    "encode pipeline (100 cmds)" => fn -> RESP3.encode_pipeline(pipeline_100) end
  },
  time: 3,
  warmup: 1,
  print: [configuration: false]
)

# -------------------------------------------------------------------
# Decode benchmarks - simple types
# -------------------------------------------------------------------

IO.puts("\n--- Decode: Simple Types ---\n")

Benchee.run(
  %{
    "simple string (+OK)" => fn -> RESP3.decode(simple_string) end,
    "simple error (-ERR)" => fn -> RESP3.decode(simple_error) end,
    "integer (:42)" => fn -> RESP3.decode(integer) end,
    "double (,3.14)" => fn -> RESP3.decode(double) end,
    "boolean (#t)" => fn -> RESP3.decode(boolean_true) end,
    "null (_)" => fn -> RESP3.decode(null) end
  },
  time: 3,
  warmup: 1,
  print: [configuration: false]
)

# -------------------------------------------------------------------
# Decode benchmarks - blob strings
# -------------------------------------------------------------------

IO.puts("\n--- Decode: Blob Strings ---\n")

Benchee.run(
  %{
    "blob 10B" => fn -> RESP3.decode(blob_10) end,
    "blob 1KB" => fn -> RESP3.decode(blob_1k) end,
    "blob 100KB" => fn -> RESP3.decode(blob_100k) end
  },
  time: 3,
  warmup: 1,
  print: [configuration: false]
)

# -------------------------------------------------------------------
# Decode benchmarks - aggregates
# -------------------------------------------------------------------

IO.puts("\n--- Decode: Aggregates ---\n")

Benchee.run(
  %{
    "array (5 ints)" => fn -> RESP3.decode(array_5) end,
    "array (100 strings)" => fn -> RESP3.decode(array_100) end,
    "array (1000 ints)" => fn -> RESP3.decode(array_1000) end,
    "map (5 pairs)" => fn -> RESP3.decode(map_5) end,
    "map (50 pairs)" => fn -> RESP3.decode(map_50) end,
    "nested (10 maps x 3 fields)" => fn -> RESP3.decode(nested) end,
    "mixed types (6 elements)" => fn -> RESP3.decode(mixed) end
  },
  time: 3,
  warmup: 1,
  print: [configuration: false]
)

# -------------------------------------------------------------------
# RESP3 vs RESP2 comparison
# -------------------------------------------------------------------

IO.puts("\n--- RESP3 vs RESP2 Decode ---\n")

Benchee.run(
  %{
    "RESP3 simple string" => fn -> RESP3.decode(simple_string) end,
    "RESP2 simple string" => fn -> RESP2.decode(simple_string) end,
    "RESP3 array (100)" => fn -> RESP3.decode(array_100) end,
    "RESP2 array (100)" => fn -> RESP2.decode(array_100) end,
    "RESP3 integer" => fn -> RESP3.decode(integer) end,
    "RESP2 integer" => fn -> RESP2.decode(integer) end
  },
  time: 3,
  warmup: 1,
  print: [configuration: false]
)

# -------------------------------------------------------------------
# Encode + Decode round-trip
# -------------------------------------------------------------------

IO.puts("\n--- Round-trip: Encode + Decode ---\n")

Benchee.run(
  %{
    "GET round-trip" => fn ->
      encoded = RESP3.encode(cmd_small) |> IO.iodata_to_binary()
      RESP3.decode(encoded)
    end,
    "MSET round-trip (101 args)" => fn ->
      encoded = RESP3.encode(cmd_large) |> IO.iodata_to_binary()
      RESP3.decode(encoded)
    end
  },
  time: 3,
  warmup: 1,
  print: [configuration: false]
)

IO.puts("\n=== Benchmark Complete ===\n")

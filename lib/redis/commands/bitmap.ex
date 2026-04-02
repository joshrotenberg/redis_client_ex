defmodule Redis.Commands.Bitmap do
  @moduledoc """
  Command builders for Redis bitmap operations.

  Provides pure functions that build command lists for manipulating individual bits
  within string values. Supports setting and reading bits (SETBIT/GETBIT), counting
  set bits (BITCOUNT), finding bit positions (BITPOS), bitwise operations between
  keys (BITOP), and the compound BITFIELD command for multi-bit integer access.
  Each function returns a plain list of strings suitable for passing to
  `Redis.command/2` or `Redis.pipeline/2`.

  These functions contain no connection or networking logic -- they only construct
  the Redis protocol command as a list.

  ## Examples

  Set and read individual bits (useful for feature flags or presence tracking):

      iex> Redis.Commands.Bitmap.setbit("user:1:features", 7, 1)
      ["SETBIT", "user:1:features", "7", "1"]
      iex> Redis.Commands.Bitmap.getbit("user:1:features", 7)
      ["GETBIT", "user:1:features", "7"]

  Count the number of set bits in a key:

      iex> Redis.Commands.Bitmap.bitcount("user:1:features")
      ["BITCOUNT", "user:1:features"]

  Use BITFIELD for multi-bit integer operations:

      iex> Redis.Commands.Bitmap.bitfield("mykey", ["GET", "u8", "0", "SET", "u8", "0", "100"])
      ["BITFIELD", "mykey", "GET", "u8", "0", "SET", "u8", "0", "100"]
  """

  @spec getbit(String.t(), integer()) :: [String.t()]
  def getbit(key, offset), do: ["GETBIT", key, to_string(offset)]

  @doc """
  Builds a SETBIT command to set or clear the bit at the given offset.

  The value must be 0 or 1. Returns the command list; Redis will respond with the
  original bit value at that offset.

  ## Example

      iex> Redis.Commands.Bitmap.setbit("flags", 7, 1)
      ["SETBIT", "flags", "7", "1"]
  """
  @spec setbit(String.t(), integer(), integer()) :: [String.t()]
  def setbit(key, offset, value), do: ["SETBIT", key, to_string(offset), to_string(value)]

  @doc """
  Builds a BITCOUNT command to count the number of set bits (population count).

  Without options, counts all bits in the value. Use `:start` and `:end` to limit
  the range, and `:byte` or `:bit` to specify whether the range is in bytes or bits.

  ## Examples

      iex> Redis.Commands.Bitmap.bitcount("flags")
      ["BITCOUNT", "flags"]

      iex> Redis.Commands.Bitmap.bitcount("flags", start: 0, end: 10, byte: true)
      ["BITCOUNT", "flags", "0", "10", "BYTE"]
  """
  @spec bitcount(String.t(), keyword()) :: [String.t()]
  def bitcount(key, opts \\ []) do
    cmd = ["BITCOUNT", key]
    cmd = if opts[:start], do: cmd ++ [to_string(opts[:start])], else: cmd
    cmd = if opts[:end], do: cmd ++ [to_string(opts[:end])], else: cmd
    cmd = if opts[:byte], do: cmd ++ ["BYTE"], else: cmd
    cmd = if opts[:bit], do: cmd ++ ["BIT"], else: cmd
    cmd
  end

  @spec bitpos(String.t(), integer(), keyword()) :: [String.t()]
  def bitpos(key, bit, opts \\ []) do
    cmd = ["BITPOS", key, to_string(bit)]
    cmd = if opts[:start], do: cmd ++ [to_string(opts[:start])], else: cmd
    cmd = if opts[:end], do: cmd ++ [to_string(opts[:end])], else: cmd
    cmd = if opts[:byte], do: cmd ++ ["BYTE"], else: cmd
    cmd = if opts[:bit], do: cmd ++ ["BIT"], else: cmd
    cmd
  end

  @spec bitop(String.t(), String.t(), [String.t()]) :: [String.t()]
  def bitop(operation, destkey, keys) when is_list(keys) do
    ["BITOP", String.upcase(operation), destkey | keys]
  end

  @doc """
  Builds a BITFIELD command for multi-bit integer operations on a string key.

  The subcommands list contains the raw BITFIELD subcommand tokens (GET, SET,
  INCRBY, OVERFLOW) as a flat list of strings.

  ## Example

      iex> Redis.Commands.Bitmap.bitfield("counters", ["SET", "u8", "0", "42"])
      ["BITFIELD", "counters", "SET", "u8", "0", "42"]
  """
  @spec bitfield(String.t(), [String.t()]) :: [String.t()]
  def bitfield(key, subcommands) when is_list(subcommands) do
    ["BITFIELD", key | subcommands]
  end

  @spec bitfield_ro(String.t(), [String.t()]) :: [String.t()]
  def bitfield_ro(key, subcommands) when is_list(subcommands) do
    ["BITFIELD_RO", key | subcommands]
  end
end

defmodule Redis.Commands.Bitmap do
  @moduledoc """
  Command builders for Redis bitmap operations.
  """

  @spec getbit(String.t(), integer()) :: [String.t()]
  def getbit(key, offset), do: ["GETBIT", key, to_string(offset)]

  @spec setbit(String.t(), integer(), integer()) :: [String.t()]
  def setbit(key, offset, value), do: ["SETBIT", key, to_string(offset), to_string(value)]

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

  @spec bitfield(String.t(), [String.t()]) :: [String.t()]
  def bitfield(key, subcommands) when is_list(subcommands) do
    ["BITFIELD", key | subcommands]
  end

  @spec bitfield_ro(String.t(), [String.t()]) :: [String.t()]
  def bitfield_ro(key, subcommands) when is_list(subcommands) do
    ["BITFIELD_RO", key | subcommands]
  end
end

defmodule Redis.Commands.Function do
  @moduledoc """
  Command builders for Redis Functions (Redis 7+).

  Redis Functions provide a persistent, named alternative to Lua scripting.
  Libraries are loaded once and survive server restarts, and individual
  functions within a library are invoked by name with `FCALL` / `FCALL_RO`.

  All functions are pure and return a command list for use with
  `Redis.command/2` or `Redis.pipeline/2`.

  ## Examples

      # Load a function library
      Redis.command(conn, Function.load("#!lua name=mylib\\nredis.register_function('myfunc', function(keys, args) return keys[1] end)"))

      # Call a function
      Redis.command(conn, Function.fcall("myfunc", ["key1"], ["arg1"]))

      # List all libraries
      Redis.command(conn, Function.list())
  """

  @doc """
  FCALL -- invoke a Redis Function by name.

  The `keys` list is passed as KEYS and `args` as ARGV inside the function.
  The number of keys is computed automatically.

      Function.fcall("myfunc", ["key1"], ["arg1"])
      #=> ["FCALL", "myfunc", "1", "key1", "arg1"]
  """
  @spec fcall(String.t(), [String.t()], [String.t()]) :: [String.t()]
  def fcall(function, keys \\ [], args \\ []) do
    ["FCALL", function, to_string(length(keys))] ++ keys ++ args
  end

  @doc """
  FCALL_RO -- invoke a read-only Redis Function by name.

  Identical to `fcall/3` but uses the read-only variant, which is safe
  for use on replicas.
  """
  @spec fcall_ro(String.t(), [String.t()], [String.t()]) :: [String.t()]
  def fcall_ro(function, keys \\ [], args \\ []) do
    ["FCALL_RO", function, to_string(length(keys))] ++ keys ++ args
  end

  @doc """
  FUNCTION LOAD -- load a function library into Redis.

  Pass `replace: true` to overwrite an existing library with the same name.

      Function.load("#!lua name=mylib\\nredis.register_function(...)")
      Function.load(code, replace: true)
  """
  @spec load(String.t(), keyword()) :: [String.t()]
  def load(function_code, opts \\ []) do
    cmd = ["FUNCTION", "LOAD"]
    cmd = if opts[:replace], do: cmd ++ ["REPLACE"], else: cmd
    cmd ++ [function_code]
  end

  @doc """
  FUNCTION DELETE -- remove a function library by name.
  """
  @spec delete(String.t()) :: [String.t()]
  def delete(library_name), do: ["FUNCTION", "DELETE", library_name]

  @doc """
  FUNCTION DUMP -- return a serialized payload of all loaded libraries.

  The result can be restored on another server with `restore/2`.
  """
  @spec dump() :: [String.t()]
  def dump, do: ["FUNCTION", "DUMP"]

  @doc """
  FUNCTION RESTORE -- restore libraries from a serialized payload.

  ## Options

    * `:flush` - delete all existing libraries before restoring
    * `:append` - append to existing libraries (error on name conflict)
    * `:replace` - replace existing libraries with same name
  """
  @spec restore(String.t(), keyword()) :: [String.t()]
  def restore(serialized_value, opts \\ []) do
    cmd = ["FUNCTION", "RESTORE", serialized_value]

    cond do
      opts[:flush] -> cmd ++ ["FLUSH"]
      opts[:append] -> cmd ++ ["APPEND"]
      opts[:replace] -> cmd ++ ["REPLACE"]
      true -> cmd
    end
  end

  @doc """
  FUNCTION FLUSH -- delete all function libraries.

  ## Options

    * `:mode` - `:async` or `:sync` (default: server decides)
  """
  @spec flush(keyword()) :: [String.t()]
  def flush(opts \\ []) do
    cmd = ["FUNCTION", "FLUSH"]

    case opts[:mode] do
      :async -> cmd ++ ["ASYNC"]
      :sync -> cmd ++ ["SYNC"]
      nil -> cmd
    end
  end

  @doc """
  FUNCTION LIST -- list loaded function libraries.

  ## Options

    * `:libraryname` - filter by library name pattern
    * `:withcode` - include library source code in the response
  """
  @spec list(keyword()) :: [String.t()]
  def list(opts \\ []) do
    cmd = ["FUNCTION", "LIST"]
    cmd = if opts[:libraryname], do: cmd ++ ["LIBRARYNAME", opts[:libraryname]], else: cmd
    cmd = if opts[:withcode], do: cmd ++ ["WITHCODE"], else: cmd
    cmd
  end

  @doc """
  FUNCTION STATS -- return information about function execution.
  """
  @spec stats() :: [String.t()]
  def stats, do: ["FUNCTION", "STATS"]
end

defmodule Redis.Commands.Script do
  @moduledoc """
  Command builders for Redis Lua scripting and Redis Functions.

  This module covers two related subsystems:

    * **Lua scripting** -- `EVAL`, `EVALSHA`, and `SCRIPT *` commands for
      running ad-hoc Lua scripts on the server.
    * **Redis Functions** (Redis 7+) -- `FCALL`, `FCALL_RO`, and `FUNCTION *`
      commands for managing and invoking persistent, named functions.

  All functions are pure and return a command list for use with
  `Redis.command/2` or `Redis.pipeline/2`.

  ## Examples

      # Evaluate a Lua script that increments a key by a given amount
      Redis.command(conn, Script.eval("return redis.call('INCRBY', KEYS[1], ARGV[1])", ["counter"], ["5"]))

      # Call a previously loaded function
      Redis.command(conn, Script.fcall("myfunc", ["key1"], ["arg1", "arg2"]))

      # Load a function library (Redis 7+)
      Redis.command(conn, Script.function_load("#!lua name=mylib\\nredis.register_function('myfunc', function(keys, args) return keys[1] end)"))
  """

  @doc """
  EVAL -- evaluate a Lua script on the server.

  The `keys` list is passed as KEYS and `args` as ARGV inside the script.
  The number of keys is computed automatically.

      Script.eval("return redis.call('SET', KEYS[1], ARGV[1])", ["mykey"], ["myval"])
      #=> ["EVAL", "return redis.call('SET', KEYS[1], ARGV[1])", "1", "mykey", "myval"]
  """
  @spec eval(String.t(), [String.t()], [String.t()]) :: [String.t()]
  def eval(script, keys \\ [], args \\ []) do
    ["EVAL", script, to_string(length(keys))] ++ keys ++ args
  end

  @doc """
  EVALSHA -- evaluate a cached Lua script by its SHA1 digest.

  Use `script_load/1` first to cache the script and obtain its SHA1.
  """
  @spec evalsha(String.t(), [String.t()], [String.t()]) :: [String.t()]
  def evalsha(sha1, keys \\ [], args \\ []) do
    ["EVALSHA", sha1, to_string(length(keys))] ++ keys ++ args
  end

  @spec eval_ro(String.t(), [String.t()], [String.t()]) :: [String.t()]
  def eval_ro(script, keys \\ [], args \\ []) do
    ["EVAL_RO", script, to_string(length(keys))] ++ keys ++ args
  end

  @spec evalsha_ro(String.t(), [String.t()], [String.t()]) :: [String.t()]
  def evalsha_ro(sha1, keys \\ [], args \\ []) do
    ["EVALSHA_RO", sha1, to_string(length(keys))] ++ keys ++ args
  end

  @spec script_exists([String.t()]) :: [String.t()]
  def script_exists(sha1s) when is_list(sha1s), do: ["SCRIPT", "EXISTS" | sha1s]

  @spec script_flush(keyword()) :: [String.t()]
  def script_flush(opts \\ []) do
    if opts[:async], do: ["SCRIPT", "FLUSH", "ASYNC"], else: ["SCRIPT", "FLUSH"]
  end

  @spec script_kill() :: [String.t()]
  def script_kill, do: ["SCRIPT", "KILL"]

  @spec script_load(String.t()) :: [String.t()]
  def script_load(script), do: ["SCRIPT", "LOAD", script]

  @doc """
  FUNCTION LOAD -- load a function library into Redis (Redis 7+).

  Pass `replace: true` to overwrite an existing library with the same name.

      Script.function_load("#!lua name=mylib\\nredis.register_function('myfunc', function(keys, args) return 'ok' end)")
      Script.function_load(code, replace: true)
  """
  @spec function_load(String.t(), keyword()) :: [String.t()]
  def function_load(function_code, opts \\ []) do
    cmd = ["FUNCTION", "LOAD"]
    cmd = if opts[:replace], do: cmd ++ ["REPLACE"], else: cmd
    cmd ++ [function_code]
  end

  @spec function_delete(String.t()) :: [String.t()]
  def function_delete(library_name), do: ["FUNCTION", "DELETE", library_name]

  @spec function_list(keyword()) :: [String.t()]
  def function_list(opts \\ []) do
    cmd = ["FUNCTION", "LIST"]
    cmd = if opts[:libraryname], do: cmd ++ ["LIBRARYNAME", opts[:libraryname]], else: cmd
    cmd = if opts[:withcode], do: cmd ++ ["WITHCODE"], else: cmd
    cmd
  end

  @spec function_dump() :: [String.t()]
  def function_dump, do: ["FUNCTION", "DUMP"]

  @spec function_restore(String.t(), keyword()) :: [String.t()]
  def function_restore(serialized_value, opts \\ []) do
    cmd = ["FUNCTION", "RESTORE", serialized_value]

    cond do
      opts[:flush] -> cmd ++ ["FLUSH"]
      opts[:append] -> cmd ++ ["APPEND"]
      opts[:replace] -> cmd ++ ["REPLACE"]
      true -> cmd
    end
  end

  @doc """
  FUNCTION FLUSH -- delete all function libraries (Redis 7+).

  Pass `mode: :async` or `mode: :sync` to control flush behaviour.

      Script.function_flush()
      #=> ["FUNCTION", "FLUSH"]

      Script.function_flush(mode: :async)
      #=> ["FUNCTION", "FLUSH", "ASYNC"]
  """
  @spec function_flush(keyword()) :: [String.t()]
  def function_flush(opts \\ []) do
    cmd = ["FUNCTION", "FLUSH"]

    case opts[:mode] do
      :async -> cmd ++ ["ASYNC"]
      :sync -> cmd ++ ["SYNC"]
      nil -> cmd
    end
  end

  @spec function_stats() :: [String.t()]
  def function_stats, do: ["FUNCTION", "STATS"]

  @doc """
  FCALL -- invoke a Redis Function by name (Redis 7+).

  Like `eval/3`, the `keys` and `args` lists map to KEYS and ARGV inside
  the function body.

      Script.fcall("myfunc", ["key1"], ["arg1"])
      #=> ["FCALL", "myfunc", "1", "key1", "arg1"]
  """
  @spec fcall(String.t(), [String.t()], [String.t()]) :: [String.t()]
  def fcall(function, keys \\ [], args \\ []) do
    ["FCALL", function, to_string(length(keys))] ++ keys ++ args
  end

  @spec fcall_ro(String.t(), [String.t()], [String.t()]) :: [String.t()]
  def fcall_ro(function, keys \\ [], args \\ []) do
    ["FCALL_RO", function, to_string(length(keys))] ++ keys ++ args
  end
end

defmodule Redis.Function do
  @moduledoc """
  High-level interface for Redis Functions (Redis 7+).

  Redis Functions are persistent, named server-side routines that replace
  ad-hoc Lua scripting for production workloads. Libraries are loaded once
  and survive server restarts; individual functions within a library are
  invoked by name.

  ## Usage

      # Load a library
      code = \"""
      #!lua name=mylib
      redis.register_function('myfunc', function(keys, args)
        return redis.call('GET', keys[1])
      end)
      \"""
      :ok = Redis.Function.load(conn, code)

      # Call the function
      {:ok, result} = Redis.Function.call(conn, "myfunc", keys: ["mykey"])

      # Read-only variant (safe on replicas)
      {:ok, result} = Redis.Function.call_ro(conn, "myfunc", keys: ["mykey"])

      # List loaded libraries
      {:ok, libs} = Redis.Function.list(conn)

      # Clean up
      :ok = Redis.Function.delete(conn, "mylib")

  ## See also

  `Redis.Script` for ad-hoc Lua scripting with SHA1-based caching.
  """

  alias Redis.Connection

  @doc """
  Loads a function library into Redis.

  The `code` must include a shebang header declaring the engine and library
  name, e.g. `#!lua name=mylib`.

  ## Options

    * `:replace` - overwrite an existing library with the same name (default: false)

  Returns `:ok` on success or `{:error, reason}` on failure.
  """
  @spec load(GenServer.server(), String.t(), keyword()) :: :ok | {:error, term()}
  def load(conn, code, opts \\ []) do
    cmd = ["FUNCTION", "LOAD"]
    cmd = if opts[:replace], do: cmd ++ ["REPLACE"], else: cmd
    cmd = cmd ++ [code]

    case Connection.command(conn, cmd) do
      {:ok, _library_name} -> :ok
      {:error, _} = error -> error
    end
  end

  @doc """
  Deletes a function library by name.

  Returns `:ok` on success or `{:error, reason}` on failure.
  """
  @spec delete(GenServer.server(), String.t()) :: :ok | {:error, term()}
  def delete(conn, library_name) do
    case Connection.command(conn, ["FUNCTION", "DELETE", library_name]) do
      {:ok, "OK"} -> :ok
      {:error, _} = error -> error
    end
  end

  @doc """
  Calls a function by name via FCALL.

  ## Options

    * `:keys` - list of Redis keys (default: [])
    * `:args` - list of additional arguments (default: [])
  """
  @spec call(GenServer.server(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def call(conn, function_name, opts \\ []) do
    keys = Keyword.get(opts, :keys, [])
    args = Keyword.get(opts, :args, [])
    numkeys = length(keys)

    cmd = ["FCALL", function_name, to_string(numkeys)] ++ keys ++ Enum.map(args, &to_string/1)
    Connection.command(conn, cmd)
  end

  @doc """
  Calls a function by name via FCALL_RO (read-only variant).

  Safe for use on replicas. Accepts the same options as `call/3`.
  """
  @spec call_ro(GenServer.server(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def call_ro(conn, function_name, opts \\ []) do
    keys = Keyword.get(opts, :keys, [])
    args = Keyword.get(opts, :args, [])
    numkeys = length(keys)

    cmd = ["FCALL_RO", function_name, to_string(numkeys)] ++ keys ++ Enum.map(args, &to_string/1)
    Connection.command(conn, cmd)
  end

  @doc """
  Lists loaded function libraries.

  ## Options

    * `:libraryname` - filter by library name pattern
    * `:withcode` - include library source code in the response (default: false)
  """
  @spec list(GenServer.server(), keyword()) :: {:ok, term()} | {:error, term()}
  def list(conn, opts \\ []) do
    cmd = ["FUNCTION", "LIST"]
    cmd = if opts[:libraryname], do: cmd ++ ["LIBRARYNAME", opts[:libraryname]], else: cmd
    cmd = if opts[:withcode], do: cmd ++ ["WITHCODE"], else: cmd

    Connection.command(conn, cmd)
  end

  @doc """
  Deletes all function libraries.

  ## Options

    * `:mode` - `:async` or `:sync` (default: server decides)
  """
  @spec flush(GenServer.server(), keyword()) :: :ok | {:error, term()}
  def flush(conn, opts \\ []) do
    cmd = ["FUNCTION", "FLUSH"]

    cmd =
      case opts[:mode] do
        :async -> cmd ++ ["ASYNC"]
        :sync -> cmd ++ ["SYNC"]
        nil -> cmd
      end

    case Connection.command(conn, cmd) do
      {:ok, "OK"} -> :ok
      {:error, _} = error -> error
    end
  end

  @doc """
  Returns a serialized payload of all loaded function libraries.

  The result can be restored on another server with `restore/3`.
  """
  @spec dump(GenServer.server()) :: {:ok, binary()} | {:error, term()}
  def dump(conn) do
    Connection.command(conn, ["FUNCTION", "DUMP"])
  end

  @doc """
  Restores function libraries from a serialized payload produced by `dump/1`.

  ## Options

    * `:flush` - delete all existing libraries before restoring
    * `:append` - append to existing libraries (error on name conflict)
    * `:replace` - replace existing libraries with same name
  """
  @spec restore(GenServer.server(), binary(), keyword()) :: :ok | {:error, term()}
  def restore(conn, data, opts \\ []) do
    cmd = ["FUNCTION", "RESTORE", data]

    cmd =
      cond do
        opts[:flush] -> cmd ++ ["FLUSH"]
        opts[:append] -> cmd ++ ["APPEND"]
        opts[:replace] -> cmd ++ ["REPLACE"]
        true -> cmd
      end

    case Connection.command(conn, cmd) do
      {:ok, "OK"} -> :ok
      {:error, _} = error -> error
    end
  end

  @doc """
  Returns information about function execution statistics.
  """
  @spec stats(GenServer.server()) :: {:ok, term()} | {:error, term()}
  def stats(conn) do
    Connection.command(conn, ["FUNCTION", "STATS"])
  end
end

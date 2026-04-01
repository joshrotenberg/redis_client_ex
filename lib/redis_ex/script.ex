defmodule RedisEx.Script do
  @moduledoc """
  Lua script helper with SHA1 caching.

  Computes the SHA1 at creation time and uses EVALSHA by default,
  automatically falling back to EVAL on NOSCRIPT error.

  ## Usage

      script = RedisEx.Script.new("return redis.call('GET', KEYS[1])")

      {:ok, result} = RedisEx.Script.eval(conn, script, keys: ["mykey"])

      # With arguments
      script = RedisEx.Script.new("return redis.call('SET', KEYS[1], ARGV[1])")
      {:ok, "OK"} = RedisEx.Script.eval(conn, script, keys: ["mykey"], args: ["myval"])

      # Pre-load into Redis script cache
      :ok = RedisEx.Script.load(conn, script)

  The SHA1 is computed once at struct creation. Subsequent `eval` calls
  try EVALSHA first (fast path), falling back to EVAL only on NOSCRIPT.
  """

  alias RedisEx.Connection

  defstruct [:source, :sha]

  @type t :: %__MODULE__{
          source: String.t(),
          sha: String.t()
        }

  @doc """
  Creates a new Script from Lua source code.
  Computes the SHA1 hash immediately.
  """
  @spec new(String.t()) :: t()
  def new(source) when is_binary(source) do
    sha = :crypto.hash(:sha, source) |> Base.encode16(case: :lower)
    %__MODULE__{source: source, sha: sha}
  end

  @doc """
  Evaluates the script against a connection.

  Tries EVALSHA first. On NOSCRIPT error, falls back to EVAL (which also
  loads the script into the server cache for future EVALSHA calls).

  ## Options

    * `:keys` - list of Redis keys (default: [])
    * `:args` - list of additional arguments (default: [])
  """
  @spec eval(GenServer.server(), t(), keyword()) :: {:ok, term()} | {:error, term()}
  def eval(conn, %__MODULE__{} = script, opts \\ []) do
    keys = Keyword.get(opts, :keys, [])
    args = Keyword.get(opts, :args, [])
    numkeys = length(keys)

    evalsha_args = ["EVALSHA", script.sha, to_string(numkeys)] ++ keys ++ Enum.map(args, &to_string/1)

    case Connection.command(conn, evalsha_args) do
      {:error, %RedisEx.Error{message: "NOSCRIPT" <> _}} ->
        # Script not cached on server — fall back to EVAL (which also caches it)
        eval_args = ["EVAL", script.source, to_string(numkeys)] ++ keys ++ Enum.map(args, &to_string/1)
        Connection.command(conn, eval_args)

      result ->
        result
    end
  end

  @doc """
  Evaluates the script, raising on error.
  """
  @spec eval!(GenServer.server(), t(), keyword()) :: term()
  def eval!(conn, script, opts \\ []) do
    case eval(conn, script, opts) do
      {:ok, result} -> result
      {:error, error} -> raise "RedisEx.Script error: #{inspect(error)}"
    end
  end

  @doc """
  Pre-loads the script into the server's script cache via SCRIPT LOAD.
  """
  @spec load(GenServer.server(), t()) :: :ok | {:error, term()}
  def load(conn, %__MODULE__{} = script) do
    case Connection.command(conn, ["SCRIPT", "LOAD", script.source]) do
      {:ok, _sha} -> :ok
      error -> error
    end
  end

  @doc """
  Checks if the script is cached on the server.
  """
  @spec exists?(GenServer.server(), t()) :: boolean()
  def exists?(conn, %__MODULE__{} = script) do
    case Connection.command(conn, ["SCRIPT", "EXISTS", script.sha]) do
      {:ok, [1]} -> true
      {:ok, [0]} -> false
      _ -> false
    end
  end

  @doc """
  Read-only variant of eval (EVALSHA_RO / EVAL_RO).
  Safe for use on replicas.
  """
  @spec eval_ro(GenServer.server(), t(), keyword()) :: {:ok, term()} | {:error, term()}
  def eval_ro(conn, %__MODULE__{} = script, opts \\ []) do
    keys = Keyword.get(opts, :keys, [])
    args = Keyword.get(opts, :args, [])
    numkeys = length(keys)

    evalsha_args = ["EVALSHA_RO", script.sha, to_string(numkeys)] ++ keys ++ Enum.map(args, &to_string/1)

    case Connection.command(conn, evalsha_args) do
      {:error, %RedisEx.Error{message: "NOSCRIPT" <> _}} ->
        eval_args = ["EVAL_RO", script.source, to_string(numkeys)] ++ keys ++ Enum.map(args, &to_string/1)
        Connection.command(conn, eval_args)

      result ->
        result
    end
  end
end

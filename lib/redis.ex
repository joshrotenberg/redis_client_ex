defmodule Redis do
  @moduledoc """
  Modern, full-featured Redis client for Elixir.

  This module provides the top-level API for single-connection usage.
  For other deployment modes and features, see:

    * `Redis.Connection` - single connection with full options
    * `Redis.Connection.Pool` - connection pooling
    * `Redis.Cluster` - cluster-aware client with slot routing
    * `Redis.Sentinel` - sentinel-aware client with failover
    * `Redis.PubSub` - pub/sub subscriptions
    * `Redis.PhoenixPubSub` - Phoenix.PubSub adapter
    * `Redis.Cache` - client-side caching with ETS
    * `Redis.Consumer` - streams consumer group GenServer
    * `Redis.JSON` - high-level JSON document API
    * `Redis.Search` - high-level search API (Meilisearch-inspired)
    * `Redis.PlugSession` - Plug session store
    * `Redis.Resilience` - composed retry, circuit breaker, bulkhead
    * `Redis.Script` - Lua script execution with SHA caching
    * `Redis.Commands` - 21 command builder modules

  ## Quick Start

      {:ok, conn} = Redis.start_link()
      {:ok, "OK"} = Redis.command(conn, ["SET", "key", "value"])
      {:ok, "value"} = Redis.command(conn, ["GET", "key"])

  ## Pipelining

      {:ok, results} = Redis.pipeline(conn, [
        ["SET", "a", "1"],
        ["SET", "b", "2"],
        ["MGET", "a", "b"]
      ])

  ## Transactions

      {:ok, [1, 2, 3]} = Redis.transaction(conn, [
        ["INCR", "counter"],
        ["INCR", "counter"],
        ["INCR", "counter"]
      ])

  ## Optimistic Locking

      Redis.watch_transaction(conn, ["balance"], fn conn ->
        {:ok, bal} = Redis.command(conn, ["GET", "balance"])
        new_bal = String.to_integer(bal) + 100
        [["SET", "balance", to_string(new_bal)]]
      end)
  """

  alias Redis.Connection

  @type conn :: GenServer.server()

  @doc "Returns a child spec for supervision trees."
  defdelegate child_spec(opts), to: Connection

  @doc "Starts a connection. Accepts a keyword list or a Redis URI string."
  @spec start_link(keyword() | String.t()) :: GenServer.on_start()
  defdelegate start_link(opts \\ []), to: Connection

  @doc "Sends a single command."
  @spec command(conn(), [String.t()], keyword()) :: {:ok, term()} | {:error, term()}
  def command(conn, args, opts \\ []), do: Connection.command(conn, args, opts)

  @doc "Sends a single command, raises on error."
  @spec command!(conn(), [String.t()], keyword()) :: term()
  def command!(conn, args, opts \\ []) do
    case command(conn, args, opts) do
      {:ok, result} -> result
      {:error, error} -> raise "Redis error: #{inspect(error)}"
    end
  end

  @doc "Sends multiple commands in a single pipeline."
  @spec pipeline(conn(), [[String.t()]], keyword()) :: {:ok, [term()]} | {:error, term()}
  def pipeline(conn, commands, opts \\ []), do: Connection.pipeline(conn, commands, opts)

  @doc "Executes commands in a MULTI/EXEC transaction."
  @spec transaction(conn(), [[String.t()]], keyword()) :: {:ok, [term()]} | {:error, term()}
  def transaction(conn, commands, opts \\ []), do: Connection.transaction(conn, commands, opts)

  @doc """
  Executes a WATCH-based optimistic locking transaction.

  Watches the given keys, calls `fun` to read values and build commands,
  then executes in MULTI/EXEC. Retries automatically on conflict.

      Redis.watch_transaction(conn, ["balance"], fn conn ->
        {:ok, bal} = Redis.command(conn, ["GET", "balance"])
        new_bal = String.to_integer(bal) + 100
        [["SET", "balance", to_string(new_bal)]]
      end)
  """
  @spec watch_transaction(
          conn(),
          [String.t()],
          (conn() -> [[String.t()]] | {:abort, term()}),
          keyword()
        ) :: {:ok, [term()]} | {:error, term()}
  def watch_transaction(conn, keys, fun, opts \\ []),
    do: Connection.watch_transaction(conn, keys, fun, opts)

  @doc "Sends a command without waiting for a reply (CLIENT REPLY OFF/ON)."
  @spec noreply_command(conn(), [String.t()], keyword()) :: :ok | {:error, term()}
  def noreply_command(conn, args, opts \\ []), do: Connection.noreply_command(conn, args, opts)

  @doc "Sends multiple commands without waiting for replies."
  @spec noreply_pipeline(conn(), [[String.t()]], keyword()) :: :ok | {:error, term()}
  def noreply_pipeline(conn, commands, opts \\ []),
    do: Connection.noreply_pipeline(conn, commands, opts)
end

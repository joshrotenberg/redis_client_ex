defmodule RedisEx do
  @moduledoc """
  Modern, full-featured Redis client for Elixir.

  ## Quick Start

      {:ok, conn} = RedisEx.start_link()
      {:ok, conn} = RedisEx.start_link("redis://:secret@localhost:6380/2")
      {:ok, "OK"} = RedisEx.command(conn, ["SET", "key", "value"])
      {:ok, "value"} = RedisEx.command(conn, ["GET", "key"])

  ## Pipelining

      {:ok, results} = RedisEx.pipeline(conn, [
        ["SET", "a", "1"],
        ["SET", "b", "2"],
        ["MGET", "a", "b"]
      ])

  ## Fire-and-Forget

      :ok = RedisEx.noreply_command(conn, ["INCR", "counter"])
      :ok = RedisEx.noreply_pipeline(conn, [["SET", "a", "1"], ["SET", "b", "2"]])

  ## Cluster

      {:ok, cluster} = RedisEx.Cluster.start_link(nodes: [{"127.0.0.1", 7000}])
      {:ok, "value"} = RedisEx.Cluster.command(cluster, ["GET", "key"])

  ## Sentinel

      {:ok, conn} = RedisEx.Sentinel.start_link(
        sentinels: ["sentinel1:26379"],
        group: "mymaster"
      )
  """

  alias RedisEx.Connection

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
      {:error, error} -> raise "RedisEx error: #{inspect(error)}"
    end
  end

  @doc "Sends multiple commands in a single pipeline."
  @spec pipeline(conn(), [[String.t()]], keyword()) :: {:ok, [term()]} | {:error, term()}
  def pipeline(conn, commands, opts \\ []), do: Connection.pipeline(conn, commands, opts)

  @doc "Executes commands in a MULTI/EXEC transaction."
  @spec transaction(conn(), [[String.t()]], keyword()) :: {:ok, [term()]} | {:error, term()}
  def transaction(conn, commands, opts \\ []), do: Connection.transaction(conn, commands, opts)

  @doc "Sends a command without waiting for a reply (CLIENT REPLY OFF/ON)."
  @spec noreply_command(conn(), [String.t()], keyword()) :: :ok | {:error, term()}
  def noreply_command(conn, args, opts \\ []), do: Connection.noreply_command(conn, args, opts)

  @doc "Sends multiple commands without waiting for replies."
  @spec noreply_pipeline(conn(), [[String.t()]], keyword()) :: :ok | {:error, term()}
  def noreply_pipeline(conn, commands, opts \\ []), do: Connection.noreply_pipeline(conn, commands, opts)
end

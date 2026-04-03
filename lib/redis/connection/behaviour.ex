defmodule Redis.Connection.Behaviour do
  @moduledoc """
  Behaviour defining the Redis connection interface.

  Used by higher-level modules (Search, JSON, Consumer, Resilience, etc.)
  to interact with Redis. Enables testing these modules with Mox without
  a real Redis connection.

  `Redis.Connection` implements this behaviour.
  """

  @type conn :: GenServer.server()
  @type command :: [String.t()]

  @callback command(conn(), command(), keyword()) :: {:ok, term()} | {:error, term()}
  @callback pipeline(conn(), [command()], keyword()) :: {:ok, [term()]} | {:error, term()}
  @callback transaction(conn(), [command()], keyword()) :: {:ok, [term()]} | {:error, term()}
  @callback stop(conn()) :: :ok
end

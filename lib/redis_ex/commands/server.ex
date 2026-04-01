defmodule RedisEx.Commands.Server do
  @moduledoc """
  Command builders for Redis server operations.

  ## TODO (Phase 2)

  CLIENT, CONFIG, DBSIZE, DEBUG, FLUSHALL, FLUSHDB, INFO,
  LASTSAVE, MONITOR, PSYNC, REPLICAOF, SAVE, SHUTDOWN, SLOWLOG,
  TIME, WAIT
  """

  @spec ping(String.t() | nil) :: [String.t()]
  def ping(message \\ nil) do
    if message, do: ["PING", message], else: ["PING"]
  end

  @spec info(String.t() | nil) :: [String.t()]
  def info(section \\ nil) do
    if section, do: ["INFO", section], else: ["INFO"]
  end

  @spec dbsize() :: [String.t()]
  def dbsize, do: ["DBSIZE"]

  @spec flushdb(keyword()) :: [String.t()]
  def flushdb(opts \\ []) do
    if opts[:async], do: ["FLUSHDB", "ASYNC"], else: ["FLUSHDB"]
  end

  @spec client_setname(String.t()) :: [String.t()]
  def client_setname(name), do: ["CLIENT", "SETNAME", name]

  @spec client_getname() :: [String.t()]
  def client_getname, do: ["CLIENT", "GETNAME"]
end

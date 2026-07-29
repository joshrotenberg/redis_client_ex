defmodule RedisConsumerProject do
  @moduledoc false

  @spec command(GenServer.server(), [term()]) :: {:ok, term()} | {:error, term()}
  def command(connection, command) do
    Redis.command(connection, command)
  end
end

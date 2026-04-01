defmodule RedisEx.Error do
  @moduledoc """
  Represents a Redis error response.
  """

  defexception [:message]

  @type t :: %__MODULE__{message: String.t()}
end

defmodule RedisEx.ConnectionError do
  @moduledoc """
  Represents a connection-level error (socket closed, timeout, etc.).
  """

  defexception [:reason]

  @type t :: %__MODULE__{reason: atom() | String.t()}

  @impl true
  def message(%{reason: reason}) when is_atom(reason), do: "connection error: #{reason}"
  def message(%{reason: reason}), do: "connection error: #{inspect(reason)}"
end

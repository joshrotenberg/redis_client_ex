defmodule Redis.Error do
  @moduledoc """
  Represents a Redis error response.
  """

  defexception [:message]

  @type t :: %__MODULE__{message: String.t()}
end

defmodule Redis.ConnectionError do
  @moduledoc """
  Represents a connection-level error (socket closed, timeout, etc.).
  """

  defexception [:reason]

  @type t :: %__MODULE__{reason: atom() | String.t()}

  @impl true
  def message(%{reason: reason}) when is_atom(reason), do: "connection error: #{reason}"
  def message(%{reason: reason}), do: "connection error: #{inspect(reason)}"
end

defmodule Redis.ResponseError do
  @moduledoc """
  Represents a failure while converting a raw Redis reply to a typed response.
  """

  defexception [:command, :reason, :response]

  @type t :: %__MODULE__{
          command: [term()] | nil,
          reason: term(),
          response: term()
        }

  @impl true
  def message(%{command: command, reason: reason}) do
    "could not parse response for #{format_command(command)}: #{format_reason(reason)}"
  end

  defp format_command([command | _]) when is_binary(command), do: String.upcase(command)
  defp format_command(command), do: inspect(command)

  defp format_reason({:invalid_response_mode, mode}),
    do: "invalid response mode #{inspect(mode)} (expected :raw or :typed)"

  defp format_reason(reason), do: inspect(reason)
end

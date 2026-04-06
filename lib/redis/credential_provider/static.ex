defmodule Redis.CredentialProvider.Static do
  @moduledoc """
  A credential provider that returns static credentials.

  Used internally to wrap the legacy `password:` / `username:` options
  so that the connection code has a single credential-fetching path.

  ## Options

    * `:password` - the password string (required)
    * `:username` - the username string (optional, defaults to nil)

  ## Example

      Redis.Connection.start_link(
        port: 6379,
        credential_provider: {Redis.CredentialProvider.Static, password: "secret"}
      )
  """

  @behaviour Redis.CredentialProvider

  @impl true
  def get_credentials(opts) do
    case Keyword.fetch(opts, :password) do
      {:ok, password} ->
        username = Keyword.get(opts, :username)
        {:ok, %{username: username, password: password}}

      :error ->
        {:error, :missing_password}
    end
  end
end

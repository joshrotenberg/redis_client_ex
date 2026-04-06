defmodule Redis.CredentialProvider do
  @moduledoc """
  Behaviour for dynamic credential providers.

  Implement this behaviour to supply credentials that may change over time,
  such as rotating auth tokens for cloud-managed Redis instances (e.g.,
  AWS ElastiCache IAM, Azure Cache for Redis AAD tokens).

  The connection calls `get_credentials/1` on every connect and reconnect,
  passing the provider-specific options from the `{module, opts}` tuple.
  This ensures rotated tokens are picked up automatically.

  ## Example

      defmodule MyCloudProvider do
        @behaviour Redis.CredentialProvider

        @impl true
        def get_credentials(opts) do
          region = Keyword.fetch!(opts, :region)
          token = fetch_token_from_cloud(region)
          {:ok, %{username: "default", password: token}}
        end
      end

  Then pass the provider when starting a connection:

      Redis.Connection.start_link(
        port: 6379,
        credential_provider: {MyCloudProvider, region: "us-east-1"}
      )
  """

  @type credentials :: %{username: String.t() | nil, password: String.t()}

  @doc """
  Returns fresh credentials for authenticating with Redis.

  Receives the options from the `{module, opts}` credential_provider tuple.
  Called on every connection and reconnection attempt.
  """
  @callback get_credentials(opts :: keyword()) :: {:ok, credentials()} | {:error, term()}
end

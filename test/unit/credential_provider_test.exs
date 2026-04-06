defmodule Redis.CredentialProviderTest do
  use ExUnit.Case, async: true

  alias Redis.CredentialProvider.Static

  describe "Static.get_credentials/1" do
    test "returns credentials with password and username" do
      opts = [password: "secret", username: "admin"]
      assert {:ok, %{username: "admin", password: "secret"}} = Static.get_credentials(opts)
    end

    test "returns credentials with password only" do
      opts = [password: "secret"]
      assert {:ok, %{username: nil, password: "secret"}} = Static.get_credentials(opts)
    end

    test "returns error when password is missing" do
      assert {:error, :missing_password} = Static.get_credentials([])
    end
  end

  describe "custom provider" do
    defmodule CountingProvider do
      @behaviour Redis.CredentialProvider

      @impl true
      def get_credentials(opts) do
        agent = Keyword.fetch!(opts, :agent)
        count = Agent.get_and_update(agent, fn n -> {n + 1, n + 1} end)
        {:ok, %{username: nil, password: "token-#{count}"}}
      end
    end

    test "provider is called and returns fresh credentials each time" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)
      opts = [agent: agent]

      assert {:ok, %{password: "token-1"}} = CountingProvider.get_credentials(opts)
      assert {:ok, %{password: "token-2"}} = CountingProvider.get_credentials(opts)
      assert {:ok, %{password: "token-3"}} = CountingProvider.get_credentials(opts)
    end

    defmodule FailingProvider do
      @behaviour Redis.CredentialProvider

      @impl true
      def get_credentials(_opts) do
        {:error, :token_expired}
      end
    end

    test "provider can return an error" do
      assert {:error, :token_expired} = FailingProvider.get_credentials([])
    end
  end
end

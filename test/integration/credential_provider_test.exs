defmodule Redis.Integration.CredentialProviderTest do
  use ExUnit.Case, async: false

  defmodule TrackingProvider do
    @behaviour Redis.CredentialProvider

    @impl true
    def get_credentials(opts) do
      agent = Keyword.fetch!(opts, :agent)
      Agent.update(agent, fn calls -> calls + 1 end)
      password = Keyword.get(opts, :password, "testpass")
      {:ok, %{username: nil, password: password}}
    end
  end

  describe "credential_provider option" do
    test "provider is called on initial connection" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      {:ok, conn} =
        Redis.Connection.start_link(
          port: 6399,
          credential_provider: {TrackingProvider, agent: agent, password: "testpass"}
        )

      # Provider should have been called at least once during connect
      call_count = Agent.get(agent, & &1)
      assert call_count >= 1

      # Connection should be functional
      assert {:ok, "PONG"} = Redis.Connection.command(conn, ["PING"])

      Redis.Connection.stop(conn)
    end

    test "backward compat: static password option still works" do
      {:ok, conn} =
        Redis.Connection.start_link(
          port: 6399,
          password: "testpass"
        )

      assert {:ok, "PONG"} = Redis.Connection.command(conn, ["PING"])

      Redis.Connection.stop(conn)
    end

    test "provider is called again on reconnection" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      {:ok, conn} =
        Redis.Connection.start_link(
          port: 6399,
          credential_provider: {TrackingProvider, agent: agent, password: "testpass"},
          backoff_initial: 100,
          backoff_max: 200
        )

      initial_calls = Agent.get(agent, & &1)
      assert initial_calls >= 1

      # Verify connection works
      assert {:ok, "PONG"} = Redis.Connection.command(conn, ["PING"])

      # Force a disconnect by killing the TCP connection via CLIENT KILL
      {:ok, admin} = Redis.Connection.start_link(port: 6399, password: "testpass")
      admin_id = get_client_id(admin)

      {:ok, clients} = Redis.Connection.command(admin, ["CLIENT", "LIST"])

      client_ids =
        clients
        |> String.split("\n", trim: true)
        |> Enum.map(&extract_client_id/1)
        |> Enum.reject(&(is_nil(&1) or &1 == admin_id))

      # Kill all non-admin connections to force reconnect
      for id <- client_ids do
        Redis.Connection.command(admin, ["CLIENT", "KILL", "ID", to_string(id)])
      end

      # Wait for reconnection
      Process.sleep(500)

      # The provider should have been called again during reconnection
      reconnect_calls = Agent.get(agent, & &1)
      assert reconnect_calls > initial_calls

      # Connection should be functional again
      assert {:ok, "PONG"} = Redis.Connection.command(conn, ["PING"])

      Redis.Connection.stop(conn)
      Redis.Connection.stop(admin)
    end

    test "connection fails when provider returns error" do
      defmodule ErrorProvider do
        @behaviour Redis.CredentialProvider

        @impl true
        def get_credentials(_opts), do: {:error, :cannot_fetch_token}
      end

      Process.flag(:trap_exit, true)

      result =
        Redis.Connection.start_link(
          port: 6399,
          credential_provider: {ErrorProvider, []}
        )

      assert {:error, {:credential_provider_failed, :cannot_fetch_token}} = result
    end
  end

  defp get_client_id(conn) do
    {:ok, id} = Redis.Connection.command(conn, ["CLIENT", "ID"])
    id
  end

  defp extract_client_id(client_line) do
    case Regex.run(~r/id=(\d+)/, client_line) do
      [_, id] -> String.to_integer(id)
      _ -> nil
    end
  end
end

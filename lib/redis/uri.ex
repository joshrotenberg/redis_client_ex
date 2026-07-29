defmodule Redis.URI do
  @moduledoc """
  Parses Redis URIs into connection options.

  Supports `redis://`, `rediss://` (TLS), and `valkey://` schemes.

  ## Format

      redis://[username:password@]host[:port][/database]
      rediss://[username:password@]host[:port][/database]

  ## Examples

      Redis.URI.parse("redis://localhost:6379")
      #=> [host: "localhost", port: 6379]

      Redis.URI.parse("redis://:secret@myhost:6380/2")
      #=> [host: "myhost", port: 6380, password: "secret", database: 2]

      Redis.URI.parse("rediss://user:pass@host:6379")
      #=> [host: "host", port: 6379, username: "user", password: "pass", ssl: true]
  """

  @default_port 6379
  @supported_schemes ~w(redis rediss valkey)

  @doc """
  Parses a Redis URI string into a keyword list of connection options.
  """
  @spec parse(String.t()) :: keyword()
  def parse(uri_string) when is_binary(uri_string) do
    uri = URI.parse(uri_string)
    validate_uri!(uri, uri_string)
    ssl = uri.scheme == "rediss"

    []
    |> prepend_host(uri)
    |> prepend_port(uri)
    |> prepend_userinfo(uri)
    |> prepend_database(uri)
    |> prepend_ssl(ssl)
    |> Enum.reverse()
  end

  defp validate_uri!(%{scheme: scheme, host: host}, _uri_string)
       when scheme in @supported_schemes and is_binary(host) and host != "",
       do: :ok

  defp validate_uri!(_uri, uri_string) do
    raise ArgumentError,
          "invalid Redis URI #{inspect(uri_string)}; expected redis://, rediss://, or valkey:// with a host"
  end

  defp prepend_host(opts, uri), do: [{:host, uri.host} | opts]

  defp prepend_port(opts, uri), do: [{:port, uri.port || @default_port} | opts]

  defp prepend_userinfo(opts, %{userinfo: nil}), do: opts

  defp prepend_userinfo(opts, %{userinfo: info}) do
    case String.split(info, ":", parts: 2) do
      ["", password] ->
        [{:password, URI.decode(password)} | opts]

      [username, password] ->
        [{:username, URI.decode(username)}, {:password, URI.decode(password)} | opts]

      [password] ->
        [{:password, URI.decode(password)} | opts]
    end
  end

  defp prepend_database(opts, %{path: path}) when path in [nil, "", "/"], do: opts

  defp prepend_database(opts, %{path: "/" <> db_str}) do
    case Integer.parse(db_str) do
      {db, ""} when db > 0 -> [{:database, db} | opts]
      _ -> opts
    end
  end

  defp prepend_database(opts, _uri), do: opts

  defp prepend_ssl(opts, true), do: [{:ssl, true} | opts]
  defp prepend_ssl(opts, false), do: opts

  @doc """
  Converts connection options back to a Redis URI string.
  """
  @spec to_string(keyword()) :: String.t()
  def to_string(opts) do
    scheme = if Keyword.get(opts, :ssl, false), do: "rediss", else: "redis"
    host = opts |> Keyword.get(:host, "127.0.0.1") |> format_host()
    port = Keyword.get(opts, :port, @default_port)
    password = Keyword.get(opts, :password)
    username = Keyword.get(opts, :username)
    database = Keyword.get(opts, :database)

    userinfo =
      case {username, password} do
        {nil, nil} -> ""
        {nil, pw} -> ":#{URI.encode(pw)}@"
        {user, nil} -> "#{URI.encode(user)}:@"
        {user, pw} -> "#{URI.encode(user)}:#{URI.encode(pw)}@"
      end

    db_path =
      case database do
        nil -> ""
        0 -> ""
        db -> "/#{db}"
      end

    "#{scheme}://#{userinfo}#{host}:#{port}#{db_path}"
  end

  defp format_host(host) do
    if String.contains?(host, ":") and not String.starts_with?(host, "[") do
      "[#{host}]"
    else
      host
    end
  end
end

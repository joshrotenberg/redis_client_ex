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

  @doc """
  Parses a Redis URI string into a keyword list of connection options.
  """
  @spec parse(String.t()) :: keyword()
  def parse(uri_string) when is_binary(uri_string) do
    normalized = normalize_scheme(uri_string)
    ssl = String.starts_with?(uri_string, "rediss://")
    uri = URI.parse(normalized)

    []
    |> prepend_host(uri)
    |> prepend_port(uri_string)
    |> prepend_userinfo(uri)
    |> prepend_database(uri)
    |> prepend_ssl(ssl)
    |> Enum.reverse()
  end

  defp normalize_scheme(uri_string) do
    uri_string
    |> String.replace(~r/^rediss:\/\//, "https://")
    |> String.replace(~r/^redis:\/\//, "http://")
    |> String.replace(~r/^valkey:\/\//, "http://")
  end

  defp prepend_host(opts, uri) do
    if uri.host && uri.host != "", do: [{:host, uri.host} | opts], else: opts
  end

  defp prepend_port(opts, uri_string) do
    actual_port =
      case Regex.run(~r/:(\d+)(?:\/|$)/, uri_string) do
        [_, port_str] -> String.to_integer(port_str)
        _ -> @default_port
      end

    [{:port, actual_port} | opts]
  end

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
    host = Keyword.get(opts, :host, "127.0.0.1")
    port = Keyword.get(opts, :port, @default_port)
    password = Keyword.get(opts, :password)
    username = Keyword.get(opts, :username)
    database = Keyword.get(opts, :database)

    userinfo =
      case {username, password} do
        {nil, nil} -> ""
        {nil, pw} -> ":#{URI.encode(pw)}@"
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
end

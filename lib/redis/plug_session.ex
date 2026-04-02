defmodule Redis.PlugSession do
  @moduledoc """
  A Plug.Session.Store backed by Redis.

  Stores session data as serialized terms in Redis with configurable TTL.
  Each session gets a unique key prefixed with a configurable namespace.

  ## Usage

  In your Phoenix endpoint or Plug pipeline:

      plug Plug.Session,
        store: Redis.PlugSession,
        key: "_my_app_session",
        table: :redis,
        signing_salt: "your_salt",
        ttl: 86_400

  ## Options

    * `:table` (required) - Redis connection name or pid
    * `:prefix` - key prefix (default: `"plug:session:"`)
    * `:ttl` - session TTL in seconds (default: 86400 / 24 hours)

  The `:table` option is named for compatibility with `Plug.Session`'s
  option naming convention. It should be a `Redis.Connection` pid or
  registered name.
  """

  @behaviour Plug.Session.Store

  @default_prefix "plug:session:"
  @default_ttl 86_400

  @impl true
  def init(opts) do
    %{
      conn: Keyword.fetch!(opts, :table),
      prefix: Keyword.get(opts, :prefix, @default_prefix),
      ttl: Keyword.get(opts, :ttl, @default_ttl)
    }
  end

  @impl true
  def get(_plug_conn, cookie, opts) when is_binary(cookie) and byte_size(cookie) > 0 do
    key = session_key(opts.prefix, cookie)

    case Redis.Connection.command(opts.conn, ["GET", key]) do
      {:ok, nil} ->
        {nil, %{}}

      {:ok, data} when is_binary(data) ->
        {cookie, safe_deserialize(data)}

      _ ->
        {nil, %{}}
    end
  end

  def get(_plug_conn, _cookie, _opts) do
    {nil, %{}}
  end

  @impl true
  def put(_plug_conn, nil, data, opts) do
    sid = generate_sid()
    store_session(sid, data, opts)
    sid
  end

  def put(_plug_conn, sid, data, opts) do
    store_session(sid, data, opts)
    sid
  end

  @impl true
  def delete(_plug_conn, nil, _opts), do: :ok

  def delete(_plug_conn, sid, opts) do
    key = session_key(opts.prefix, sid)
    Redis.Connection.command(opts.conn, ["DEL", key])
    :ok
  end

  # -------------------------------------------------------------------
  # Private
  # -------------------------------------------------------------------

  defp store_session(sid, data, opts) do
    key = session_key(opts.prefix, sid)
    value = :erlang.term_to_binary(data)

    Redis.Connection.command(opts.conn, [
      "SET",
      key,
      value,
      "EX",
      Integer.to_string(opts.ttl)
    ])
  end

  defp session_key(prefix, sid), do: prefix <> sid

  defp generate_sid do
    :crypto.strong_rand_bytes(96) |> Base.encode64()
  end

  defp safe_deserialize(data) do
    :erlang.binary_to_term(data)
  rescue
    ArgumentError -> %{}
  end
end

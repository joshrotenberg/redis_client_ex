defmodule Redis.Cluster.Scan do
  @moduledoc """
  Cluster-wide SCAN — iterates keys across all master nodes transparently.

  ## Usage

      {:ok, cluster} = Redis.Cluster.start_link(nodes: [{"127.0.0.1", 7000}])

      # Scan all keys matching a pattern
      {:ok, keys} = Redis.Cluster.Scan.scan(cluster, match: "user:*")

      # Stream-based (lazy) scanning
      Redis.Cluster.Scan.stream(cluster, match: "user:*", count: 100)
      |> Enum.take(50)

  ## Options

    * `:match` - glob pattern (default: "*")
    * `:count` - hint for number of keys per SCAN call (default: 100)
    * `:type` - filter by key type ("string", "list", "set", etc.)
  """

  alias Redis.Connection

  @doc """
  Scans all keys across the cluster, returning the full list.
  Use `stream/2` for large keyspaces.
  """
  @spec scan(GenServer.server(), keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def scan(cluster, opts \\ []) do
    keys =
      stream(cluster, opts)
      |> Enum.to_list()

    {:ok, keys}
  end

  @doc """
  Returns a Stream that lazily scans all cluster nodes.
  Each element is a key string.
  """
  @spec stream(GenServer.server(), keyword()) :: Enumerable.t()
  def stream(cluster, opts \\ []) do
    # Get all node connections from the cluster
    info = GenServer.call(cluster, :get_connections)

    # Get unique master connections
    connections = Map.values(info) |> Enum.uniq()

    # Stream across all nodes
    connections
    |> Stream.flat_map(fn conn ->
      scan_node_stream(conn, opts)
    end)
  end

  # Stream that lazily SCANs a single node
  defp scan_node_stream(conn, opts) do
    match = Keyword.get(opts, :match, "*")
    count = Keyword.get(opts, :count, 100)
    type = Keyword.get(opts, :type)

    Stream.resource(
      fn -> "0" end,
      fn
        :done -> {:halt, :done}
        cursor -> scan_next(conn, cursor, match, count, type)
      end,
      fn _ -> :ok end
    )
  end

  defp scan_next(conn, cursor, match, count, type) do
    cmd = build_scan_cmd(cursor, match, count, type)

    case Connection.command(conn, cmd) do
      {:ok, [next_cursor, keys]} ->
        next = if next_cursor == "0", do: :done, else: next_cursor
        {keys, next}

      _ ->
        {[], :done}
    end
  end

  defp build_scan_cmd(cursor, match, count, type) do
    cmd = ["SCAN", cursor, "MATCH", match, "COUNT", to_string(count)]
    if type, do: cmd ++ ["TYPE", type], else: cmd
  end
end

defmodule Redis.PhoenixPubSub do
  @moduledoc """
  A Phoenix.PubSub adapter backed by Redis.

  Uses Redis Pub/Sub for cross-node message broadcasting, allowing
  multiple Elixir nodes to share a Phoenix.PubSub namespace.

  ## Usage

  Add to your supervision tree:

      children = [
        {Phoenix.PubSub,
         name: MyApp.PubSub,
         adapter: Redis.PhoenixPubSub,
         redis_opts: [host: "localhost", port: 6379]}
      ]

  Then use `Phoenix.PubSub` as normal:

      Phoenix.PubSub.subscribe(MyApp.PubSub, "user:123")
      Phoenix.PubSub.broadcast(MyApp.PubSub, "user:123", {:updated, %{name: "Alice"}})

  ## Options

    * `:redis_opts` - keyword list passed to `Redis.Connection.start_link/1`
      and `Redis.PubSub.start_link/1` (host, port, password, etc.)
    * `:node_name` - node identifier (default: `node()`)
    * `:compression` - compression level for `:erlang.term_to_binary/2`
      (0 = none, 1-9 = zlib levels, default: 0)
  """

  @behaviour Phoenix.PubSub.Adapter

  use Supervisor

  alias Redis.PhoenixPubSub.Listener

  @impl true
  def node_name(adapter_name) do
    :ets.lookup_element(adapter_name, :node_name, 2)
  end

  @impl true
  def broadcast(adapter_name, topic, message, dispatcher) do
    publish(adapter_name, {:except, node_name(adapter_name), topic, message, dispatcher})
  end

  @impl true
  def direct_broadcast(adapter_name, target_node, topic, message, dispatcher) do
    publish(adapter_name, {:only, target_node, topic, message, dispatcher})
  end

  defp publish(adapter_name, payload) do
    compression = :ets.lookup_element(adapter_name, :compression, 2)
    bin = :erlang.term_to_binary(payload, compressed: compression)
    conn = :ets.lookup_element(adapter_name, :pub_conn, 2)

    case Redis.Connection.command(conn, ["PUBLISH", channel(adapter_name), bin]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp channel(adapter_name), do: "phx:#{adapter_name}"

  # -------------------------------------------------------------------
  # Supervisor
  # -------------------------------------------------------------------

  def start_link(opts) do
    adapter_name = Keyword.fetch!(opts, :adapter_name)
    Supervisor.start_link(__MODULE__, opts, name: :"#{adapter_name}.Supervisor")
  end

  @impl Supervisor
  def init(opts) do
    adapter_name = Keyword.fetch!(opts, :adapter_name)
    pubsub_name = Keyword.fetch!(opts, :name)
    node_name = Keyword.get(opts, :node_name, node())
    compression = Keyword.get(opts, :compression, 0)
    redis_opts = Keyword.get(opts, :redis_opts, [])

    # ETS table for fast concurrent reads from publisher path
    :ets.new(adapter_name, [:public, :named_table, read_concurrency: true])
    :ets.insert(adapter_name, {:node_name, node_name})
    :ets.insert(adapter_name, {:compression, compression})

    pub_conn_name = :"#{adapter_name}.Publisher"

    children = [
      # Publisher connection for PUBLISH commands
      {Redis.Connection, Keyword.merge(redis_opts, name: pub_conn_name)},
      # Subscriber listener (dedicated PubSub connection)
      {Listener, {adapter_name, pubsub_name, node_name, channel(adapter_name), redis_opts}}
    ]

    # Store pub_conn after init so broadcast can find it
    :ets.insert(adapter_name, {:pub_conn, pub_conn_name})

    Supervisor.init(children, strategy: :rest_for_one)
  end
end

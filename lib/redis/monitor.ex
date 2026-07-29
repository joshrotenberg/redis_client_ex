defmodule Redis.Monitor do
  @moduledoc """
  Streams commands observed by Redis' `MONITOR` command.

  `Redis.Monitor` owns a dedicated connection because a connection in monitor
  mode cannot be used for ordinary commands. Each record is parsed into a
  `Redis.Monitor.Entry` and sent to subscribers:

      {:ok, monitor} = Redis.Monitor.start_link(port: 6379)
      :ok = Redis.Monitor.subscribe(monitor)

      receive do
        {:redis_monitor, %Redis.Monitor.Entry{} = entry} ->
          IO.inspect(entry)
      end

  A Redis URI can be passed instead of connection options:

      Redis.Monitor.start_link("redis://:secret@localhost:6379/2")

  ## Subscriber filters

  Filters are applied independently for each subscriber:

      Redis.Monitor.subscribe(monitor,
        commands: ["SET", "DEL"],
        database: 0,
        client: ~r/^127\.0\.0\.1:/
      )

  Supported filters are:

    * `:commands` - a command or list of commands, matched case-insensitively
    * `:database` - a database number or list of database numbers
    * `:client` - an exact client identifier or a regular expression

  ## Connection options

  The connection options mirror `Redis.Connection` where they apply:
  `:host`, `:port`, `:password`, `:username`, `:database`, `:ssl`,
  `:ssl_opts`, `:socket`, `:client_name`, `:credential_provider`, `:timeout`,
  `:sync_connect`, `:backoff_initial`, and `:backoff_max`.

  `MONITOR` exposes live application traffic and has a measurable performance
  cost. It should be protected and used deliberately in production.
  """

  use GenServer

  alias Redis.Monitor.Entry
  alias Redis.Protocol.RESP2

  require Logger

  defstruct [
    :host,
    :port,
    :password,
    :username,
    :database,
    :socket,
    :unix_socket,
    :ssl,
    :ssl_opts,
    :client_name,
    :timeout,
    :credential_provider,
    state: :disconnected,
    buffer: <<>>,
    subscribers: %{},
    backoff_initial: 500,
    backoff_max: 30_000,
    backoff_current: 500
  ]

  @type filter ::
          {:commands, String.t() | [String.t()]}
          | {:database, non_neg_integer() | [non_neg_integer()]}
          | {:client, String.t() | Regex.t()}

  # -------------------------------------------------------------------
  # Public API
  # -------------------------------------------------------------------

  @doc "Returns a child specification for a monitor process."
  @spec child_spec(keyword() | String.t()) :: Supervisor.child_spec()
  def child_spec(opts) do
    id = if is_list(opts), do: Keyword.get(opts, :name, __MODULE__), else: __MODULE__

    %{
      id: id,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  @doc "Starts a dedicated Redis `MONITOR` connection."
  @spec start_link(keyword() | String.t()) :: GenServer.on_start()
  def start_link(uri) when is_binary(uri), do: start_link(Redis.URI.parse(uri))

  def start_link(opts) when is_list(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  def start_link, do: start_link([])

  @doc """
  Subscribes a process to parsed monitor entries.

  The second argument may be a subscriber pid or a filter keyword list.
  """
  @spec subscribe(GenServer.server(), pid() | [filter()]) :: :ok | {:error, term()}
  def subscribe(monitor, subscriber_or_filters \\ self())

  def subscribe(monitor, subscriber) when is_pid(subscriber),
    do: subscribe(monitor, subscriber, [])

  def subscribe(monitor, filters) when is_list(filters),
    do: subscribe(monitor, self(), filters)

  @doc "Subscribes `subscriber` with optional per-subscriber filters."
  @spec subscribe(GenServer.server(), pid(), [filter()]) :: :ok | {:error, term()}
  def subscribe(monitor, subscriber, filters) when is_pid(subscriber) and is_list(filters) do
    GenServer.call(monitor, {:subscribe, subscriber, filters})
  end

  @doc "Unsubscribes a process from monitor entries."
  @spec unsubscribe(GenServer.server(), pid()) :: :ok
  def unsubscribe(monitor, subscriber \\ self()) do
    GenServer.call(monitor, {:unsubscribe, subscriber})
  end

  @doc "Returns the currently subscribed process identifiers."
  @spec subscribers(GenServer.server()) :: [pid()]
  def subscribers(monitor), do: GenServer.call(monitor, :subscribers)

  @doc "Stops the monitor connection."
  @spec stop(GenServer.server()) :: :ok
  def stop(monitor), do: GenServer.stop(monitor, :normal)

  # -------------------------------------------------------------------
  # GenServer callbacks
  # -------------------------------------------------------------------

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    password = resolve_password(Keyword.get(opts, :password))
    initial_backoff = Keyword.get(opts, :backoff_initial, 500)

    state = %__MODULE__{
      host: Keyword.get(opts, :host, "127.0.0.1"),
      port: Keyword.get(opts, :port, 6379),
      password: password,
      username: Keyword.get(opts, :username),
      database: Keyword.get(opts, :database),
      ssl: Keyword.get(opts, :ssl, false),
      ssl_opts: Keyword.get(opts, :ssl_opts, []),
      unix_socket: Keyword.get(opts, :socket),
      client_name: Keyword.get(opts, :client_name),
      timeout: Keyword.get(opts, :timeout, 5_000),
      credential_provider: build_credential_provider(opts, password),
      backoff_initial: initial_backoff,
      backoff_max: Keyword.get(opts, :backoff_max, 30_000),
      backoff_current: initial_backoff
    }

    if Keyword.get(opts, :sync_connect, true) do
      case connect(state) do
        {:ok, state} -> {:ok, state}
        {:error, reason} -> {:stop, reason}
      end
    else
      send(self(), :connect)
      {:ok, state}
    end
  end

  @impl true
  def handle_call({:subscribe, subscriber, filters}, _from, state) do
    case normalize_filters(filters) do
      {:ok, filters} ->
        state = put_subscriber(state, subscriber, filters)
        {:reply, :ok, state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:unsubscribe, subscriber}, _from, state) do
    {:reply, :ok, delete_subscriber(state, subscriber)}
  end

  def handle_call(:subscribers, _from, state) do
    {:reply, Map.keys(state.subscribers), state}
  end

  @impl true
  def handle_info({kind, socket, data}, %{socket: socket} = state) when kind in [:tcp, :ssl] do
    {:noreply, process_buffer(%{state | buffer: state.buffer <> data})}
  end

  def handle_info({closed, socket}, %{socket: socket} = state)
      when closed in [:tcp_closed, :ssl_closed] do
    Logger.warning("Redis.Monitor: connection closed")
    {:noreply, state |> disconnect() |> schedule_reconnect()}
  end

  def handle_info({error, socket, reason}, %{socket: socket} = state)
      when error in [:tcp_error, :ssl_error] do
    Logger.warning("Redis.Monitor: connection error: #{inspect(reason)}")
    {:noreply, state |> disconnect() |> schedule_reconnect()}
  end

  def handle_info(:connect, %{state: :ready} = state), do: {:noreply, state}

  def handle_info(:connect, state) do
    case connect(state) do
      {:ok, state} ->
        {:noreply, state}

      {:error, reason} ->
        Logger.warning("Redis.Monitor: reconnect failed: #{inspect(reason)}")
        {:noreply, schedule_reconnect(state)}
    end
  end

  def handle_info(:process_buffer, state), do: {:noreply, process_buffer(state)}

  def handle_info({:DOWN, ref, :process, subscriber, _reason}, state) do
    case Map.get(state.subscribers, subscriber) do
      %{ref: ^ref} ->
        {:noreply, %{state | subscribers: Map.delete(state.subscribers, subscriber)}}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({kind, _stale_socket, _data}, state)
      when kind in [:tcp, :ssl, :tcp_error, :ssl_error],
      do: {:noreply, state}

  def handle_info({kind, _stale_socket}, state) when kind in [:tcp_closed, :ssl_closed],
    do: {:noreply, state}

  def handle_info({:EXIT, _port, _reason}, state), do: {:noreply, state}
  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    if state.socket, do: close_socket(state)
    :ok
  end

  # -------------------------------------------------------------------
  # Connection
  # -------------------------------------------------------------------

  defp connect(%{unix_socket: path} = state) when is_binary(path) do
    tcp_opts = [:binary, active: false, packet: :raw]

    case :gen_tcp.connect({:local, String.to_charlist(path)}, 0, tcp_opts, state.timeout) do
      {:ok, socket} -> finish_connect(%{state | socket: socket, ssl: false})
      {:error, reason} -> {:error, reason}
    end
  end

  defp connect(state) do
    host = String.to_charlist(state.host)
    tcp_opts = [:binary, active: false, packet: :raw, nodelay: true]

    case :gen_tcp.connect(host, state.port, tcp_opts, state.timeout) do
      {:ok, tcp_socket} ->
        case maybe_upgrade_ssl(tcp_socket, state) do
          {:ok, socket} ->
            finish_connect(%{state | socket: socket})

          {:error, reason} ->
            :gen_tcp.close(tcp_socket)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_upgrade_ssl(socket, %{ssl: false}), do: {:ok, socket}

  defp maybe_upgrade_ssl(socket, %{ssl: true} = state) do
    ssl_opts = Keyword.put_new(state.ssl_opts, :verify, :verify_none)

    case :ssl.connect(socket, ssl_opts, state.timeout) do
      {:ok, socket} -> {:ok, socket}
      {:error, reason} -> {:error, {:ssl_error, reason}}
    end
  end

  defp finish_connect(state) do
    state = %{state | state: :ready, buffer: <<>>}

    with {:ok, state} <- fetch_credentials(state),
         {:ok, state} <- maybe_auth(state),
         {:ok, state} <- maybe_select(state),
         {:ok, state} <- maybe_set_client_name(state),
         {:ok, state} <- start_monitoring(state),
         :ok <- set_active(state, true) do
      if state.buffer != <<>>, do: send(self(), :process_buffer)

      Logger.debug("Redis.Monitor: connected to #{connection_label(state)}")
      {:ok, %{state | backoff_current: state.backoff_initial}}
    else
      {:error, reason} ->
        close_socket(state)
        {:error, reason}
    end
  end

  defp maybe_auth(%{password: nil} = state), do: {:ok, state}

  defp maybe_auth(state) do
    args =
      case state.username do
        nil -> ["AUTH", state.password]
        username -> ["AUTH", username, state.password]
      end

    case sync_command(state, args) do
      {:ok, "OK", state} -> {:ok, state}
      {:ok, %Redis.Error{message: message}, _state} -> {:error, {:auth_failed, message}}
      {:error, reason} -> {:error, {:auth_failed, reason}}
    end
  end

  defp maybe_select(%{database: database} = state) when database in [nil, 0],
    do: {:ok, state}

  defp maybe_select(state) do
    case sync_command(state, ["SELECT", to_string(state.database)]) do
      {:ok, "OK", state} -> {:ok, state}
      {:ok, %Redis.Error{message: message}, _state} -> {:error, {:select_failed, message}}
      {:error, reason} -> {:error, {:select_failed, reason}}
    end
  end

  defp maybe_set_client_name(%{client_name: nil} = state), do: {:ok, state}

  defp maybe_set_client_name(state) do
    case sync_command(state, ["CLIENT", "SETNAME", state.client_name]) do
      {:ok, "OK", state} -> {:ok, state}
      {:ok, %Redis.Error{message: message}, _state} -> {:error, {:client_name_failed, message}}
      {:error, reason} -> {:error, {:client_name_failed, reason}}
    end
  end

  defp start_monitoring(state) do
    case sync_command(state, ["MONITOR"]) do
      {:ok, "OK", state} -> {:ok, state}
      {:ok, %Redis.Error{message: message}, _state} -> {:error, {:monitor_failed, message}}
      {:error, reason} -> {:error, {:monitor_failed, reason}}
    end
  end

  defp sync_command(state, args) do
    with :ok <- send_data(state, RESP2.encode(args)),
         {:ok, response, rest} <- recv_response(state, state.buffer) do
      {:ok, response, %{state | buffer: rest}}
    end
  end

  defp recv_response(state, buffer) do
    case RESP2.decode(buffer) do
      {:ok, response, rest} ->
        {:ok, response, rest}

      {:continuation, _continuation} ->
        case recv_data(state) do
          {:ok, data} -> recv_response(state, buffer <> data)
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp send_data(%{ssl: true, socket: socket}, data), do: :ssl.send(socket, data)
  defp send_data(%{socket: socket}, data), do: :gen_tcp.send(socket, data)

  defp recv_data(%{ssl: true} = state), do: :ssl.recv(state.socket, 0, state.timeout)
  defp recv_data(state), do: :gen_tcp.recv(state.socket, 0, state.timeout)

  defp set_active(%{ssl: true, socket: socket}, active), do: :ssl.setopts(socket, active: active)
  defp set_active(%{socket: socket}, active), do: :inet.setopts(socket, active: active)

  defp close_socket(%{socket: nil}), do: :ok
  defp close_socket(%{ssl: true, socket: socket}), do: :ssl.close(socket)
  defp close_socket(%{socket: socket}), do: :gen_tcp.close(socket)

  defp disconnect(state) do
    close_socket(state)
    %{state | socket: nil, state: :disconnected, buffer: <<>>}
  end

  defp connection_label(%{unix_socket: path}) when is_binary(path), do: path
  defp connection_label(state), do: "#{state.host}:#{state.port}"

  # -------------------------------------------------------------------
  # Credentials
  # -------------------------------------------------------------------

  defp build_credential_provider(opts, resolved_password) do
    case Keyword.get(opts, :credential_provider) do
      {module, provider_opts} ->
        {module, provider_opts}

      nil when is_binary(resolved_password) ->
        {Redis.CredentialProvider.Static,
         [password: resolved_password, username: Keyword.get(opts, :username)]}

      nil ->
        nil
    end
  end

  defp fetch_credentials(%{credential_provider: nil} = state), do: {:ok, state}

  defp fetch_credentials(%{credential_provider: {module, opts}} = state) do
    case module.get_credentials(opts) do
      {:ok, %{username: username, password: password}} ->
        {:ok, %{state | username: username, password: password}}

      {:error, reason} ->
        {:error, {:credential_provider_failed, reason}}
    end
  end

  defp resolve_password(nil), do: nil
  defp resolve_password(password) when is_binary(password), do: password
  defp resolve_password({module, function, arguments}), do: apply(module, function, arguments)

  # -------------------------------------------------------------------
  # Entries and subscribers
  # -------------------------------------------------------------------

  defp process_buffer(state) do
    case RESP2.decode(state.buffer) do
      {:ok, raw, rest} when is_binary(raw) ->
        dispatch_entry(raw, state.subscribers)
        process_buffer(%{state | buffer: rest})

      {:ok, _unexpected, rest} ->
        process_buffer(%{state | buffer: rest})

      {:continuation, _continuation} ->
        state
    end
  end

  defp dispatch_entry(raw, subscribers) do
    case Entry.parse(raw) do
      {:ok, entry} ->
        Enum.each(subscribers, &dispatch_to_subscriber(&1, entry))

      {:error, :invalid_monitor_entry} ->
        Logger.debug("Redis.Monitor: ignored malformed entry: #{inspect(raw)}")
    end
  end

  defp dispatch_to_subscriber({subscriber, %{filters: filters}}, entry) do
    if matches_filters?(entry, filters), do: send(subscriber, {:redis_monitor, entry})
  end

  defp put_subscriber(state, subscriber, filters) do
    case Map.get(state.subscribers, subscriber) do
      nil ->
        subscription = %{ref: Process.monitor(subscriber), filters: filters}
        %{state | subscribers: Map.put(state.subscribers, subscriber, subscription)}

      %{ref: ref} ->
        subscription = %{ref: ref, filters: filters}
        %{state | subscribers: Map.put(state.subscribers, subscriber, subscription)}
    end
  end

  defp delete_subscriber(state, subscriber) do
    case Map.pop(state.subscribers, subscriber) do
      {nil, _subscribers} ->
        state

      {%{ref: ref}, subscribers} ->
        Process.demonitor(ref, [:flush])
        %{state | subscribers: subscribers}
    end
  end

  defp normalize_filters(filters) do
    allowed = [:commands, :database, :client]

    with [] <- Keyword.keys(filters) -- allowed,
         {:ok, commands} <- normalize_commands(Keyword.get(filters, :commands)),
         {:ok, databases} <- normalize_databases(Keyword.get(filters, :database)),
         {:ok, client} <- normalize_client(Keyword.get(filters, :client)) do
      {:ok, %{commands: commands, databases: databases, client: client}}
    else
      [_ | _] = unknown -> {:error, {:invalid_filter, {:unknown_options, unknown}}}
      {:error, _reason} = error -> error
    end
  end

  defp normalize_commands(nil), do: {:ok, nil}
  defp normalize_commands(command) when is_binary(command), do: normalize_commands([command])

  defp normalize_commands(commands) when is_list(commands) do
    if Enum.all?(commands, &is_binary/1) and commands != [] do
      {:ok, commands |> Enum.map(&String.upcase/1) |> MapSet.new()}
    else
      {:error, {:invalid_filter, :commands}}
    end
  end

  defp normalize_commands(_commands), do: {:error, {:invalid_filter, :commands}}

  defp normalize_databases(nil), do: {:ok, nil}

  defp normalize_databases(database) when is_integer(database),
    do: normalize_databases([database])

  defp normalize_databases(databases) when is_list(databases) do
    if Enum.all?(databases, &(is_integer(&1) and &1 >= 0)) and databases != [] do
      {:ok, MapSet.new(databases)}
    else
      {:error, {:invalid_filter, :database}}
    end
  end

  defp normalize_databases(_databases), do: {:error, {:invalid_filter, :database}}

  defp normalize_client(nil), do: {:ok, nil}
  defp normalize_client(client) when is_binary(client), do: {:ok, client}
  defp normalize_client(%Regex{} = client), do: {:ok, client}
  defp normalize_client(_client), do: {:error, {:invalid_filter, :client}}

  defp matches_filters?(entry, filters) do
    matches_command?(entry, filters.commands) and
      matches_database?(entry, filters.databases) and
      matches_client?(entry, filters.client)
  end

  defp matches_command?(_entry, nil), do: true

  defp matches_command?(entry, commands),
    do: MapSet.member?(commands, String.upcase(entry.command))

  defp matches_database?(_entry, nil), do: true
  defp matches_database?(entry, databases), do: MapSet.member?(databases, entry.database)

  defp matches_client?(_entry, nil), do: true
  defp matches_client?(entry, client) when is_binary(client), do: entry.client == client
  defp matches_client?(entry, %Regex{} = client), do: Regex.match?(client, entry.client)

  # -------------------------------------------------------------------
  # Reconnection
  # -------------------------------------------------------------------

  defp schedule_reconnect(state) do
    Process.send_after(self(), :connect, state.backoff_current)
    next_backoff = min(state.backoff_current * 2, state.backoff_max)
    %{state | backoff_current: next_backoff}
  end
end

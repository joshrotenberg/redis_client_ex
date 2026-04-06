defmodule Redis.Connection do
  @moduledoc """
  GenServer managing a single TCP/TLS connection to a Redis server.

  Handles the socket lifecycle, RESP3 handshake, command sending/receiving,
  pipeline buffering, and automatic reconnection with exponential backoff.

  ## Options

    * `:host` - Redis host (default: "127.0.0.1")
    * `:port` - Redis port (default: 6379)
    * `:password` - auth password (string or `{mod, fun, args}` MFA tuple)
    * `:username` - auth username (Redis 6+ ACL)
    * `:database` - database number to SELECT
    * `:ssl` - enable TLS (default: false)
    * `:ssl_opts` - SSL options list
    * `:socket` - Unix domain socket path (overrides host/port)
    * `:name` - GenServer name registration
    * `:sync_connect` - connect synchronously in init (default: true)
    * `:backoff_initial` - initial reconnect delay ms (default: 500)
    * `:backoff_max` - max reconnect delay ms (default: 30_000)
    * `:protocol` - `:resp3` or `:resp2` (default: `:resp3`)
    * `:client_name` - CLIENT SETNAME value
    * `:timeout` - command timeout ms (default: 5_000)
    * `:credential_provider` - `{module, opts}` implementing `Redis.CredentialProvider`
      for dynamic/rotating credentials (e.g., cloud IAM tokens).
      When set, `:password` and `:username` are ignored.
    * `:exit_on_disconnection` - exit instead of reconnecting (default: false)
    * `:hibernate_after` - idle ms before hibernation (default: nil)

  A Redis URI string may be passed as the first (sole) argument:

      Connection.start_link("redis://:secret@localhost:6380/2")
  """

  use GenServer

  alias Redis.Protocol.{RESP2, RESP3}

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
    :backoff_initial,
    :backoff_max,
    :backoff_current,
    :timeout,
    :push_receiver,
    :credential_provider,
    protocol: :resp3,
    state: :disconnected,
    exit_on_disconnection: false,
    buffer: <<>>,
    callers: :queue.new()
  ]

  @behaviour Redis.Connection.Behaviour

  # -------------------------------------------------------------------
  # Public API
  # -------------------------------------------------------------------

  @doc """
  Returns a child spec for supervision trees.

      children = [
        {Redis.Connection, port: 6379, name: :redis}
      ]
  """
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  @spec start_link(keyword() | String.t()) :: GenServer.on_start()
  def start_link(uri) when is_binary(uri) do
    start_link(Redis.URI.parse(uri))
  end

  def start_link(opts) when is_list(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    {hibernate_after, opts} = Keyword.pop(opts, :hibernate_after)

    gen_opts = []
    gen_opts = if name, do: [{:name, name} | gen_opts], else: gen_opts

    gen_opts =
      if hibernate_after, do: [{:hibernate_after, hibernate_after} | gen_opts], else: gen_opts

    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  def start_link, do: start_link([])

  @impl Redis.Connection.Behaviour
  @spec command(GenServer.server(), [String.t()], keyword()) ::
          {:ok, term()} | {:error, term()}
  def command(conn, args, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5_000)
    GenServer.call(conn, {:command, args}, timeout)
  end

  @impl Redis.Connection.Behaviour
  @spec pipeline(GenServer.server(), [[String.t()]], keyword()) ::
          {:ok, [term()]} | {:error, term()}
  def pipeline(conn, commands, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5_000)
    GenServer.call(conn, {:pipeline, commands}, timeout)
  end

  @impl Redis.Connection.Behaviour
  @spec transaction(GenServer.server(), [[String.t()]], keyword()) ::
          {:ok, [term()]} | {:error, term()}
  def transaction(conn, commands, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5_000)
    GenServer.call(conn, {:transaction, commands}, timeout)
  end

  @doc """
  Executes a WATCH-based optimistic locking transaction.

  Watches the given keys, calls `fun` with the connection to read current
  values and compute commands, then executes those commands in a MULTI/EXEC
  block. If any watched key was modified by another client, EXEC returns nil
  and the function is retried (up to `:max_retries` times, default 3).

  The function `fun` receives the connection and must return either:
  - a list of commands to execute in the transaction
  - `{:abort, reason}` to abort without executing

  Returns `{:ok, results}` on success, `{:error, :watch_conflict}` if all
  retries are exhausted, or `{:error, reason}` on other failures.

  ## Example

      Redis.Connection.watch_transaction(conn, ["account:1", "account:2"], fn conn ->
        {:ok, bal1} = Redis.Connection.command(conn, ["GET", "account:1"])
        {:ok, bal2} = Redis.Connection.command(conn, ["GET", "account:2"])

        amount = 100
        new1 = String.to_integer(bal1) - amount
        new2 = String.to_integer(bal2) + amount

        [
          ["SET", "account:1", to_string(new1)],
          ["SET", "account:2", to_string(new2)]
        ]
      end)
  """
  @spec watch_transaction(
          GenServer.server(),
          [String.t()],
          (GenServer.server() -> [[String.t()]] | {:abort, term()}),
          keyword()
        ) :: {:ok, [term()]} | {:error, term()}
  def watch_transaction(conn, keys, fun, opts \\ []) do
    max_retries = Keyword.get(opts, :max_retries, 3)
    do_watch_transaction(conn, keys, fun, opts, max_retries)
  end

  defp do_watch_transaction(_conn, _keys, _fun, _opts, 0) do
    {:error, :watch_conflict}
  end

  defp do_watch_transaction(conn, keys, fun, opts, retries_left) do
    timeout = Keyword.get(opts, :timeout, 5_000)

    with {:ok, "OK"} <- GenServer.call(conn, {:command, ["WATCH" | keys]}, timeout),
         {:ok, commands} <- safe_build_commands(conn, fun),
         result <- GenServer.call(conn, {:transaction, commands}, timeout) do
      case result do
        {:error, :transaction_aborted} ->
          # WATCH conflict — EXEC returned nil, retry
          do_watch_transaction(conn, keys, fun, opts, retries_left - 1)

        other ->
          other
      end
    else
      {:abort, reason} ->
        # User aborted — unwatch and return error
        GenServer.call(conn, {:command, ["UNWATCH"]}, timeout)
        {:error, {:aborted, reason}}

      {:error, _} = error ->
        # Clean up WATCH state on error
        catch_unwatch(conn, timeout)
        error
    end
  end

  defp safe_build_commands(conn, fun) do
    case fun.(conn) do
      {:abort, _} = abort -> abort
      commands when is_list(commands) -> {:ok, commands}
    end
  rescue
    e ->
      {:error, {:user_function_error, e}}
  end

  defp catch_unwatch(conn, timeout) do
    GenServer.call(conn, {:command, ["UNWATCH"]}, timeout)
  catch
    :exit, _ -> :ok
  end

  @doc """
  Sends a command without waiting for a reply.
  Uses CLIENT REPLY OFF/ON internally.
  """
  @spec noreply_command(GenServer.server(), [String.t()], keyword()) :: :ok | {:error, term()}
  def noreply_command(conn, args, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5_000)
    GenServer.call(conn, {:noreply_command, args}, timeout)
  end

  @doc """
  Sends multiple commands without waiting for replies.
  """
  @spec noreply_pipeline(GenServer.server(), [[String.t()]], keyword()) :: :ok | {:error, term()}
  def noreply_pipeline(conn, commands, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5_000)
    GenServer.call(conn, {:noreply_pipeline, commands}, timeout)
  end

  @spec stop(GenServer.server()) :: :ok
  @impl Redis.Connection.Behaviour
  def stop(conn), do: GenServer.stop(conn, :normal)

  # -------------------------------------------------------------------
  # GenServer callbacks
  # -------------------------------------------------------------------

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    # Build credential provider from explicit option or legacy password/username
    credential_provider = build_credential_provider(opts)

    # Resolve MFA password at init time (used when no credential provider)
    password = resolve_password(Keyword.get(opts, :password))

    state = %__MODULE__{
      host: Keyword.get(opts, :host, "127.0.0.1"),
      port: Keyword.get(opts, :port, 6379),
      password: password,
      username: Keyword.get(opts, :username),
      database: Keyword.get(opts, :database),
      ssl: Keyword.get(opts, :ssl, false),
      ssl_opts: Keyword.get(opts, :ssl_opts, []),
      unix_socket: Keyword.get(opts, :socket),
      protocol: Keyword.get(opts, :protocol, :resp3),
      client_name: Keyword.get(opts, :client_name),
      backoff_initial: Keyword.get(opts, :backoff_initial, 500),
      backoff_max: Keyword.get(opts, :backoff_max, 30_000),
      backoff_current: Keyword.get(opts, :backoff_initial, 500),
      timeout: Keyword.get(opts, :timeout, 5_000),
      exit_on_disconnection: Keyword.get(opts, :exit_on_disconnection, false),
      push_receiver: Keyword.get(opts, :push_receiver),
      credential_provider: credential_provider
    }

    sync = Keyword.get(opts, :sync_connect, true)

    if sync do
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
  # Accept both 2-tuple (direct) and 3-tuple (from resilience wrappers)
  def handle_call({:command, args, _opts}, from, %{state: :ready} = state) do
    handle_call({:command, args}, from, state)
  end

  def handle_call({:pipeline, commands, _opts}, from, %{state: :ready} = state) do
    handle_call({:pipeline, commands}, from, state)
  end

  def handle_call({:transaction, commands, _opts}, from, %{state: :ready} = state) do
    handle_call({:transaction, commands}, from, state)
  end

  def handle_call({:command, args}, from, %{state: :ready} = state) do
    data = encode(state.protocol, args)

    case send_data(state, data) do
      :ok ->
        callers = :queue.in({from, :single}, state.callers)
        {:noreply, %{state | callers: callers}}

      {:error, reason} ->
        {:reply, {:error, %Redis.ConnectionError{reason: reason}}, handle_disconnect(state)}
    end
  end

  def handle_call({:pipeline, commands}, from, %{state: :ready} = state) do
    data = encode_pipeline(state.protocol, commands)

    case send_data(state, data) do
      :ok ->
        callers = :queue.in({from, {:pipeline, length(commands)}}, state.callers)
        {:noreply, %{state | callers: callers}}

      {:error, reason} ->
        {:reply, {:error, %Redis.ConnectionError{reason: reason}}, handle_disconnect(state)}
    end
  end

  def handle_call({:transaction, commands}, from, %{state: :ready} = state) do
    full = [["MULTI"]] ++ commands ++ [["EXEC"]]
    data = encode_pipeline(state.protocol, full)

    case send_data(state, data) do
      :ok ->
        callers = :queue.in({from, {:transaction, length(full)}}, state.callers)
        {:noreply, %{state | callers: callers}}

      {:error, reason} ->
        {:reply, {:error, %Redis.ConnectionError{reason: reason}}, handle_disconnect(state)}
    end
  end

  def handle_call({:noreply_command, args}, from, %{state: :ready} = state) do
    # CLIENT REPLY OFF, <command>, CLIENT REPLY ON
    # We only expect one response: the OK from CLIENT REPLY ON
    commands = [["CLIENT", "REPLY", "OFF"], args, ["CLIENT", "REPLY", "ON"]]
    data = encode_pipeline(state.protocol, commands)

    case send_data(state, data) do
      :ok ->
        callers = :queue.in({from, :noreply}, state.callers)
        {:noreply, %{state | callers: callers}}

      {:error, reason} ->
        {:reply, {:error, %Redis.ConnectionError{reason: reason}}, handle_disconnect(state)}
    end
  end

  def handle_call({:noreply_pipeline, commands}, from, %{state: :ready} = state) do
    full = [["CLIENT", "REPLY", "OFF"]] ++ commands ++ [["CLIENT", "REPLY", "ON"]]
    data = encode_pipeline(state.protocol, full)

    case send_data(state, data) do
      :ok ->
        callers = :queue.in({from, :noreply}, state.callers)
        {:noreply, %{state | callers: callers}}

      {:error, reason} ->
        {:reply, {:error, %Redis.ConnectionError{reason: reason}}, handle_disconnect(state)}
    end
  end

  def handle_call(_msg, _from, %{state: conn_state} = state) when conn_state != :ready do
    {:reply, {:error, %Redis.ConnectionError{reason: :not_connected}}, state}
  end

  @impl true
  def handle_info({:tcp, _socket, data}, state) do
    state = %{state | buffer: state.buffer <> data}
    state = process_buffer(state)
    {:noreply, state}
  end

  def handle_info({:ssl, _socket, data}, state) do
    state = %{state | buffer: state.buffer <> data}
    state = process_buffer(state)
    {:noreply, state}
  end

  def handle_info({closed, _socket}, state) when closed in [:tcp_closed, :ssl_closed] do
    Logger.warning("Redis: connection closed")
    state = fail_pending_callers(state, :closed)

    if state.exit_on_disconnection do
      {:stop, :disconnected, handle_disconnect(state)}
    else
      {:noreply, schedule_reconnect(handle_disconnect(state))}
    end
  end

  def handle_info({error, _socket, reason}, state) when error in [:tcp_error, :ssl_error] do
    Logger.warning("Redis: connection error: #{inspect(reason)}")
    state = fail_pending_callers(state, reason)

    if state.exit_on_disconnection do
      {:stop, {:connection_error, reason}, handle_disconnect(state)}
    else
      {:noreply, schedule_reconnect(handle_disconnect(state))}
    end
  end

  def handle_info(:connect, state) do
    case connect(state) do
      {:ok, state} ->
        {:noreply, state}

      {:error, reason} ->
        Logger.warning("Redis: connect failed: #{inspect(reason)}, retrying...")
        {:noreply, schedule_reconnect(state)}
    end
  end

  def handle_info({:EXIT, _port, _reason}, state) do
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{socket: nil}), do: :ok

  def terminate(_reason, %{socket: socket, ssl: true}) do
    :ssl.close(socket)
  end

  def terminate(_reason, %{socket: socket}) do
    :gen_tcp.close(socket)
  end

  # -------------------------------------------------------------------
  # Connection
  # -------------------------------------------------------------------

  defp connect(%{unix_socket: path} = state) when is_binary(path) do
    tcp_opts = [:binary, {:active, false}, {:packet, :raw}]

    with {:ok, socket} <-
           :gen_tcp.connect({:local, String.to_charlist(path)}, 0, tcp_opts, state.timeout),
         {:ok, state} <- handshake(%{state | socket: socket, state: :ready, buffer: <<>>}) do
      set_active(state, true)
      Logger.debug("Redis: connected to #{path}")
      {:ok, %{state | backoff_current: state.backoff_initial}}
    end
  end

  defp connect(state) do
    host = String.to_charlist(state.host)
    tcp_opts = [:binary, active: false, packet: :raw, nodelay: true]

    with {:ok, socket} <- :gen_tcp.connect(host, state.port, tcp_opts, state.timeout),
         {:ok, socket, state} <- maybe_upgrade_ssl(socket, state),
         {:ok, state} <- handshake(%{state | socket: socket, state: :ready, buffer: <<>>}) do
      set_active(state, true)
      Logger.debug("Redis: connected to #{state.host}:#{state.port}")
      {:ok, %{state | backoff_current: state.backoff_initial}}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_upgrade_ssl(socket, %{ssl: false} = state), do: {:ok, socket, state}

  defp maybe_upgrade_ssl(socket, %{ssl: true} = state) do
    ssl_opts = [verify: :verify_none] ++ state.ssl_opts

    case :ssl.connect(socket, ssl_opts, state.timeout) do
      {:ok, ssl_socket} -> {:ok, ssl_socket, %{state | socket: ssl_socket}}
      {:error, reason} -> {:error, {:ssl_error, reason}}
    end
  end

  defp handshake(state) do
    with {:ok, state} <- fetch_credentials(state),
         {:ok, state} <- negotiate_protocol(state),
         {:ok, state} <- maybe_auth(state),
         {:ok, state} <- maybe_select(state),
         {:ok, state} <- maybe_set_client_name(state) do
      maybe_set_client_info(state)
    end
  end

  defp negotiate_protocol(%{protocol: :resp3} = state) do
    args = hello_args(state.username, state.password)

    case sync_command(state, args) do
      {:ok, response, state} when is_map(response) and not is_struct(response) ->
        {:ok, %{state | protocol: :resp3}}

      {:ok, %Redis.Error{message: msg}, _state} ->
        classify_hello_error(msg, state)

      {:error, reason} ->
        {:error, {:handshake_failed, reason}}
    end
  end

  defp negotiate_protocol(%{protocol: :resp2} = state), do: {:ok, state}

  defp hello_args(nil, nil), do: ["HELLO", "3"]
  defp hello_args(nil, pw), do: ["HELLO", "3", "AUTH", "default", pw]
  defp hello_args(user, pw), do: ["HELLO", "3", "AUTH", user, pw]

  defp classify_hello_error(msg, state) do
    cond do
      String.contains?(msg, "WRONGPASS") or String.contains?(msg, "invalid password") ->
        {:error, {:auth_failed, msg}}

      String.contains?(msg, "NOAUTH") ->
        {:error, {:auth_required, msg}}

      true ->
        Logger.debug("Redis: HELLO 3 not supported, falling back to RESP2")
        {:ok, %{state | protocol: :resp2}}
    end
  end

  defp maybe_auth(%{password: nil} = state), do: {:ok, state}
  defp maybe_auth(%{protocol: :resp3} = state), do: {:ok, state}

  defp maybe_auth(state) do
    args =
      case state.username do
        nil -> ["AUTH", state.password]
        user -> ["AUTH", user, state.password]
      end

    case sync_command(state, args) do
      {:ok, "OK", state} -> {:ok, state}
      {:ok, %Redis.Error{message: msg}, _state} -> {:error, {:auth_failed, msg}}
      {:error, reason} -> {:error, {:auth_failed, reason}}
    end
  end

  defp maybe_select(%{database: nil} = state), do: {:ok, state}
  defp maybe_select(%{database: 0} = state), do: {:ok, state}

  defp maybe_select(state) do
    case sync_command(state, ["SELECT", to_string(state.database)]) do
      {:ok, "OK", state} -> {:ok, state}
      {:ok, %Redis.Error{message: msg}, _state} -> {:error, {:select_failed, msg}}
      {:error, reason} -> {:error, {:select_failed, reason}}
    end
  end

  defp maybe_set_client_name(%{client_name: nil} = state), do: {:ok, state}

  defp maybe_set_client_name(state) do
    case sync_command(state, ["CLIENT", "SETNAME", state.client_name]) do
      {:ok, "OK", state} -> {:ok, state}
      {:ok, _, state} -> {:ok, state}
      {:error, _} -> {:ok, state}
    end
  end

  # CLIENT SETINFO (Redis 7.2+) -- silently ignored on older versions
  defp maybe_set_client_info(state) do
    version = Application.spec(:redis, :vsn) |> to_string()

    # Best-effort: don't fail the handshake if these aren't supported
    state =
      case sync_command(state, ["CLIENT", "SETINFO", "LIB-NAME", "redis_client_ex"]) do
        {:ok, _, state} -> state
        {:error, _} -> state
      end

    case sync_command(state, ["CLIENT", "SETINFO", "LIB-VER", version]) do
      {:ok, _, state} -> {:ok, state}
      {:error, _} -> {:ok, state}
    end
  end

  defp sync_command(state, args) do
    data = encode(state.protocol, args)

    case send_data(state, data) do
      :ok ->
        case recv_response(state) do
          {:ok, response, rest} -> {:ok, response, %{state | buffer: rest}}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp recv_response(state, buffer \\ <<>>) do
    recv_fn =
      if state.ssl do
        fn -> :ssl.recv(state.socket, 0, state.timeout) end
      else
        fn -> :gen_tcp.recv(state.socket, 0, state.timeout) end
      end

    case decode(state.protocol, buffer) do
      {:ok, response, rest} ->
        {:ok, response, rest}

      {:continuation, _} ->
        case recv_fn.() do
          {:ok, data} -> recv_response(state, buffer <> data)
          {:error, reason} -> {:error, reason}
        end
    end
  end

  # -------------------------------------------------------------------
  # Credential provider
  # -------------------------------------------------------------------

  defp build_credential_provider(opts) do
    case Keyword.get(opts, :credential_provider) do
      {mod, provider_opts} ->
        {mod, provider_opts}

      nil ->
        password = Keyword.get(opts, :password)
        username = Keyword.get(opts, :username)

        if password do
          resolved = resolve_password(password)
          {Redis.CredentialProvider.Static, [password: resolved, username: username]}
        else
          nil
        end
    end
  end

  defp fetch_credentials(%{credential_provider: nil} = state), do: {:ok, state}

  defp fetch_credentials(%{credential_provider: {mod, opts}} = state) do
    case mod.get_credentials(opts) do
      {:ok, %{username: username, password: password}} ->
        {:ok, %{state | username: username, password: password}}

      {:error, reason} ->
        {:error, {:credential_provider_failed, reason}}
    end
  end

  # -------------------------------------------------------------------
  # MFA password resolution
  # -------------------------------------------------------------------

  defp resolve_password(nil), do: nil
  defp resolve_password(pw) when is_binary(pw), do: pw
  defp resolve_password({mod, fun, args}), do: apply(mod, fun, args)

  # -------------------------------------------------------------------
  # Send / receive helpers
  # -------------------------------------------------------------------

  defp send_data(%{ssl: true, socket: socket}, data), do: :ssl.send(socket, data)
  defp send_data(%{socket: socket}, data), do: :gen_tcp.send(socket, data)

  defp set_active(%{ssl: true, socket: socket}, active), do: :ssl.setopts(socket, active: active)
  defp set_active(%{socket: socket}, active), do: :inet.setopts(socket, active: active)

  # -------------------------------------------------------------------
  # Protocol encode/decode dispatch
  # -------------------------------------------------------------------

  defp encode(:resp3, args), do: RESP3.encode(args)
  defp encode(:resp2, args), do: RESP2.encode(args)

  defp encode_pipeline(:resp3, commands), do: RESP3.encode_pipeline(commands)
  defp encode_pipeline(:resp2, commands), do: RESP2.encode_pipeline(commands)

  defp decode(:resp3, data), do: RESP3.decode(data)
  defp decode(:resp2, data), do: RESP2.decode(data)

  # -------------------------------------------------------------------
  # Response processing
  # -------------------------------------------------------------------

  defp process_buffer(state) do
    # Check for push messages first — they can arrive interleaved with responses
    state = drain_pushes(state)

    case :queue.peek(state.callers) do
      :empty -> state
      {:value, {from, type}} -> process_caller(state, from, type)
    end
  end

  defp process_caller(state, from, :single) do
    case decode(state.protocol, state.buffer) do
      {:ok, response, rest} ->
        GenServer.reply(from, wrap_response(response))
        advance_and_continue(state, rest)

      {:continuation, _} ->
        state
    end
  end

  defp process_caller(state, from, {:pipeline, count}) do
    case decode_n(state.protocol, state.buffer, count) do
      {:ok, responses, rest} ->
        GenServer.reply(from, {:ok, responses})
        advance_and_continue(state, rest)

      {:continuation, _} ->
        state
    end
  end

  defp process_caller(state, from, {:transaction, count}) do
    case decode_n(state.protocol, state.buffer, count) do
      {:ok, responses, rest} ->
        GenServer.reply(from, transaction_reply(responses))
        advance_and_continue(state, rest)

      {:continuation, _} ->
        state
    end
  end

  defp process_caller(state, from, :noreply) do
    # Expect exactly one response: the OK from CLIENT REPLY ON
    case decode(state.protocol, state.buffer) do
      {:ok, _response, rest} ->
        GenServer.reply(from, :ok)
        advance_and_continue(state, rest)

      {:continuation, _} ->
        state
    end
  end

  defp advance_and_continue(state, rest) do
    process_buffer(%{state | buffer: rest, callers: :queue.drop(state.callers)})
  end

  defp transaction_reply(responses) do
    case List.last(responses) do
      nil -> {:error, :transaction_aborted}
      %Redis.Error{} = err -> {:error, err}
      results when is_list(results) -> {:ok, results}
      other -> {:ok, other}
    end
  end

  defp decode_n(_protocol, buffer, 0), do: {:ok, [], buffer}

  defp decode_n(protocol, buffer, count) do
    case decode(protocol, buffer) do
      {:ok, response, rest} ->
        case decode_n(protocol, rest, count - 1) do
          {:ok, responses, final_rest} -> {:ok, [response | responses], final_rest}
          {:continuation, _} = cont -> cont
        end

      {:continuation, _} = cont ->
        cont
    end
  end

  defp wrap_response(%Redis.Error{} = error), do: {:error, error}
  defp wrap_response(response), do: {:ok, response}

  # Drains all leading push messages from buffer before processing responses
  defp drain_pushes(state) do
    case decode(state.protocol, state.buffer) do
      {:ok, {:push, payload}, rest} ->
        route_push(state, payload)
        drain_pushes(%{state | buffer: rest})

      _ ->
        state
    end
  end

  defp route_push(state, ["invalidate" | keys]) do
    if state.push_receiver do
      send(state.push_receiver, {:redis_push, :invalidate, List.first(keys)})
    end
  end

  defp route_push(state, payload) do
    if state.push_receiver do
      send(state.push_receiver, {:redis_push, :unknown, payload})
    end
  end

  # -------------------------------------------------------------------
  # Reconnection
  # -------------------------------------------------------------------

  defp handle_disconnect(state) do
    if state.socket do
      if state.ssl, do: :ssl.close(state.socket), else: :gen_tcp.close(state.socket)
    end

    %{state | socket: nil, state: :disconnected, buffer: <<>>}
  end

  defp schedule_reconnect(state) do
    delay = state.backoff_current
    Process.send_after(self(), :connect, delay)
    next_backoff = min(delay * 2, state.backoff_max)
    %{state | backoff_current: next_backoff}
  end

  defp fail_pending_callers(state, reason) do
    error = {:error, %Redis.ConnectionError{reason: reason}}

    state.callers
    |> :queue.to_list()
    |> Enum.each(fn {from, _type} -> GenServer.reply(from, error) end)

    %{state | callers: :queue.new()}
  end
end

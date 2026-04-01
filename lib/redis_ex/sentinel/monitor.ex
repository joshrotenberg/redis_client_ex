defmodule RedisEx.Sentinel.Monitor do
  @moduledoc """
  Proactive sentinel failover monitor.

  Subscribes to `+switch-master` on a sentinel instance and notifies
  the parent Sentinel connection to reconnect before the old connection fails.

  ## Usage

  Typically started internally by `RedisEx.Sentinel`:

      {:ok, monitor} = Monitor.start_link(
        sentinel_host: "127.0.0.1",
        sentinel_port: 26379,
        group: "mymaster",
        notify: sentinel_pid
      )

  When a failover occurs, sends `{:failover, group, new_host, new_port}` to the
  notify pid.
  """

  use GenServer

  alias RedisEx.Protocol.RESP2

  require Logger

  defstruct [
    :sentinel_host,
    :sentinel_port,
    :sentinel_password,
    :group,
    :notify,
    :socket,
    :timeout,
    buffer: <<>>,
    backoff_current: 1_000,
    backoff_max: 30_000
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def stop(monitor), do: GenServer.stop(monitor, :normal)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    state = %__MODULE__{
      sentinel_host: Keyword.fetch!(opts, :sentinel_host),
      sentinel_port: Keyword.fetch!(opts, :sentinel_port),
      sentinel_password: Keyword.get(opts, :sentinel_password),
      group: Keyword.fetch!(opts, :group),
      notify: Keyword.fetch!(opts, :notify),
      timeout: Keyword.get(opts, :timeout, 5_000)
    }

    send(self(), :connect)
    {:ok, state}
  end

  @impl true
  def handle_info(:connect, state) do
    case connect_and_subscribe(state) do
      {:ok, state} ->
        Logger.debug("RedisEx.Sentinel.Monitor: subscribed to +switch-master on #{state.sentinel_host}:#{state.sentinel_port}")
        {:noreply, %{state | backoff_current: 1_000}}

      {:error, reason} ->
        Logger.warning("RedisEx.Sentinel.Monitor: connect failed: #{inspect(reason)}")
        Process.send_after(self(), :connect, state.backoff_current)
        next = min(state.backoff_current * 2, state.backoff_max)
        {:noreply, %{state | backoff_current: next}}
    end
  end

  def handle_info({:tcp, _socket, data}, state) do
    state = %{state | buffer: state.buffer <> data}
    state = process_messages(state)
    {:noreply, state}
  end

  def handle_info({:tcp_closed, _socket}, state) do
    Logger.warning("RedisEx.Sentinel.Monitor: connection closed, reconnecting...")
    Process.send_after(self(), :connect, state.backoff_current)
    {:noreply, %{state | socket: nil, buffer: <<>>}}
  end

  def handle_info({:tcp_error, _socket, _reason}, state) do
    Process.send_after(self(), :connect, state.backoff_current)
    {:noreply, %{state | socket: nil, buffer: <<>>}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{socket: nil}), do: :ok
  def terminate(_reason, %{socket: socket}), do: :gen_tcp.close(socket)

  # -------------------------------------------------------------------
  # Connection
  # -------------------------------------------------------------------

  defp connect_and_subscribe(state) do
    host = String.to_charlist(state.sentinel_host)
    tcp_opts = [:binary, active: false, packet: :raw, nodelay: true]

    with {:ok, socket} <- :gen_tcp.connect(host, state.sentinel_port, tcp_opts, state.timeout),
         :ok <- maybe_auth(socket, state),
         :ok <- subscribe_switch_master(socket) do
      :inet.setopts(socket, active: true)
      {:ok, %{state | socket: socket, buffer: <<>>}}
    end
  end

  defp maybe_auth(_socket, %{sentinel_password: nil}), do: :ok

  defp maybe_auth(socket, state) do
    :gen_tcp.send(socket, RESP2.encode(["AUTH", state.sentinel_password]))

    case :gen_tcp.recv(socket, 0, state.timeout) do
      {:ok, data} ->
        case RESP2.decode(data) do
          {:ok, "OK", _} -> :ok
          _ -> {:error, :sentinel_auth_failed}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp subscribe_switch_master(socket) do
    :gen_tcp.send(socket, RESP2.encode(["SUBSCRIBE", "+switch-master"]))
    # Don't wait for the subscribe confirmation — it'll come via active mode
    :ok
  end

  # -------------------------------------------------------------------
  # Message processing
  # -------------------------------------------------------------------

  defp process_messages(state) do
    case RESP2.decode(state.buffer) do
      {:ok, message, rest} ->
        state = %{state | buffer: rest}
        state = handle_message(message, state)
        process_messages(state)

      {:continuation, _} ->
        state
    end
  end

  defp handle_message(["message", "+switch-master", payload], state) do
    # Payload format: "master-name old-ip old-port new-ip new-port"
    case String.split(payload, " ") do
      [master_name, _old_ip, _old_port, new_ip, new_port] ->
        if master_name == state.group do
          port = String.to_integer(new_port)
          Logger.info("RedisEx.Sentinel.Monitor: failover detected for #{master_name} → #{new_ip}:#{port}")
          send(state.notify, {:failover, master_name, new_ip, port})
        end

      _ ->
        Logger.warning("RedisEx.Sentinel.Monitor: unexpected +switch-master payload: #{payload}")
    end

    state
  end

  # Subscribe confirmation
  defp handle_message(["subscribe", "+switch-master", _count], state), do: state
  defp handle_message(_msg, state), do: state
end

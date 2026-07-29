defmodule Redis.MonitorTest do
  use ExUnit.Case, async: false

  alias Redis.Connection
  alias Redis.Monitor
  alias Redis.Monitor.Entry

  test "streams structured command entries" do
    {:ok, monitor} = Monitor.start_link(port: 6398)
    :ok = Monitor.subscribe(monitor)
    {:ok, connection} = Connection.start_link(port: 6398)
    key = "monitor:#{System.unique_integer([:positive])}"

    assert {:ok, "OK"} = Connection.command(connection, ["SET", key, "value"])

    assert %Entry{
             database: 0,
             command: command,
             arguments: [^key, "value"]
           } =
             receive_matching_entry(fn entry ->
               String.upcase(entry.command) == "SET" and entry.arguments == [key, "value"]
             end)

    assert String.upcase(command) == "SET"

    Connection.stop(connection)
    Monitor.stop(monitor)
  end

  test "applies independent subscriber filters" do
    {:ok, monitor} = Monitor.start_link(port: 6398)
    :ok = Monitor.subscribe(monitor, commands: "GET", database: 0)
    {:ok, connection} = Connection.start_link(port: 6398)
    key = "monitor:filter:#{System.unique_integer([:positive])}"

    assert {:ok, "OK"} = Connection.command(connection, ["SET", key, "value"])
    assert {:ok, "value"} = Connection.command(connection, ["GET", key])

    assert %Entry{command: command, arguments: [^key]} =
             receive_matching_entry(fn entry ->
               String.upcase(entry.command) == "GET" and entry.arguments == [key]
             end)

    assert String.upcase(command) == "GET"
    refute_receive {:redis_monitor, %Entry{command: "SET", arguments: [^key, "value"]}}, 100

    Connection.stop(connection)
    Monitor.stop(monitor)
  end

  test "authenticates, selects a database, and accepts a Redis URI" do
    {:ok, monitor} = Monitor.start_link("redis://:testpass@127.0.0.1:6399/2")
    :ok = Monitor.subscribe(monitor)
    {:ok, connection} = Connection.start_link(port: 6399, password: "testpass", database: 2)
    key = "monitor:auth:#{System.unique_integer([:positive])}"

    assert {:ok, "OK"} = Connection.command(connection, ["SET", key, "value"])

    assert %Entry{database: 2, arguments: [^key, "value"]} =
             receive_matching_entry(fn entry ->
               String.upcase(entry.command) == "SET" and entry.arguments == [key, "value"]
             end)

    Connection.stop(connection)
    Monitor.stop(monitor)
  end

  test "removes subscribers when they exit" do
    {:ok, monitor} = Monitor.start_link(port: 6398)
    subscriber = spawn(fn -> Process.sleep(:infinity) end)

    :ok = Monitor.subscribe(monitor, subscriber, [])
    assert subscriber in Monitor.subscribers(monitor)

    Process.exit(subscriber, :kill)
    ref = Process.monitor(subscriber)
    assert_receive {:DOWN, ^ref, :process, ^subscriber, :noproc}

    eventually(fn -> subscriber not in Monitor.subscribers(monitor) end)

    Monitor.stop(monitor)
  end

  test "rejects invalid subscriber filters" do
    {:ok, monitor} = Monitor.start_link(port: 6398)

    assert {:error, {:invalid_filter, :commands}} =
             Monitor.subscribe(monitor, commands: [])

    assert {:error, {:invalid_filter, {:unknown_options, [:unknown]}}} =
             Monitor.subscribe(monitor, unknown: true)

    Monitor.stop(monitor)
  end

  test "reconnects and resumes streaming after a server restart" do
    port = 6470
    {:ok, server} = RedisServerWrapper.Server.start_link(port: port)

    {:ok, monitor} =
      Monitor.start_link(port: port, backoff_initial: 50, backoff_max: 100)

    :ok = Monitor.subscribe(monitor)
    {:ok, connection} = Connection.start_link(port: port)
    initial_key = "monitor:before-restart"

    assert {:ok, "OK"} = Connection.command(connection, ["SET", initial_key, "value"])

    assert %Entry{arguments: [^initial_key, "value"]} =
             receive_matching_entry(fn entry -> entry.arguments == [initial_key, "value"] end)

    Connection.stop(connection)
    RedisServerWrapper.Server.stop(server)

    eventually(fn -> :sys.get_state(monitor).state == :disconnected end)
    {:ok, restarted_server} = start_server_when_available(port)
    eventually(fn -> :sys.get_state(monitor).state == :ready end, 200)

    {:ok, connection} = Connection.start_link(port: port)
    restarted_key = "monitor:after-restart"

    assert {:ok, "OK"} = Connection.command(connection, ["SET", restarted_key, "value"])

    assert %Entry{arguments: [^restarted_key, "value"]} =
             receive_matching_entry(fn entry -> entry.arguments == [restarted_key, "value"] end)

    Connection.stop(connection)
    Monitor.stop(monitor)
    RedisServerWrapper.Server.stop(restarted_server)
  end

  defp receive_matching_entry(predicate, timeout \\ 2_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_receive_matching_entry(predicate, deadline)
  end

  defp do_receive_matching_entry(predicate, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:redis_monitor, %Entry{} = entry} ->
        if predicate.(entry), do: entry, else: do_receive_matching_entry(predicate, deadline)
    after
      remaining -> flunk("timed out waiting for matching Redis MONITOR entry")
    end
  end

  defp eventually(predicate, attempts \\ 50) do
    cond do
      predicate.() ->
        :ok

      attempts == 0 ->
        flunk("condition did not become true")

      true ->
        Process.sleep(10)
        eventually(predicate, attempts - 1)
    end
  end

  defp start_server_when_available(port, attempts \\ 20)

  defp start_server_when_available(_port, 0),
    do: flunk("Redis server port did not become available")

  defp start_server_when_available(port, attempts) do
    case RedisServerWrapper.Server.start_link(port: port) do
      {:ok, server} ->
        {:ok, server}

      {:error, _reason} ->
        Process.sleep(50)
        start_server_when_available(port, attempts - 1)
    end
  end
end

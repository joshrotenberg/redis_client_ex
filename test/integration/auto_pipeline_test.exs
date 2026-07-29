defmodule Redis.AutoPipelineIntegrationTest do
  use ExUnit.Case, async: false

  alias Redis.Connection
  alias Redis.Connection.Pool

  @flush_event [:redis_ex, :auto_pipeline, :flush]

  test "batches concurrent commands and returns each caller's own reply" do
    {:ok, conn} =
      Connection.start_link(
        port: 6398,
        auto_pipeline: true,
        auto_pipeline_window: 20
      )

    assert {:ok, "OK"} = Connection.command(conn, ["SET", "auto:counter", "0"])
    attach_flush_handler()

    results =
      1..20
      |> Task.async_stream(
        fn _index -> Connection.command(conn, ["INCR", "auto:counter"]) end,
        max_concurrency: 20,
        ordered: false,
        timeout: 5_000
      )
      |> Enum.map(fn {:ok, {:ok, value}} -> value end)
      |> Enum.sort()

    assert results == Enum.to_list(1..20)
    assert_receive {:auto_pipeline_flush, %{batch_size: 20}, %{reason: :window}}, 1_000
  end

  test "flushes immediately when the maximum batch size is reached" do
    {:ok, setup_conn} = Connection.start_link(port: 6398)
    assert {:ok, "OK"} = Connection.command(setup_conn, ["SET", "auto:max", "0"])

    {:ok, conn} =
      Connection.start_link(
        port: 6398,
        auto_pipeline: true,
        auto_pipeline_window: 1_000,
        auto_pipeline_max_size: 3
      )

    attach_flush_handler()

    tasks =
      for _index <- 1..3 do
        Task.async(fn -> Connection.command(conn, ["INCR", "auto:max"]) end)
      end

    assert [1, 2, 3] =
             tasks
             |> Enum.map(&Task.await(&1, 2_000))
             |> Enum.map(fn {:ok, value} -> value end)
             |> Enum.sort()

    assert_receive {:auto_pipeline_flush, %{batch_size: 3}, %{reason: :max_size}}, 500
  end

  test "flushes queued commands before an explicit pipeline" do
    {:ok, setup_conn} = Connection.start_link(port: 6398)
    assert {:ok, _deleted} = Connection.command(setup_conn, ["DEL", "auto:barrier"])

    {:ok, conn} =
      Connection.start_link(
        port: 6398,
        auto_pipeline: true,
        auto_pipeline_window: 1_000
      )

    attach_flush_handler()
    set_task = Task.async(fn -> Connection.command(conn, ["SET", "auto:barrier", "before"]) end)

    eventually(fn -> :sys.get_state(conn).auto_pipeline_size == 1 end)

    assert {:ok, ["before"]} =
             Connection.pipeline(conn, [["GET", "auto:barrier"]])

    assert {:ok, "OK"} = Task.await(set_task, 1_000)
    assert_receive {:auto_pipeline_flush, %{batch_size: 1}, %{reason: :barrier}}, 500
  end

  test "a single-connection pool batches on its physical connection" do
    {:ok, pool} =
      Pool.start_link(
        pool_size: 1,
        port: 6398,
        auto_pipeline: true,
        auto_pipeline_window: 20
      )

    assert {:ok, "OK"} = Pool.command(pool, ["SET", "auto:pool", "0"])
    attach_flush_handler()

    results =
      1..10
      |> Task.async_stream(
        fn _index -> Pool.command(pool, ["INCR", "auto:pool"]) end,
        max_concurrency: 10,
        ordered: false,
        timeout: 5_000
      )
      |> Enum.map(fn {:ok, {:ok, value}} -> value end)
      |> Enum.sort()

    assert results == Enum.to_list(1..10)
    assert_receive {:auto_pipeline_flush, %{batch_size: 10}, %{reason: :window}}, 1_000
  end

  test "typed response parsing remains transparent for batched callers" do
    {:ok, setup_conn} = Connection.start_link(port: 6398)

    assert {:ok, 2} =
             Connection.command(
               setup_conn,
               ["HSET", "auto:typed", "name", "Ada", "role", "admin"]
             )

    {:ok, conn} =
      Connection.start_link(
        port: 6398,
        protocol: :resp2,
        auto_pipeline: true,
        auto_pipeline_window: 20
      )

    tasks =
      for _index <- 1..2 do
        Task.async(fn ->
          Connection.command(conn, ["HGETALL", "auto:typed"], response: :typed)
        end)
      end

    assert [{:ok, expected}, {:ok, expected}] =
             Enum.map(tasks, &Task.await(&1, 1_000))

    assert expected == %{"name" => "Ada", "role" => "admin"}
  end

  test "pending unsent callers receive an error when the socket closes" do
    {:ok, conn} =
      Connection.start_link(
        port: 6398,
        client_name: "auto_pipeline_disconnect",
        auto_pipeline: true,
        auto_pipeline_window: 1_000,
        backoff_initial: 60_000
      )

    {:ok, admin} = Connection.start_link(port: 6398)

    assert {:ok, clients} =
             Connection.command(admin, ["CLIENT", "LIST"], response: :typed)

    client = Enum.find(clients, &(&1.name == "auto_pipeline_disconnect"))
    assert client

    pending = Task.async(fn -> Connection.command(conn, ["PING"], timeout: 2_000) end)
    eventually(fn -> :sys.get_state(conn).auto_pipeline_size == 1 end)

    assert {:ok, 1} =
             Connection.command(admin, ["CLIENT", "KILL", "ID", to_string(client.id)])

    assert {:error, %Redis.ConnectionError{reason: :closed}} =
             Task.await(pending, 1_000)
  end

  defp attach_flush_handler do
    handler_id = "auto-pipeline-test-#{System.unique_integer([:positive])}"
    test_pid = self()

    :telemetry.attach(
      handler_id,
      @flush_event,
      fn _event, measurements, metadata, pid ->
        send(pid, {:auto_pipeline_flush, measurements, metadata})
      end,
      test_pid
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp eventually(fun, attempts \\ 100)
  defp eventually(fun, 0), do: assert(fun.())

  defp eventually(fun, attempts) do
    if fun.() do
      :ok
    else
      Process.sleep(5)
      eventually(fun, attempts - 1)
    end
  end
end

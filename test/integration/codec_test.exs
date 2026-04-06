defmodule Redis.Integration.CodecTest do
  use ExUnit.Case, async: false

  alias Redis.Codec
  alias Redis.Connection

  # Uses redis-server started in test_helper.exs on port 6398 (no auth)

  setup do
    {:ok, conn} = Connection.start_link(port: 6398)

    on_exit(fn ->
      try do
        Connection.stop(conn)
      catch
        :exit, _ -> :ok
      end
    end)

    %{conn: conn}
  end

  describe "JSON codec round-trip" do
    test "SET/GET with a map", %{conn: conn} do
      codec = Codec.JSON
      key = "codec:json:#{System.unique_integer([:positive])}"

      data = %{"name" => "Alice", "age" => 30, "tags" => ["admin", "user"]}
      {:ok, encoded} = Codec.encode_value(codec, data)
      assert {:ok, "OK"} = Connection.command(conn, ["SET", key, encoded])

      {:ok, raw} = Connection.command(conn, ["GET", key])
      assert {:ok, ^data} = Codec.decode_result(codec, raw)
    end

    test "SET/GET with a list", %{conn: conn} do
      codec = Codec.JSON
      key = "codec:json:list:#{System.unique_integer([:positive])}"

      data = [1, "two", 3.0, nil, true]
      {:ok, encoded} = Codec.encode_value(codec, data)
      assert {:ok, "OK"} = Connection.command(conn, ["SET", key, encoded])

      {:ok, raw} = Connection.command(conn, ["GET", key])
      assert {:ok, ^data} = Codec.decode_result(codec, raw)
    end

    test "pipeline with decode_results", %{conn: conn} do
      codec = Codec.JSON
      k1 = "codec:json:p1:#{System.unique_integer([:positive])}"
      k2 = "codec:json:p2:#{System.unique_integer([:positive])}"

      {:ok, v1} = Codec.encode_value(codec, %{"x" => 1})
      {:ok, v2} = Codec.encode_value(codec, %{"y" => 2})

      {:ok, _} =
        Connection.pipeline(conn, [
          ["SET", k1, v1],
          ["SET", k2, v2]
        ])

      {:ok, [raw1, raw2]} =
        Connection.pipeline(conn, [
          ["GET", k1],
          ["GET", k2]
        ])

      assert {:ok, [%{"x" => 1}, %{"y" => 2}]} = Codec.decode_results(codec, [raw1, raw2])
    end

    test "GET returns nil for missing key", %{conn: conn} do
      codec = Codec.JSON
      {:ok, raw} = Connection.command(conn, ["GET", "codec:nonexistent:key"])
      assert {:ok, nil} = Codec.decode_result(codec, raw)
    end
  end

  describe "Term codec round-trip" do
    test "SET/GET preserves atoms and tuples", %{conn: conn} do
      codec = Codec.Term
      key = "codec:term:#{System.unique_integer([:positive])}"

      data = %{status: :active, counts: {1, 2, 3}}
      {:ok, encoded} = Codec.encode_value(codec, data)
      assert {:ok, "OK"} = Connection.command(conn, ["SET", key, encoded])

      {:ok, raw} = Connection.command(conn, ["GET", key])
      assert {:ok, ^data} = Codec.decode_result(codec, raw)
    end
  end

  describe "Raw codec round-trip" do
    test "SET/GET passes strings through", %{conn: conn} do
      codec = Codec.Raw
      key = "codec:raw:#{System.unique_integer([:positive])}"

      {:ok, encoded} = Codec.encode_value(codec, "plain text")
      assert {:ok, "OK"} = Connection.command(conn, ["SET", key, encoded])

      {:ok, raw} = Connection.command(conn, ["GET", key])
      assert {:ok, "plain text"} = Codec.decode_result(codec, raw)
    end
  end
end

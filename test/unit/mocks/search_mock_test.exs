defmodule Redis.Search.MockTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Redis.Search
  alias Redis.Search.Result

  # A simple GenServer test double that records commands sent to it
  # and returns canned responses. Since Redis.Connection.command/3
  # does GenServer.call(conn, {:command, args}, timeout), we handle
  # that message directly.
  defmodule TestConn do
    use GenServer

    def start_link(responses \\ []) do
      GenServer.start_link(__MODULE__, responses)
    end

    def commands(pid) do
      GenServer.call(pid, :get_commands)
    end

    @impl true
    def init(responses) do
      {:ok, %{responses: responses, commands: []}}
    end

    @impl true
    def handle_call({:command, args}, _from, state) do
      {response, remaining} =
        case state.responses do
          [r | rest] -> {r, rest}
          [] -> {{:ok, "OK"}, []}
        end

      {:reply, response, %{state | responses: remaining, commands: state.commands ++ [args]}}
    end

    @impl true
    def handle_call(:get_commands, _from, state) do
      {:reply, state.commands, state}
    end
  end

  # -------------------------------------------------------------------
  # create_index command building
  # -------------------------------------------------------------------

  describe "create_index/3" do
    test "builds correct FT.CREATE for hash index with text and numeric fields" do
      {:ok, conn} = TestConn.start_link([{:ok, "OK"}])

      :ok =
        Search.create_index(conn, "movies",
          prefix: "movie:",
          fields: [
            title: :text,
            year: :numeric
          ]
        )

      [cmd] = TestConn.commands(conn)
      assert hd(cmd) == "FT.CREATE"
      assert "movies" in cmd
      assert "ON" in cmd
      assert "HASH" in cmd
      assert "PREFIX" in cmd
      assert "movie:" in cmd
      assert "SCHEMA" in cmd

      # After SCHEMA, we expect: title TEXT year NUMERIC
      schema_idx = Enum.find_index(cmd, &(&1 == "SCHEMA"))
      schema_part = Enum.drop(cmd, schema_idx + 1)
      assert schema_part == ["title", "TEXT", "year", "NUMERIC"]
    end

    test "builds correct FT.CREATE for json index with field aliases" do
      {:ok, conn} = TestConn.start_link([{:ok, "OK"}])

      :ok =
        Search.create_index(conn, "docs",
          on: :json,
          prefix: "doc:",
          fields: [
            title: :text,
            score: {:numeric, sortable: true}
          ]
        )

      [cmd] = TestConn.commands(conn)
      assert "JSON" in cmd

      schema_idx = Enum.find_index(cmd, &(&1 == "SCHEMA"))
      schema_part = Enum.drop(cmd, schema_idx + 1)

      # JSON fields get $.prefix and AS alias
      assert "$.title" in schema_part
      assert "$.score" in schema_part
      assert "AS" in schema_part
      assert "SORTABLE" in schema_part
    end

    test "propagates error from connection" do
      {:ok, conn} = TestConn.start_link([{:error, "ERR index already exists"}])

      assert {:error, "ERR index already exists"} ==
               Search.create_index(conn, "idx", fields: [name: :text])
    end
  end

  # -------------------------------------------------------------------
  # find query building via command capture
  # -------------------------------------------------------------------

  describe "find/4 query building" do
    test "simple text search builds correct FT.SEARCH command" do
      resp3_result = %{"total_results" => 0, "results" => []}
      {:ok, conn} = TestConn.start_link([{:ok, resp3_result}])

      {:ok, _result} = Search.find(conn, "movies", "dark knight")

      [cmd] = TestConn.commands(conn)
      assert Enum.at(cmd, 0) == "FT.SEARCH"
      assert Enum.at(cmd, 1) == "movies"
      assert Enum.at(cmd, 2) == "dark knight"
    end

    test "where with :gt filter builds correct numeric range" do
      resp3_result = %{"total_results" => 0, "results" => []}
      {:ok, conn} = TestConn.start_link([{:ok, resp3_result}])

      {:ok, _} = Search.find(conn, "movies", "*", where: [year: {:gt, 2000}])

      [cmd] = TestConn.commands(conn)
      query = Enum.at(cmd, 2)
      assert query == "@year:[(2000 +inf]"
    end

    test "where with :between filter builds correct range" do
      resp3_result = %{"total_results" => 0, "results" => []}
      {:ok, conn} = TestConn.start_link([{:ok, resp3_result}])

      {:ok, _} = Search.find(conn, "idx", "*", where: [score: {:between, 1, 100}])

      [cmd] = TestConn.commands(conn)
      query = Enum.at(cmd, 2)
      assert query == "@score:[1 100]"
    end

    test "where with :tag filter builds correct tag query" do
      resp3_result = %{"total_results" => 0, "results" => []}
      {:ok, conn} = TestConn.start_link([{:ok, resp3_result}])

      {:ok, _} = Search.find(conn, "idx", "*", where: [genre: {:tag, "action"}])

      [cmd] = TestConn.commands(conn)
      query = Enum.at(cmd, 2)
      assert query == "@genre:{action}"
    end

    test "where with :any filter builds tag OR query" do
      resp3_result = %{"total_results" => 0, "results" => []}
      {:ok, conn} = TestConn.start_link([{:ok, resp3_result}])

      {:ok, _} = Search.find(conn, "idx", "*", where: [genre: {:any, ["action", "drama"]}])

      [cmd] = TestConn.commands(conn)
      query = Enum.at(cmd, 2)
      assert query == "@genre:{action|drama}"
    end

    test "multiple filters are combined with base query" do
      resp3_result = %{"total_results" => 0, "results" => []}
      {:ok, conn} = TestConn.start_link([{:ok, resp3_result}])

      {:ok, _} =
        Search.find(conn, "idx", "batman", where: [year: {:gte, 2000}, genre: {:tag, "action"}])

      [cmd] = TestConn.commands(conn)
      query = Enum.at(cmd, 2)
      assert query == "batman @year:[2000 +inf] @genre:{action}"
    end

    test "sort and limit options are translated" do
      resp3_result = %{"total_results" => 0, "results" => []}
      {:ok, conn} = TestConn.start_link([{:ok, resp3_result}])

      {:ok, _} = Search.find(conn, "idx", "*", sort: {:year, :desc}, limit: 5)

      [cmd] = TestConn.commands(conn)
      assert "SORTBY" in cmd
      assert "year" in cmd
      assert "DESC" in cmd
      assert "LIMIT" in cmd
      assert "0" in cmd
      assert "5" in cmd
    end
  end

  # -------------------------------------------------------------------
  # Result parsing (RESP3 map format)
  # -------------------------------------------------------------------

  describe "find/4 result parsing" do
    test "parses RESP3 map format with documents" do
      resp3_result = %{
        "total_results" => 2,
        "results" => [
          %{
            "id" => "movie:1",
            "extra_attributes" => %{"title" => "The Dark Knight", "year" => "2008"}
          },
          %{
            "id" => "movie:2",
            "extra_attributes" => %{"title" => "Batman Begins", "year" => "2005"}
          }
        ]
      }

      {:ok, conn} = TestConn.start_link([{:ok, resp3_result}])
      {:ok, %Result{} = result} = Search.find(conn, "movies", "*")

      assert result.total == 2
      assert length(result.results) == 2

      [first, second] = result.results
      assert first[:id] == "movie:1"
      assert first["title"] == "The Dark Knight"
      # With coerce: true (default), "2008" becomes 2008
      assert first["year"] == 2008

      assert second[:id] == "movie:2"
      assert second["title"] == "Batman Begins"
      assert second["year"] == 2005
    end

    test "parses empty result set" do
      resp3_result = %{"total_results" => 0, "results" => []}
      {:ok, conn} = TestConn.start_link([{:ok, resp3_result}])

      {:ok, %Result{} = result} = Search.find(conn, "movies", "nonexistent")

      assert result.total == 0
      assert result.results == []
    end
  end

  # -------------------------------------------------------------------
  # Coercion
  # -------------------------------------------------------------------

  describe "coercion" do
    test "coerces numeric strings to integers by default" do
      resp3_result = %{
        "total_results" => 1,
        "results" => [
          %{"id" => "doc:1", "extra_attributes" => %{"count" => "42", "name" => "test"}}
        ]
      }

      {:ok, conn} = TestConn.start_link([{:ok, resp3_result}])
      {:ok, %Result{} = result} = Search.find(conn, "idx", "*")

      [doc] = result.results
      assert doc["count"] == 42
      assert is_integer(doc["count"])
      assert doc["name"] == "test"
    end

    test "coerces numeric strings to floats when not pure integers" do
      resp3_result = %{
        "total_results" => 1,
        "results" => [
          %{"id" => "doc:1", "extra_attributes" => %{"score" => "3.14"}}
        ]
      }

      {:ok, conn} = TestConn.start_link([{:ok, resp3_result}])
      {:ok, %Result{} = result} = Search.find(conn, "idx", "*")

      [doc] = result.results
      assert doc["score"] == 3.14
      assert is_float(doc["score"])
    end

    test "skips coercion when coerce: false" do
      resp3_result = %{
        "total_results" => 1,
        "results" => [
          %{"id" => "doc:1", "extra_attributes" => %{"year" => "2008", "score" => "9.5"}}
        ]
      }

      {:ok, conn} = TestConn.start_link([{:ok, resp3_result}])
      {:ok, %Result{} = result} = Search.find(conn, "idx", "*", coerce: false)

      [doc] = result.results
      assert doc["year"] == "2008"
      assert doc["score"] == "9.5"
    end
  end

  # -------------------------------------------------------------------
  # Aggregate result parsing
  # -------------------------------------------------------------------

  describe "aggregate/3 result parsing" do
    test "parses RESP3 aggregate result" do
      resp3_result = %{
        "total_results" => 2,
        "results" => [
          %{"extra_attributes" => %{"genre" => "action", "total" => "15"}},
          %{"extra_attributes" => %{"genre" => "drama", "total" => "8"}}
        ]
      }

      {:ok, conn} = TestConn.start_link([{:ok, resp3_result}])

      {:ok, %Result{} = result} =
        Search.aggregate(conn, "movies",
          group_by: :genre,
          reduce: [count: "total"]
        )

      assert result.total == 2
      assert length(result.results) == 2

      [first, second] = result.results
      # Aggregate results do not have :id
      assert first["genre"] == "action"
      assert first["total"] == 15
      assert second["genre"] == "drama"
      assert second["total"] == 8
    end
  end

  # -------------------------------------------------------------------
  # add command building
  # -------------------------------------------------------------------

  describe "add/5" do
    test "builds HSET command for hash documents" do
      {:ok, conn} = TestConn.start_link([{:ok, 3}])

      Search.add(conn, "movies", "movie:1", %{
        title: "Inception",
        year: 2010
      })

      [cmd] = TestConn.commands(conn)
      assert hd(cmd) == "HSET"
      assert Enum.at(cmd, 1) == "movie:1"
      # Remaining elements are field-value pairs (order may vary due to map)
      fields = Enum.drop(cmd, 2)
      field_map = fields |> Enum.chunk_every(2) |> Map.new(fn [k, v] -> {k, v} end)
      assert field_map["title"] == "Inception"
      assert field_map["year"] == "2010"
    end

    test "builds JSON.SET command for json documents" do
      {:ok, conn} = TestConn.start_link([{:ok, "OK"}])

      Search.add(conn, "movies", "movie:1", %{title: "Inception", year: 2010}, on: :json)

      [cmd] = TestConn.commands(conn)
      assert Enum.at(cmd, 0) == "JSON.SET"
      assert Enum.at(cmd, 1) == "movie:1"
      assert Enum.at(cmd, 2) == "$"

      json = Enum.at(cmd, 3)
      decoded = Jason.decode!(json)
      assert decoded["title"] == "Inception"
      assert decoded["year"] == 2010
    end
  end
end

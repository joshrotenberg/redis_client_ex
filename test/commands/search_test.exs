defmodule Redis.Commands.SearchTest do
  use ExUnit.Case, async: true

  alias Redis.Commands.Search

  describe "index management" do
    test "CREATE hash index with schema" do
      cmd =
        Search.create("idx:users", :hash,
          prefix: "user:",
          schema: [
            {"name", :text},
            {"age", :numeric, sortable: true},
            {"email", :tag}
          ]
        )

      assert ["FT.CREATE", "idx:users", "ON", "HASH", "PREFIX", "1", "user:",
              "SCHEMA", "name", "TEXT", "age", "NUMERIC", "SORTABLE", "email", "TAG"] = cmd
    end

    test "CREATE JSON index with AS aliases" do
      cmd =
        Search.create("idx:docs", :json,
          prefix: "doc:",
          schema: [
            {"$.title", :text, as: "title"},
            {"$.score", :numeric, as: "score", sortable: true}
          ]
        )

      assert ["FT.CREATE", "idx:docs", "ON", "JSON", "PREFIX", "1", "doc:",
              "SCHEMA", "$.title", "AS", "title", "TEXT",
              "$.score", "AS", "score", "NUMERIC", "SORTABLE"] = cmd
    end

    test "CREATE with stopwords" do
      cmd = Search.create("idx", :hash, schema: [{"f", :text}], stopwords: 0)
      assert "STOPWORDS" in cmd
      assert "0" in cmd
    end

    test "DROPINDEX" do
      assert Search.dropindex("idx") == ["FT.DROPINDEX", "idx"]
      assert Search.dropindex("idx", dd: true) == ["FT.DROPINDEX", "idx", "DD"]
    end

    test "ALTER" do
      cmd = Search.alter("idx", {"newfield", :tag})
      assert cmd == ["FT.ALTER", "idx", "SCHEMA", "ADD", "newfield", "TAG"]
    end

    test "INFO" do
      assert Search.info("idx") == ["FT.INFO", "idx"]
    end

    test "_LIST" do
      assert Search.list() == ["FT._LIST"]
    end
  end

  describe "search" do
    test "basic search" do
      assert Search.search("idx", "@name:Alice") == ["FT.SEARCH", "idx", "@name:Alice"]
    end

    test "search with options" do
      cmd =
        Search.search("idx", "*",
          return: ["name", "age"],
          sortby: {"age", :desc},
          limit: {0, 20},
          nocontent: true,
          dialect: 3
        )

      assert "NOCONTENT" in cmd
      assert "RETURN" in cmd
      assert "SORTBY" in cmd
      assert "LIMIT" in cmd
      assert "DIALECT" in cmd
    end

    test "search with params" do
      cmd = Search.search("idx", "@name:$name", params: [{:name, "Alice"}])
      assert "PARAMS" in cmd
    end
  end

  describe "aggregate" do
    test "basic aggregate" do
      cmd =
        Search.aggregate("idx", "*",
          groupby: ["@city"],
          reduce: [{"COUNT", 0, as: "count"}],
          sortby: [{"@count", :desc}],
          limit: {0, 10}
        )

      assert "FT.AGGREGATE" = hd(cmd)
      assert "GROUPBY" in cmd
      assert "REDUCE" in cmd
      assert "SORTBY" in cmd
      assert "LIMIT" in cmd
    end

    test "aggregate with apply" do
      cmd = Search.aggregate("idx", "*", apply: {"@price * @qty", as: "total"})
      assert "APPLY" in cmd
      assert "AS" in cmd
    end
  end

  describe "suggestions" do
    test "SUGADD" do
      assert Search.sugadd("ac:movies", "The Matrix", 1.0) ==
               ["FT.SUGADD", "ac:movies", "The Matrix", "1.0"]
    end

    test "SUGADD with INCR" do
      cmd = Search.sugadd("ac", "term", 1.0, incr: true)
      assert "INCR" in cmd
    end

    test "SUGGET" do
      assert Search.sugget("ac", "mat") == ["FT.SUGGET", "ac", "mat"]
    end

    test "SUGGET with options" do
      cmd = Search.sugget("ac", "mat", fuzzy: true, max: 5, withscores: true)
      assert "FUZZY" in cmd
      assert "MAX" in cmd
      assert "WITHSCORES" in cmd
    end

    test "SUGDEL" do
      assert Search.sugdel("ac", "term") == ["FT.SUGDEL", "ac", "term"]
    end

    test "SUGLEN" do
      assert Search.suglen("ac") == ["FT.SUGLEN", "ac"]
    end
  end

  describe "tag" do
    test "TAGVALS" do
      assert Search.tagvals("idx", "city") == ["FT.TAGVALS", "idx", "city"]
    end
  end
end

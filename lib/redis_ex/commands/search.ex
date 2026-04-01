defmodule RedisEx.Commands.Search do
  @moduledoc """
  Command builders for Redis Search (FT.*) operations (Redis 8+ / RediSearch).

  Includes a schema builder DSL for `FT.CREATE`.

  ## Usage

      # Create an index on JSON documents
      RedisEx.command(conn, Search.create("idx:users", :json,
        prefix: "user:",
        schema: [
          {"$.name", :text, as: "name"},
          {"$.age", :numeric, as: "age"},
          {"$.email", :tag, as: "email"}
        ]
      ))

      # Search
      RedisEx.command(conn, Search.search("idx:users", "@name:Alice"))

      # Aggregate
      RedisEx.command(conn, Search.aggregate("idx:users", "*",
        groupby: ["@age"],
        reduce: [{"COUNT", 0, as: "count"}]
      ))
  """

  # -------------------------------------------------------------------
  # Index Management
  # -------------------------------------------------------------------

  @doc """
  FT.CREATE — create a search index.

  ## Options

    * `:prefix` - key prefix(es) to index (string or list)
    * `:filter` - filter expression
    * `:language` - default language
    * `:score` - default score
    * `:stopwords` - list of stopwords (or 0 for none)
    * `:schema` - list of field definitions (required)

  ## Schema Fields

  Each field is a tuple: `{name_or_path, type}` or `{name_or_path, type, opts}`

  Types: `:text`, `:tag`, `:numeric`, `:geo`, `:vector`

  Field options:
    * `:as` - alias name
    * `:sortable` - enable sorting
    * `:noindex` - store but don't index
    * `:nostem` - disable stemming (text)
    * `:weight` - field weight (text)
    * `:separator` - tag separator (default ",")
  """
  @spec create(String.t(), :hash | :json, keyword()) :: [String.t()]
  def create(index, type \\ :hash, opts) do
    schema = Keyword.fetch!(opts, :schema)

    cmd = ["FT.CREATE", index, "ON", type_str(type)]
    cmd = cmd ++ prefix_args(Keyword.get(opts, :prefix))
    cmd = cmd ++ filter_args(Keyword.get(opts, :filter))
    cmd = cmd ++ language_args(Keyword.get(opts, :language))
    cmd = cmd ++ score_args(Keyword.get(opts, :score))
    cmd = cmd ++ stopwords_args(Keyword.get(opts, :stopwords))
    cmd ++ ["SCHEMA" | build_schema(schema)]
  end

  @doc "FT.DROPINDEX — drop an index."
  @spec dropindex(String.t(), keyword()) :: [String.t()]
  def dropindex(index, opts \\ []) do
    cmd = ["FT.DROPINDEX", index]
    if opts[:dd], do: cmd ++ ["DD"], else: cmd
  end

  @doc "FT.ALTER — add a field to an existing index."
  @spec alter(String.t(), {String.t(), atom()} | {String.t(), atom(), keyword()}) :: [String.t()]
  def alter(index, field_def) do
    ["FT.ALTER", index, "SCHEMA", "ADD" | build_field(field_def)]
  end

  @doc "FT.INFO — get index information."
  @spec info(String.t()) :: [String.t()]
  def info(index), do: ["FT.INFO", index]

  @doc "FT._LIST — list all indexes."
  @spec list() :: [String.t()]
  def list, do: ["FT._LIST"]

  # -------------------------------------------------------------------
  # Search & Query
  # -------------------------------------------------------------------

  @doc """
  FT.SEARCH — search an index.

  ## Options

    * `:return` - list of fields to return
    * `:limit` - `{offset, count}` (default: `{0, 10}`)
    * `:sortby` - `{field, :asc | :desc}`
    * `:nocontent` - return only IDs
    * `:verbatim` - don't expand query terms
    * `:params` - `[{name, value}]` for parameterized queries
    * `:dialect` - query dialect version
  """
  @spec search(String.t(), String.t(), keyword()) :: [String.t()]
  def search(index, query, opts \\ []) do
    cmd = ["FT.SEARCH", index, query]
    cmd = cmd ++ nocontent_args(opts[:nocontent])
    cmd = cmd ++ verbatim_args(opts[:verbatim])
    cmd = cmd ++ return_args(opts[:return])
    cmd = cmd ++ sortby_args(opts[:sortby])
    cmd = cmd ++ limit_args(opts[:limit])
    cmd = cmd ++ params_args(opts[:params])
    cmd = cmd ++ dialect_args(opts[:dialect])
    cmd
  end

  @doc """
  FT.AGGREGATE — run an aggregation query.

  ## Options

    * `:groupby` - list of fields to group by
    * `:reduce` - list of reduce functions `{func, nargs}` or `{func, nargs, as: alias}`
    * `:sortby` - `[{field, :asc | :desc}]`
    * `:limit` - `{offset, count}`
    * `:apply` - `{expression, as: alias}`
    * `:filter` - filter expression
    * `:params` - `[{name, value}]`
    * `:dialect` - query dialect version
  """
  @spec aggregate(String.t(), String.t(), keyword()) :: [String.t()]
  def aggregate(index, query, opts \\ []) do
    cmd = ["FT.AGGREGATE", index, query]
    cmd = cmd ++ groupby_args(opts[:groupby], opts[:reduce])
    cmd = cmd ++ agg_sortby_args(opts[:sortby])
    cmd = cmd ++ apply_args(opts[:apply])
    cmd = cmd ++ filter_arg(opts[:filter])
    cmd = cmd ++ limit_args(opts[:limit])
    cmd = cmd ++ params_args(opts[:params])
    cmd = cmd ++ dialect_args(opts[:dialect])
    cmd
  end

  # -------------------------------------------------------------------
  # Suggestions (auto-complete)
  # -------------------------------------------------------------------

  @doc "FT.SUGADD — add a suggestion string."
  @spec sugadd(String.t(), String.t(), float(), keyword()) :: [String.t()]
  def sugadd(key, string, score, opts \\ []) do
    cmd = ["FT.SUGADD", key, string, to_string(score)]
    cmd = if opts[:incr], do: cmd ++ ["INCR"], else: cmd
    cmd = if opts[:payload], do: cmd ++ ["PAYLOAD", opts[:payload]], else: cmd
    cmd
  end

  @doc "FT.SUGGET — get suggestion strings."
  @spec sugget(String.t(), String.t(), keyword()) :: [String.t()]
  def sugget(key, prefix, opts \\ []) do
    cmd = ["FT.SUGGET", key, prefix]
    cmd = if opts[:fuzzy], do: cmd ++ ["FUZZY"], else: cmd
    cmd = if opts[:max], do: cmd ++ ["MAX", to_string(opts[:max])], else: cmd
    cmd = if opts[:withscores], do: cmd ++ ["WITHSCORES"], else: cmd
    cmd = if opts[:withpayloads], do: cmd ++ ["WITHPAYLOADS"], else: cmd
    cmd
  end

  @doc "FT.SUGDEL — delete a suggestion."
  @spec sugdel(String.t(), String.t()) :: [String.t()]
  def sugdel(key, string), do: ["FT.SUGDEL", key, string]

  @doc "FT.SUGLEN — get number of suggestions."
  @spec suglen(String.t()) :: [String.t()]
  def suglen(key), do: ["FT.SUGLEN", key]

  # -------------------------------------------------------------------
  # Tag
  # -------------------------------------------------------------------

  @doc "FT.TAGVALS — get all distinct tag values for a field."
  @spec tagvals(String.t(), String.t()) :: [String.t()]
  def tagvals(index, field), do: ["FT.TAGVALS", index, field]

  # -------------------------------------------------------------------
  # Schema builder helpers
  # -------------------------------------------------------------------

  defp build_schema(fields), do: Enum.flat_map(fields, &build_field/1)

  defp build_field({name, type}) do
    [name, type_to_ft(type)]
  end

  defp build_field({name, type, opts}) do
    base = [name]
    base = if opts[:as], do: base ++ ["AS", opts[:as]], else: base
    base = base ++ [type_to_ft(type)]
    base = if opts[:sortable], do: base ++ ["SORTABLE"], else: base
    base = if opts[:noindex], do: base ++ ["NOINDEX"], else: base
    base = if opts[:nostem], do: base ++ ["NOSTEM"], else: base
    base = if opts[:weight], do: base ++ ["WEIGHT", to_string(opts[:weight])], else: base
    base = if opts[:separator], do: base ++ ["SEPARATOR", opts[:separator]], else: base
    base
  end

  defp type_to_ft(:text), do: "TEXT"
  defp type_to_ft(:tag), do: "TAG"
  defp type_to_ft(:numeric), do: "NUMERIC"
  defp type_to_ft(:geo), do: "GEO"
  defp type_to_ft(:vector), do: "VECTOR"
  defp type_to_ft(other) when is_binary(other), do: other

  defp type_str(:hash), do: "HASH"
  defp type_str(:json), do: "JSON"

  # -------------------------------------------------------------------
  # Argument builders
  # -------------------------------------------------------------------

  defp prefix_args(nil), do: []
  defp prefix_args(prefix) when is_binary(prefix), do: ["PREFIX", "1", prefix]
  defp prefix_args(prefixes) when is_list(prefixes), do: ["PREFIX", to_string(length(prefixes)) | prefixes]

  defp filter_args(nil), do: []
  defp filter_args(expr), do: ["FILTER", expr]

  defp language_args(nil), do: []
  defp language_args(lang), do: ["LANGUAGE", lang]

  defp score_args(nil), do: []
  defp score_args(score), do: ["SCORE", to_string(score)]

  defp stopwords_args(nil), do: []
  defp stopwords_args(0), do: ["STOPWORDS", "0"]
  defp stopwords_args(words) when is_list(words), do: ["STOPWORDS", to_string(length(words)) | words]

  defp nocontent_args(true), do: ["NOCONTENT"]
  defp nocontent_args(_), do: []

  defp verbatim_args(true), do: ["VERBATIM"]
  defp verbatim_args(_), do: []

  defp return_args(nil), do: []
  defp return_args(fields) when is_list(fields), do: ["RETURN", to_string(length(fields)) | fields]

  defp sortby_args(nil), do: []
  defp sortby_args({field, dir}), do: ["SORTBY", field, dir_str(dir)]

  defp limit_args(nil), do: []
  defp limit_args({offset, count}), do: ["LIMIT", to_string(offset), to_string(count)]

  defp params_args(nil), do: []
  defp params_args(params) when is_list(params) do
    flat = Enum.flat_map(params, fn {name, value} -> [to_string(name), to_string(value)] end)
    ["PARAMS", to_string(length(params) * 2) | flat]
  end

  defp dialect_args(nil), do: []
  defp dialect_args(v), do: ["DIALECT", to_string(v)]

  defp groupby_args(nil, _), do: []
  defp groupby_args(fields, reduces) when is_list(fields) do
    gb = ["GROUPBY", to_string(length(fields)) | fields]
    rb = Enum.flat_map(reduces || [], &reduce_arg/1)
    gb ++ rb
  end

  defp reduce_arg({func, nargs}) do
    ["REDUCE", func, to_string(nargs)]
  end

  defp reduce_arg({func, nargs, opts}) do
    cmd = ["REDUCE", func, to_string(nargs)]
    if opts[:as], do: cmd ++ ["AS", opts[:as]], else: cmd
  end

  defp agg_sortby_args(nil), do: []
  defp agg_sortby_args(fields) when is_list(fields) do
    flat = Enum.flat_map(fields, fn {field, dir} -> [field, dir_str(dir)] end)
    ["SORTBY", to_string(length(flat)) | flat]
  end

  defp apply_args(nil), do: []
  defp apply_args({expr, opts}), do: ["APPLY", expr, "AS", opts[:as]]

  defp filter_arg(nil), do: []
  defp filter_arg(expr), do: ["FILTER", expr]

  defp dir_str(:asc), do: "ASC"
  defp dir_str(:desc), do: "DESC"
end

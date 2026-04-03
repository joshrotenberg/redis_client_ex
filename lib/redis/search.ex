defmodule Redis.Search do
  @moduledoc """
  High-level search API for Redis, inspired by Meilisearch.

  Wraps the RediSearch `FT.*` commands with an Elixir-friendly interface:
  keyword-based schemas, map-based documents, Elixir filter expressions
  instead of raw query strings, and parsed result structs.

  For raw command access, see `Redis.Commands.Search`.

  ## Quick Start

      # Create an index
      Redis.Search.create_index(conn, "movies",
        prefix: "movie:",
        fields: [
          title: :text,
          year: {:numeric, sortable: true},
          genres: :tag
        ]
      )

      # Add documents as maps
      Redis.Search.add(conn, "movies", "movie:1", %{
        title: "The Dark Knight",
        year: 2008,
        genres: "action,thriller"
      })

      # Search with Elixir filters
      Redis.Search.find(conn, "movies", "dark knight",
        where: [year: {:gt, 2000}, genres: "action"],
        sort: {:year, :desc},
        limit: 10
      )
      #=> {:ok, %Redis.Search.Result{total: 1, results: [%{id: "movie:1", ...}]}}

  ## Filter Syntax

  The `:where` option accepts a keyword list compiled to RediSearch query syntax:

    * `field: "value"` -- text match (`@field:value`)
    * `field: {:match, "hello world"}` -- phrase match (`@field:(hello world)`)
    * `field: {:gt, n}` -- greater than (`@field:[(n +inf]`)
    * `field: {:gte, n}` -- greater than or equal (`@field:[n +inf]`)
    * `field: {:lt, n}` -- less than (`@field:[-inf (n]`)
    * `field: {:lte, n}` -- less than or equal (`@field:[-inf n]`)
    * `field: {:between, min, max}` -- range (`@field:[min max]`)
    * `field: {:tag, "val"}` -- exact tag (`@field:{val}`)
    * `field: {:any, ["a", "b"]}` -- tag OR (`@field:{a|b}`)

  ## Options

    * `:where` -- filter keyword list (see above)
    * `:sort` -- `{field, :asc | :desc}`
    * `:limit` -- max results (integer) or `{offset, count}`
    * `:return` -- list of fields to return
    * `:nocontent` -- return only IDs (boolean)
    * `:dialect` -- RediSearch query dialect version
    * `:coerce` -- auto-coerce numeric strings (default: true)
  """

  alias Redis.Commands.Search, as: Cmd
  alias Redis.Connection

  defmodule Result do
    @moduledoc """
    Parsed search or aggregation result.

    Fields:
      * `:total` -- total number of matching documents
      * `:results` -- list of result maps with `:id` and field data
    """
    defstruct total: 0, results: []

    @type t :: %__MODULE__{
            total: non_neg_integer(),
            results: [map()]
          }
  end

  # -------------------------------------------------------------------
  # Index Management
  # -------------------------------------------------------------------

  @doc """
  Creates a search index.

  Fields are specified as a keyword list:

      Redis.Search.create_index(conn, "idx", fields: [name: :text, age: :numeric])
      Redis.Search.create_index(conn, "idx",
        on: :json,
        prefix: "doc:",
        fields: [
          title: :text,
          score: {:numeric, sortable: true},
          tags: :tag
        ]
      )

  ## Options

    * `:fields` (required) -- keyword list of `{name, type}` or `{name, {type, opts...}}`
    * `:on` -- `:hash` (default) or `:json`
    * `:prefix` -- key prefix string or list
    * `:stopwords` -- list of stopwords or `0` for none
    * `:language` -- default language
  """
  def create_index(conn, index, opts) do
    type = Keyword.get(opts, :on, :hash)
    fields = Keyword.fetch!(opts, :fields)

    schema = build_schema(fields, type)

    cmd_opts =
      opts
      |> Keyword.drop([:fields, :on])
      |> Keyword.put(:schema, schema)

    case Connection.command(conn, Cmd.create(index, type, cmd_opts)) do
      {:ok, "OK"} -> :ok
      {:error, _} = err -> err
    end
  end

  @doc "Drops a search index. Pass `dd: true` to also delete indexed documents."
  def drop_index(conn, index, opts \\ []) do
    case Connection.command(conn, Cmd.dropindex(index, opts)) do
      {:ok, "OK"} -> :ok
      {:error, _} = err -> err
    end
  end

  @doc "Returns index info as a map."
  def index_info(conn, index) do
    Connection.command(conn, Cmd.info(index))
  end

  # -------------------------------------------------------------------
  # Document Ingestion
  # -------------------------------------------------------------------

  @doc """
  Adds a document to an index.

  Auto-detects hash vs JSON based on the index type. Pass `:on` to
  override if the index hasn't been inspected yet.

      Redis.Search.add(conn, "movies", "movie:1", %{
        title: "Inception",
        year: 2010,
        genres: "sci-fi,thriller"
      })
  """
  def add(conn, _index, key, doc, opts \\ []) when is_map(doc) do
    type = Keyword.get(opts, :on, :hash)

    case type do
      :json ->
        json = Jason.encode!(doc)
        Connection.command(conn, ["JSON.SET", key, "$", json])

      :hash ->
        fields = Enum.flat_map(doc, fn {k, v} -> [to_string(k), to_string(v)] end)
        Connection.command(conn, ["HSET", key | fields])
    end
  end

  @doc """
  Adds multiple documents via pipeline.

      Redis.Search.add_many(conn, "movies", [
        {"movie:1", %{title: "Inception", year: 2010}},
        {"movie:2", %{title: "Interstellar", year: 2014}}
      ])
  """
  def add_many(conn, _index, docs, opts \\ []) when is_list(docs) do
    type = Keyword.get(opts, :on, :hash)

    commands =
      Enum.map(docs, fn {key, doc} ->
        case type do
          :json ->
            ["JSON.SET", key, "$", Jason.encode!(doc)]

          :hash ->
            fields = Enum.flat_map(doc, fn {k, v} -> [to_string(k), to_string(v)] end)
            ["HSET", key | fields]
        end
      end)

    Connection.pipeline(conn, commands)
  end

  # -------------------------------------------------------------------
  # Search
  # -------------------------------------------------------------------

  @doc """
  Searches an index with Elixir-friendly filters.

      # Simple full-text search
      Redis.Search.find(conn, "movies", "dark knight")

      # With filters
      Redis.Search.find(conn, "movies", "batman",
        where: [year: {:gt, 2000}, genres: {:tag, "action"}],
        sort: {:year, :desc},
        limit: 10,
        return: [:title, :year]
      )

  See module docs for the full filter syntax.
  """
  def find(conn, index, query \\ "*", opts \\ []) do
    {where, opts} = Keyword.pop(opts, :where, [])
    {coerce, opts} = Keyword.pop(opts, :coerce, true)

    full_query = build_query(query, where)
    cmd_opts = translate_search_opts(opts)

    case Connection.command(conn, Cmd.search(index, full_query, cmd_opts)) do
      {:ok, raw} -> {:ok, parse_search_result(raw, coerce)}
      {:error, _} = err -> err
    end
  end

  # -------------------------------------------------------------------
  # Aggregation
  # -------------------------------------------------------------------

  @doc """
  Runs an aggregation query.

      Redis.Search.aggregate(conn, "movies",
        group_by: :genres,
        reduce: [count: "total"],
        sort: {:total, :desc},
        limit: 10
      )

      # Multiple reducers
      Redis.Search.aggregate(conn, "movies",
        group_by: [:city],
        reduce: [
          count: "total",
          avg: {:score, "avg_score"}
        ]
      )

  ## Reducers

    * `count: "alias"` -- COUNT
    * `sum: {:field, "alias"}` -- SUM
    * `avg: {:field, "alias"}` -- AVG
    * `min: {:field, "alias"}` -- MIN
    * `max: {:field, "alias"}` -- MAX
  """
  def aggregate(conn, index, opts \\ []) do
    {where, opts} = Keyword.pop(opts, :where, [])
    {group_by, opts} = Keyword.pop(opts, :group_by)
    {reduce, opts} = Keyword.pop(opts, :reduce, [])
    {sort, opts} = Keyword.pop(opts, :sort)
    {limit, opts} = Keyword.pop(opts, :limit)
    {coerce, opts} = Keyword.pop(opts, :coerce, true)
    {dialect, _opts} = Keyword.pop(opts, :dialect)

    query = build_query("*", where)

    cmd_opts =
      []
      |> maybe_add_groupby(group_by, reduce)
      |> maybe_add_agg_sort(sort)
      |> maybe_add_limit(limit)
      |> maybe_add_dialect(dialect)

    case Connection.command(conn, Cmd.aggregate(index, query, cmd_opts)) do
      {:ok, raw} -> {:ok, parse_aggregate_result(raw, coerce)}
      {:error, _} = err -> err
    end
  end

  # -------------------------------------------------------------------
  # Query Builder
  # -------------------------------------------------------------------

  defp build_query(base, []), do: base

  defp build_query(base, filters) do
    filter_str = Enum.map_join(filters, " ", &compile_filter/1)

    case base do
      "*" -> filter_str
      _ -> "#{base} #{filter_str}"
    end
  end

  defp compile_filter({field, value}) when is_binary(value) do
    "@#{field}:#{value}"
  end

  defp compile_filter({field, {:match, phrase}}) do
    "@#{field}:(#{phrase})"
  end

  defp compile_filter({field, {:gt, n}}) do
    "@#{field}:[(#{n} +inf]"
  end

  defp compile_filter({field, {:gte, n}}) do
    "@#{field}:[#{n} +inf]"
  end

  defp compile_filter({field, {:lt, n}}) do
    "@#{field}:[-inf (#{n}]"
  end

  defp compile_filter({field, {:lte, n}}) do
    "@#{field}:[-inf #{n}]"
  end

  defp compile_filter({field, {:between, min, max}}) do
    "@#{field}:[#{min} #{max}]"
  end

  defp compile_filter({field, {:tag, value}}) when is_binary(value) do
    "@#{field}:{#{value}}"
  end

  defp compile_filter({field, {:any, values}}) when is_list(values) do
    joined = Enum.join(values, "|")
    "@#{field}:{#{joined}}"
  end

  # -------------------------------------------------------------------
  # Schema Builder
  # -------------------------------------------------------------------

  defp build_schema(fields, type) do
    Enum.map(fields, fn {name, type_spec} ->
      {field_name, field_type, field_opts} = parse_field_spec(name, type_spec, type)
      build_field_tuple(field_name, field_type, field_opts)
    end)
  end

  defp parse_field_spec(name, type, index_type) when is_atom(type) do
    field_name = field_path(name, index_type)
    {field_name, type, []}
  end

  defp parse_field_spec(name, {type, opts}, index_type) when is_atom(type) and is_list(opts) do
    field_name = field_path(name, index_type)
    {field_name, type, opts}
  end

  defp parse_field_spec(name, {type, single_opt}, index_type)
       when is_atom(type) and is_atom(single_opt) do
    field_name = field_path(name, index_type)
    {field_name, type, [{single_opt, true}]}
  end

  defp field_path(name, :json), do: "$.#{name}"
  defp field_path(name, :hash), do: to_string(name)

  defp build_field_tuple(field_name, field_type, []) do
    {field_name, field_type}
  end

  defp build_field_tuple(field_name, field_type, opts) do
    # For JSON fields, add an AS alias using the bare field name
    opts =
      if String.starts_with?(field_name, "$.") and not Keyword.has_key?(opts, :as) do
        bare = String.trim_leading(field_name, "$.")
        Keyword.put(opts, :as, bare)
      else
        opts
      end

    {field_name, field_type, opts}
  end

  # -------------------------------------------------------------------
  # Search Option Translation
  # -------------------------------------------------------------------

  defp translate_search_opts(opts) do
    Enum.flat_map(opts, fn
      {:sort, {field, dir}} -> [sortby: {to_string(field), dir}]
      {:limit, n} when is_integer(n) -> [limit: {0, n}]
      {:limit, {offset, count}} -> [limit: {offset, count}]
      {:return, fields} -> [return: Enum.map(fields, &to_string/1)]
      {:nocontent, val} -> [nocontent: val]
      {:dialect, val} -> [dialect: val]
      _ -> []
    end)
  end

  # -------------------------------------------------------------------
  # Aggregation Helpers
  # -------------------------------------------------------------------

  defp maybe_add_groupby(opts, nil, _), do: opts

  defp maybe_add_groupby(opts, field, reduce) when is_atom(field) do
    maybe_add_groupby(opts, [field], reduce)
  end

  defp maybe_add_groupby(opts, fields, reduce) when is_list(fields) do
    groupby = Enum.map(fields, &"@#{&1}")
    reduces = Enum.map(reduce, &translate_reducer/1)
    Keyword.merge(opts, groupby: groupby, reduce: reduces)
  end

  defp translate_reducer({:count, alias_name}) do
    {"COUNT", 0, as: to_string(alias_name)}
  end

  defp translate_reducer({func, {field, alias_name}})
       when func in [:sum, :avg, :min, :max] do
    {func |> to_string() |> String.upcase(), 1, as: to_string(alias_name)}
    |> then(fn {f, n, opts} -> {f, n, Keyword.put(opts, :__field, "@#{field}")} end)
  end

  defp maybe_add_agg_sort(opts, nil), do: opts

  defp maybe_add_agg_sort(opts, {field, dir}) do
    Keyword.put(opts, :sortby, [{"@#{field}", dir}])
  end

  defp maybe_add_limit(opts, nil), do: opts
  defp maybe_add_limit(opts, n) when is_integer(n), do: Keyword.put(opts, :limit, {0, n})
  defp maybe_add_limit(opts, {o, c}), do: Keyword.put(opts, :limit, {o, c})

  defp maybe_add_dialect(opts, nil), do: opts
  defp maybe_add_dialect(opts, v), do: Keyword.put(opts, :dialect, v)

  # -------------------------------------------------------------------
  # Result Parsing
  # -------------------------------------------------------------------

  defp parse_search_result(raw, coerce) when is_map(raw) do
    # RESP3 format: %{"total_results" => n, "results" => [...]}
    total = Map.get(raw, "total_results", 0)

    results =
      raw
      |> Map.get("results", [])
      |> Enum.map(fn result ->
        id = Map.get(result, "id")

        fields =
          result
          |> Map.get("extra_attributes", %{})
          |> maybe_coerce(coerce)

        Map.put(fields, :id, id)
      end)

    %Result{total: total, results: results}
  end

  defp parse_search_result(raw, coerce) when is_list(raw) do
    # RESP2 format: [total, id, [field, val, ...], ...]
    case raw do
      [total | rest] ->
        results = parse_resp2_results(rest, coerce)
        %Result{total: total, results: results}

      _ ->
        %Result{}
    end
  end

  defp parse_search_result(_, _), do: %Result{}

  defp parse_resp2_results([], _), do: []

  defp parse_resp2_results([id, fields | rest], coerce) when is_list(fields) do
    field_map =
      fields
      |> Enum.chunk_every(2)
      |> Map.new(fn [k, v] -> {k, v} end)
      |> maybe_coerce(coerce)

    [Map.put(field_map, :id, id) | parse_resp2_results(rest, coerce)]
  end

  defp parse_resp2_results(_, _), do: []

  defp parse_aggregate_result(raw, coerce) when is_map(raw) do
    total = Map.get(raw, "total_results", 0)

    results =
      raw
      |> Map.get("results", [])
      |> Enum.map(fn result ->
        result
        |> Map.get("extra_attributes", %{})
        |> maybe_coerce(coerce)
      end)

    %Result{total: total, results: results}
  end

  defp parse_aggregate_result(raw, coerce) when is_list(raw) do
    case raw do
      [total | rest] ->
        results = parse_resp2_agg_results(rest, coerce)
        %Result{total: total, results: results}

      _ ->
        %Result{}
    end
  end

  defp parse_aggregate_result(_, _), do: %Result{}

  defp parse_resp2_agg_results([], _), do: []

  defp parse_resp2_agg_results([fields | rest], coerce) when is_list(fields) do
    field_map =
      fields
      |> Enum.chunk_every(2)
      |> Map.new(fn [k, v] -> {k, v} end)
      |> maybe_coerce(coerce)

    [field_map | parse_resp2_agg_results(rest, coerce)]
  end

  defp parse_resp2_agg_results(_, _), do: []

  # -------------------------------------------------------------------
  # Coercion
  # -------------------------------------------------------------------

  defp maybe_coerce(map, false), do: map

  defp maybe_coerce(map, true) do
    Map.new(map, fn {k, v} -> {k, coerce_value(v)} end)
  end

  defp coerce_value(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, ""} ->
        n

      _ ->
        case Float.parse(v) do
          {f, ""} -> f
          _ -> v
        end
    end
  end

  defp coerce_value(v), do: v
end

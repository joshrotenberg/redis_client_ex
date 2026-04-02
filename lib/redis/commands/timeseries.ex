defmodule Redis.Commands.TimeSeries do
  @moduledoc """
  Command builders for Redis TimeSeries (`TS.*`) operations.

  Redis TimeSeries is an append-only data structure optimized for storing
  timestamped numeric samples. It supports automatic downsampling via
  compaction rules, label-based indexing for multi-series queries, and
  built-in aggregation functions (avg, sum, min, max, count, etc.) over
  arbitrary time windows. Common use cases include metrics collection, IoT
  sensor data, financial tick data, and application monitoring.

  All functions in this module are pure and return a command list (a list of
  strings) suitable for passing to `Redis.command/2` or `Redis.pipeline/2`.

  ## Examples

      # Create a time series and add a sample
      Redis.pipeline(conn, [
        TimeSeries.ts_create("temp:office", labels: %{"location" => "office"}),
        TimeSeries.ts_add("temp:office", "*", 22.5)
      ])

      # Query a time range with 1-hour average aggregation
      Redis.command(conn, TimeSeries.ts_range("temp:office", "-", "+",
        aggregation: {:avg, 3_600_000}
      ))
  """

  @doc """
  Creates a new time series key. Accepts options including `:retention`
  (max age in milliseconds), `:labels` (a map or keyword list of label
  key-value pairs), `:encoding`, `:chunk_size`, and `:duplicate_policy`.
  """
  @spec ts_create(String.t(), keyword()) :: [String.t()]
  def ts_create(key, opts \\ []) do
    cmd = ["TS.CREATE", key]
    cmd = if opts[:retention], do: cmd ++ ["RETENTION", to_string(opts[:retention])], else: cmd
    cmd = if opts[:encoding], do: cmd ++ ["ENCODING", to_string(opts[:encoding])], else: cmd
    cmd = if opts[:chunk_size], do: cmd ++ ["CHUNK_SIZE", to_string(opts[:chunk_size])], else: cmd

    cmd =
      if opts[:duplicate_policy],
        do: cmd ++ ["DUPLICATE_POLICY", to_string(opts[:duplicate_policy])],
        else: cmd

    cmd = append_labels(cmd, opts[:labels])
    cmd
  end

  @spec ts_alter(String.t(), keyword()) :: [String.t()]
  def ts_alter(key, opts \\ []) do
    cmd = ["TS.ALTER", key]
    cmd = if opts[:retention], do: cmd ++ ["RETENTION", to_string(opts[:retention])], else: cmd
    cmd = if opts[:chunk_size], do: cmd ++ ["CHUNK_SIZE", to_string(opts[:chunk_size])], else: cmd

    cmd =
      if opts[:duplicate_policy],
        do: cmd ++ ["DUPLICATE_POLICY", to_string(opts[:duplicate_policy])],
        else: cmd

    cmd = append_labels(cmd, opts[:labels])
    cmd
  end

  @doc """
  Appends a sample to a time series. Use `"*"` as the timestamp to let Redis
  assign the current server time. Accepts the same label and retention options
  as `ts_create/2`, plus `:on_duplicate` for handling duplicate timestamps.
  """
  @spec ts_add(String.t(), String.t() | integer(), String.t() | number(), keyword()) :: [
          String.t()
        ]
  def ts_add(key, timestamp, value, opts \\ []) do
    cmd = ["TS.ADD", key, to_string(timestamp), to_string(value)]
    cmd = if opts[:retention], do: cmd ++ ["RETENTION", to_string(opts[:retention])], else: cmd
    cmd = if opts[:encoding], do: cmd ++ ["ENCODING", to_string(opts[:encoding])], else: cmd
    cmd = if opts[:chunk_size], do: cmd ++ ["CHUNK_SIZE", to_string(opts[:chunk_size])], else: cmd

    cmd =
      if opts[:on_duplicate],
        do: cmd ++ ["ON_DUPLICATE", to_string(opts[:on_duplicate])],
        else: cmd

    cmd = append_labels(cmd, opts[:labels])
    cmd
  end

  @spec ts_madd([{String.t(), String.t() | integer(), String.t() | number()}]) :: [String.t()]
  def ts_madd(entries) when is_list(entries) do
    [
      "TS.MADD"
      | Enum.flat_map(entries, fn {key, timestamp, value} ->
          [key, to_string(timestamp), to_string(value)]
        end)
    ]
  end

  @spec ts_incrby(String.t(), String.t() | number(), keyword()) :: [String.t()]
  def ts_incrby(key, value, opts \\ []) do
    cmd = ["TS.INCRBY", key, to_string(value)]
    cmd = if opts[:timestamp], do: cmd ++ ["TIMESTAMP", to_string(opts[:timestamp])], else: cmd
    cmd = if opts[:retention], do: cmd ++ ["RETENTION", to_string(opts[:retention])], else: cmd
    cmd = append_labels(cmd, opts[:labels])
    cmd
  end

  @spec ts_decrby(String.t(), String.t() | number(), keyword()) :: [String.t()]
  def ts_decrby(key, value, opts \\ []) do
    cmd = ["TS.DECRBY", key, to_string(value)]
    cmd = if opts[:timestamp], do: cmd ++ ["TIMESTAMP", to_string(opts[:timestamp])], else: cmd
    cmd = if opts[:retention], do: cmd ++ ["RETENTION", to_string(opts[:retention])], else: cmd
    cmd = append_labels(cmd, opts[:labels])
    cmd
  end

  @spec ts_del(String.t(), String.t() | integer(), String.t() | integer()) :: [String.t()]
  def ts_del(key, from_timestamp, to_timestamp) do
    ["TS.DEL", key, to_string(from_timestamp), to_string(to_timestamp)]
  end

  @spec ts_get(String.t(), keyword()) :: [String.t()]
  def ts_get(key, opts \\ []) do
    cmd = ["TS.GET", key]
    if opts[:latest], do: cmd ++ ["LATEST"], else: cmd
  end

  @spec ts_mget([String.t()], keyword()) :: [String.t()]
  def ts_mget(filters, opts \\ []) when is_list(filters) do
    cmd = ["TS.MGET"]
    cmd = if opts[:latest], do: cmd ++ ["LATEST"], else: cmd
    cmd = if opts[:withlabels], do: cmd ++ ["WITHLABELS"], else: cmd
    cmd ++ ["FILTER" | filters]
  end

  @doc """
  Queries samples in the time range `from..to` (inclusive). Use `"-"` and `"+"`
  for the minimum and maximum timestamps. Supports `:count`, `:aggregation`
  (e.g. `{:avg, 60_000}`), `:filter_by_ts`, and `:filter_by_value` options.
  """
  @spec ts_range(String.t(), String.t() | integer(), String.t() | integer(), keyword()) :: [
          String.t()
        ]
  def ts_range(key, from, to, opts \\ []) do
    cmd = ["TS.RANGE", key, to_string(from), to_string(to)]
    append_range_opts(cmd, opts)
  end

  @spec ts_revrange(String.t(), String.t() | integer(), String.t() | integer(), keyword()) :: [
          String.t()
        ]
  def ts_revrange(key, from, to, opts \\ []) do
    cmd = ["TS.REVRANGE", key, to_string(from), to_string(to)]
    append_range_opts(cmd, opts)
  end

  @spec ts_mrange(String.t() | integer(), String.t() | integer(), [String.t()], keyword()) :: [
          String.t()
        ]
  def ts_mrange(from, to, filters, opts \\ []) when is_list(filters) do
    cmd = ["TS.MRANGE", to_string(from), to_string(to)]
    cmd = append_mrange_opts(cmd, opts)
    cmd ++ ["FILTER" | filters]
  end

  @spec ts_mrevrange(String.t() | integer(), String.t() | integer(), [String.t()], keyword()) :: [
          String.t()
        ]
  def ts_mrevrange(from, to, filters, opts \\ []) when is_list(filters) do
    cmd = ["TS.MREVRANGE", to_string(from), to_string(to)]
    cmd = append_mrange_opts(cmd, opts)
    cmd ++ ["FILTER" | filters]
  end

  @spec ts_queryindex([String.t()]) :: [String.t()]
  def ts_queryindex(filters) when is_list(filters) do
    ["TS.QUERYINDEX" | filters]
  end

  @spec ts_info(String.t(), keyword()) :: [String.t()]
  def ts_info(key, opts \\ []) do
    cmd = ["TS.INFO", key]
    if opts[:debug], do: cmd ++ ["DEBUG"], else: cmd
  end

  # -- Private helpers -------------------------------------------------------

  defp append_labels(cmd, nil), do: cmd

  defp append_labels(cmd, labels) when is_map(labels) do
    cmd ++ ["LABELS" | Enum.flat_map(labels, fn {k, v} -> [to_string(k), to_string(v)] end)]
  end

  defp append_labels(cmd, labels) when is_list(labels) do
    cmd ++ ["LABELS" | Enum.flat_map(labels, fn {k, v} -> [to_string(k), to_string(v)] end)]
  end

  defp append_range_opts(cmd, opts) do
    cmd = if opts[:latest], do: cmd ++ ["LATEST"], else: cmd

    cmd =
      if opts[:filter_by_ts],
        do: cmd ++ ["FILTER_BY_TS" | Enum.map(opts[:filter_by_ts], &to_string/1)],
        else: cmd

    cmd =
      if opts[:filter_by_value],
        do:
          cmd ++
            [
              "FILTER_BY_VALUE",
              to_string(elem(opts[:filter_by_value], 0)),
              to_string(elem(opts[:filter_by_value], 1))
            ],
        else: cmd

    cmd = if opts[:count], do: cmd ++ ["COUNT", to_string(opts[:count])], else: cmd

    cmd =
      if opts[:aggregation],
        do:
          cmd ++
            [
              "AGGREGATION",
              to_string(elem(opts[:aggregation], 0)),
              to_string(elem(opts[:aggregation], 1))
            ],
        else: cmd

    cmd
  end

  defp append_mrange_opts(cmd, opts) do
    cmd = if opts[:latest], do: cmd ++ ["LATEST"], else: cmd
    cmd = if opts[:withlabels], do: cmd ++ ["WITHLABELS"], else: cmd

    cmd =
      if opts[:filter_by_ts],
        do: cmd ++ ["FILTER_BY_TS" | Enum.map(opts[:filter_by_ts], &to_string/1)],
        else: cmd

    cmd =
      if opts[:filter_by_value],
        do:
          cmd ++
            [
              "FILTER_BY_VALUE",
              to_string(elem(opts[:filter_by_value], 0)),
              to_string(elem(opts[:filter_by_value], 1))
            ],
        else: cmd

    cmd = if opts[:count], do: cmd ++ ["COUNT", to_string(opts[:count])], else: cmd

    cmd =
      if opts[:aggregation],
        do:
          cmd ++
            [
              "AGGREGATION",
              to_string(elem(opts[:aggregation], 0)),
              to_string(elem(opts[:aggregation], 1))
            ],
        else: cmd

    cmd
  end
end

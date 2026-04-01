defmodule Redis.Commands.JSON do
  @moduledoc """
  Command builders for Redis JSON operations (Redis 8+ / RedisJSON).

  All path arguments default to `"$"` (root). Values are automatically
  encoded to JSON strings via `JSON.encode!/1`.

  ## Usage

      # Raw command building
      Redis.Commands.JSON.set("user:1", %{name: "Alice", age: 30})
      #=> ["JSON.SET", "user:1", "$", ~s({"name":"Alice","age":30})]

      # With connection
      Redis.command(conn, JSON.set("doc", %{x: 1}))
      Redis.command(conn, JSON.get("doc"))
  """

  @root "$"

  # -------------------------------------------------------------------
  # Core
  # -------------------------------------------------------------------

  @doc """
  JSON.SET — set a JSON value at a path.

  Value is auto-encoded to JSON. Pass a raw JSON string with `raw: true`.

      JSON.set("key", %{a: 1})
      JSON.set("key", %{a: 1}, path: "$.nested")
      JSON.set("key", ~s({"a":1}), raw: true)
      JSON.set("key", %{a: 1}, nx: true)   # only set if doesn't exist
      JSON.set("key", %{a: 1}, xx: true)   # only set if exists
  """
  @spec set(String.t(), term(), keyword()) :: [String.t()]
  def set(key, value, opts \\ []) do
    path = Keyword.get(opts, :path, @root)
    json = encode_value(value, opts)
    cmd = ["JSON.SET", key, path, json]
    cmd = if opts[:nx], do: cmd ++ ["NX"], else: cmd
    cmd = if opts[:xx], do: cmd ++ ["XX"], else: cmd
    cmd
  end

  @doc """
  JSON.GET — get JSON value(s) at one or more paths.

      JSON.get("key")
      JSON.get("key", paths: ["$.name", "$.age"])
  """
  @spec get(String.t(), keyword()) :: [String.t()]
  def get(key, opts \\ []) do
    paths = Keyword.get(opts, :paths, [@root])
    ["JSON.GET", key | List.wrap(paths)]
  end

  @doc "JSON.MGET — get a path from multiple keys."
  @spec mget([String.t()], String.t()) :: [String.t()]
  def mget(keys, path \\ @root) when is_list(keys) do
    ["JSON.MGET" | keys] ++ [path]
  end

  @doc "JSON.DEL — delete a path from a key."
  @spec del(String.t(), String.t()) :: [String.t()]
  def del(key, path \\ @root), do: ["JSON.DEL", key, path]

  @doc "JSON.TYPE — get the JSON type at a path."
  @spec type(String.t(), String.t()) :: [String.t()]
  def type(key, path \\ @root), do: ["JSON.TYPE", key, path]

  @doc "JSON.CLEAR — clear arrays/objects at a path (set to empty)."
  @spec clear(String.t(), String.t()) :: [String.t()]
  def clear(key, path \\ @root), do: ["JSON.CLEAR", key, path]

  @doc "JSON.TOGGLE — toggle boolean at a path."
  @spec toggle(String.t(), String.t()) :: [String.t()]
  def toggle(key, path \\ @root), do: ["JSON.TOGGLE", key, path]

  @doc "JSON.STRLEN — get string length at a path."
  @spec strlen(String.t(), String.t()) :: [String.t()]
  def strlen(key, path \\ @root), do: ["JSON.STRLEN", key, path]

  @doc "JSON.STRAPPEND — append to a string at a path."
  @spec strappend(String.t(), String.t(), String.t()) :: [String.t()]
  def strappend(key, value, path \\ @root) do
    ["JSON.STRAPPEND", key, path, JSON.encode!(value)]
  end

  # -------------------------------------------------------------------
  # Numeric
  # -------------------------------------------------------------------

  @doc "JSON.NUMINCRBY — increment a number at a path."
  @spec numincrby(String.t(), number(), String.t()) :: [String.t()]
  def numincrby(key, amount, path \\ @root) do
    ["JSON.NUMINCRBY", key, path, to_string(amount)]
  end

  @doc "JSON.NUMMULTBY — multiply a number at a path."
  @spec nummultby(String.t(), number(), String.t()) :: [String.t()]
  def nummultby(key, amount, path \\ @root) do
    ["JSON.NUMMULTBY", key, path, to_string(amount)]
  end

  # -------------------------------------------------------------------
  # Array
  # -------------------------------------------------------------------

  @doc "JSON.ARRAPPEND — append values to an array."
  @spec arrappend(String.t(), [term()], String.t()) :: [String.t()]
  def arrappend(key, values, path \\ @root) when is_list(values) do
    encoded = Enum.map(values, &JSON.encode!/1)
    ["JSON.ARRAPPEND", key, path | encoded]
  end

  @doc "JSON.ARRINSERT — insert values at an index."
  @spec arrinsert(String.t(), non_neg_integer(), [term()], String.t()) :: [String.t()]
  def arrinsert(key, index, values, path \\ @root) when is_list(values) do
    encoded = Enum.map(values, &JSON.encode!/1)
    ["JSON.ARRINSERT", key, path, to_string(index) | encoded]
  end

  @doc "JSON.ARRLEN — get array length."
  @spec arrlen(String.t(), String.t()) :: [String.t()]
  def arrlen(key, path \\ @root), do: ["JSON.ARRLEN", key, path]

  @doc "JSON.ARRPOP — pop from an array (default: last element)."
  @spec arrpop(String.t(), String.t(), integer()) :: [String.t()]
  def arrpop(key, path \\ @root, index \\ -1) do
    ["JSON.ARRPOP", key, path, to_string(index)]
  end

  @doc "JSON.ARRTRIM — trim an array to [start, stop]."
  @spec arrtrim(String.t(), non_neg_integer(), integer(), String.t()) :: [String.t()]
  def arrtrim(key, start, stop, path \\ @root) do
    ["JSON.ARRTRIM", key, path, to_string(start), to_string(stop)]
  end

  @doc "JSON.ARRINDEX — find index of a value in an array."
  @spec arrindex(String.t(), term(), String.t()) :: [String.t()]
  def arrindex(key, value, path \\ @root) do
    ["JSON.ARRINDEX", key, path, JSON.encode!(value)]
  end

  # -------------------------------------------------------------------
  # Object
  # -------------------------------------------------------------------

  @doc "JSON.OBJKEYS — get object keys at a path."
  @spec objkeys(String.t(), String.t()) :: [String.t()]
  def objkeys(key, path \\ @root), do: ["JSON.OBJKEYS", key, path]

  @doc "JSON.OBJLEN — get number of keys in an object."
  @spec objlen(String.t(), String.t()) :: [String.t()]
  def objlen(key, path \\ @root), do: ["JSON.OBJLEN", key, path]

  # -------------------------------------------------------------------
  # Merge
  # -------------------------------------------------------------------

  @doc "JSON.MERGE — merge a JSON value into an existing key."
  @spec merge(String.t(), term(), keyword()) :: [String.t()]
  def merge(key, value, opts \\ []) do
    path = Keyword.get(opts, :path, @root)
    json = encode_value(value, opts)
    ["JSON.MERGE", key, path, json]
  end

  # -------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------

  defp encode_value(value, opts) do
    if Keyword.get(opts, :raw, false) do
      value
    else
      JSON.encode!(value)
    end
  end
end

defmodule Redis.JSON do
  @moduledoc """
  High-level document API for RedisJSON.

  Wraps the RedisJSON commands with an Elixir-friendly interface: maps in,
  maps out, atom or list path syntax instead of JSONPath strings, and
  automatic JSON encoding/decoding.

  For raw command access, see `Redis.Commands.JSON`.

  ## Quick Start

      # Store a document
      {:ok, "OK"} = Redis.JSON.set(conn, "user:1", %{name: "Alice", age: 30})

      # Get it back as an Elixir map
      {:ok, %{"name" => "Alice", "age" => 30}} = Redis.JSON.get(conn, "user:1")

      # Get specific fields
      {:ok, %{"name" => "Alice"}} = Redis.JSON.get(conn, "user:1", fields: [:name])

      # Update a nested field
      {:ok, "OK"} = Redis.JSON.put(conn, "user:1", :status, "online")

      # Merge fields (like PATCH)
      {:ok, "OK"} = Redis.JSON.merge(conn, "user:1", %{status: "offline", last_seen: "2026-04-03"})

      # Atomic increment
      {:ok, 31} = Redis.JSON.incr(conn, "user:1", :age, 1)

      # Array operations
      {:ok, 3} = Redis.JSON.append(conn, "user:1", :tags, "admin")
      {:ok, "admin"} = Redis.JSON.pop(conn, "user:1", :tags)

  ## Path Syntax

  Paths can be atoms, lists, or raw JSONPath strings:

    * `:name` -> `$.name`
    * `[:address, :city]` -> `$.address.city`
    * `"$.users[0].name"` -> passed through as-is

  ## Options

  Most functions accept:

    * `:atom_keys` -- return map keys as atoms (default: `false`)
  """

  alias Redis.Commands.JSON, as: Cmd
  alias Redis.Connection

  # -------------------------------------------------------------------
  # CRUD
  # -------------------------------------------------------------------

  @doc """
  Stores a JSON document.

      Redis.JSON.set(conn, "user:1", %{name: "Alice", age: 30})
      Redis.JSON.set(conn, "user:1", %{name: "Alice"}, nx: true)  # only if new
      Redis.JSON.set(conn, "user:1", %{name: "Alice"}, xx: true)  # only if exists
  """
  def set(conn, key, value, opts \\ []) do
    Connection.command(conn, Cmd.set(key, value, opts))
  end

  @doc """
  Gets a JSON document or specific fields.

      {:ok, %{"name" => "Alice", "age" => 30}} = Redis.JSON.get(conn, "user:1")
      {:ok, %{"name" => "Alice"}} = Redis.JSON.get(conn, "user:1", fields: [:name])

  Returns the document as a decoded Elixir map. JSONPath array wrapping
  is automatically unwrapped for root-level gets.
  """
  def get(conn, key, opts \\ []) do
    {fields, opts} = Keyword.pop(opts, :fields)
    {atom_keys, _opts} = Keyword.pop(opts, :atom_keys, false)

    cmd_opts =
      if fields do
        [paths: Enum.map(fields, &to_path/1)]
      else
        []
      end

    case Connection.command(conn, Cmd.get(key, cmd_opts)) do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, json} when is_binary(json) ->
        decoded = Jason.decode!(json)
        {:ok, unwrap_result(decoded, fields, atom_keys)}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Gets a field from multiple keys.

      {:ok, ["Alice", "Bob"]} = Redis.JSON.mget(conn, ["user:1", "user:2"], :name)
  """
  def mget(conn, keys, field, opts \\ []) do
    {atom_keys, _opts} = Keyword.pop(opts, :atom_keys, false)
    path = to_path(field)

    case Connection.command(conn, Cmd.mget(keys, path)) do
      {:ok, results} when is_list(results) ->
        decoded =
          Enum.map(results, fn
            nil -> nil
            json when is_binary(json) -> json |> Jason.decode!() |> unwrap_scalar(atom_keys)
            other -> other
          end)

        {:ok, decoded}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Deletes a document or a path within it.

      {:ok, 1} = Redis.JSON.del(conn, "user:1")
      {:ok, 1} = Redis.JSON.del(conn, "user:1", :temporary_field)
  """
  def del(conn, key, path \\ nil) do
    cmd =
      if path do
        Cmd.del(key, to_path(path))
      else
        Cmd.del(key)
      end

    Connection.command(conn, cmd)
  end

  @doc """
  Returns the JSON type at a path.

      {:ok, :object} = Redis.JSON.type(conn, "user:1")
      {:ok, :array} = Redis.JSON.type(conn, "user:1", :tags)
  """
  def type(conn, key, path \\ nil) do
    cmd =
      if path do
        Cmd.type(key, to_path(path))
      else
        Cmd.type(key)
      end

    case Connection.command(conn, cmd) do
      {:ok, result} -> {:ok, parse_type(result)}
      {:error, _} = err -> err
    end
  end

  @doc """
  Checks if a key exists as a JSON document.

      true = Redis.JSON.exists?(conn, "user:1")
  """
  def exists?(conn, key) do
    case Connection.command(conn, Cmd.type(key)) do
      {:ok, nil} -> false
      {:ok, [nil]} -> false
      {:ok, [[nil]]} -> false
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  # -------------------------------------------------------------------
  # Nested Updates
  # -------------------------------------------------------------------

  @doc """
  Sets a value at a specific path.

      Redis.JSON.put(conn, "user:1", :status, "online")
      Redis.JSON.put(conn, "user:1", [:address, :city], "NYC")
  """
  def put(conn, key, path, value) do
    Connection.command(conn, Cmd.set(key, value, path: to_path(path)))
  end

  @doc """
  Merges fields into a document (like HTTP PATCH).

      Redis.JSON.merge(conn, "user:1", %{status: "online", last_seen: "2026-04-03"})
  """
  def merge(conn, key, value, opts \\ []) do
    Connection.command(conn, Cmd.merge(key, value, opts))
  end

  # -------------------------------------------------------------------
  # Atomic Operations
  # -------------------------------------------------------------------

  @doc """
  Atomically increments a number at a path.

      {:ok, 31} = Redis.JSON.incr(conn, "user:1", :age, 1)
      {:ok, 10.5} = Redis.JSON.incr(conn, "user:1", :score, 0.5)
  """
  def incr(conn, key, path, amount) do
    case Connection.command(conn, Cmd.numincrby(key, amount, to_path(path))) do
      {:ok, result} -> {:ok, unwrap_numeric(result)}
      {:error, _} = err -> err
    end
  end

  @doc """
  Toggles a boolean at a path.

      {:ok, false} = Redis.JSON.toggle(conn, "user:1", :active)
  """
  def toggle(conn, key, path) do
    case Connection.command(conn, Cmd.toggle(key, to_path(path))) do
      {:ok, [val]} -> {:ok, val}
      {:ok, val} -> {:ok, val}
      {:error, _} = err -> err
    end
  end

  # -------------------------------------------------------------------
  # Array Operations
  # -------------------------------------------------------------------

  @doc """
  Appends one or more values to an array.

      {:ok, 3} = Redis.JSON.append(conn, "user:1", :tags, "admin")
      {:ok, 5} = Redis.JSON.append(conn, "user:1", :tags, ["editor", "reviewer"])
  """
  def append(conn, key, path, values) do
    values = List.wrap(values)

    case Connection.command(conn, Cmd.arrappend(key, values, to_path(path))) do
      {:ok, [len]} -> {:ok, len}
      {:ok, len} -> {:ok, len}
      {:error, _} = err -> err
    end
  end

  @doc """
  Pops the last element from an array.

      {:ok, "hiking"} = Redis.JSON.pop(conn, "user:1", :tags)
  """
  def pop(conn, key, path) do
    case Connection.command(conn, Cmd.arrpop(key, to_path(path))) do
      {:ok, [val]} when is_binary(val) -> {:ok, safe_decode(val)}
      {:ok, val} when is_binary(val) -> {:ok, safe_decode(val)}
      {:ok, other} -> {:ok, other}
      {:error, _} = err -> err
    end
  end

  @doc """
  Returns the length of an array.

      {:ok, 3} = Redis.JSON.length(conn, "user:1", :tags)
  """
  def length(conn, key, path) do
    case Connection.command(conn, Cmd.arrlen(key, to_path(path))) do
      {:ok, [len]} -> {:ok, len}
      {:ok, len} -> {:ok, len}
      {:error, _} = err -> err
    end
  end

  # -------------------------------------------------------------------
  # Path Building
  # -------------------------------------------------------------------

  defp to_path(nil), do: "$"
  defp to_path(path) when is_binary(path), do: path

  defp to_path(path) when is_atom(path), do: "$.#{path}"

  defp to_path(path) when is_list(path) do
    "$." <> Enum.map_join(path, ".", &path_segment/1)
  end

  defp path_segment(seg) when is_atom(seg), do: Atom.to_string(seg)
  defp path_segment(seg) when is_integer(seg), do: "[#{seg}]"
  defp path_segment(seg) when is_binary(seg), do: seg

  # -------------------------------------------------------------------
  # Result Unwrapping
  # -------------------------------------------------------------------

  # Root get with no field selection: unwrap the JSONPath array wrapper
  defp unwrap_result([map], nil, atom_keys) when is_map(map) do
    maybe_atomize(map, atom_keys)
  end

  # Single-field get: response is a JSON array like ["Alice"]
  defp unwrap_result(list, [field], atom_keys) when is_list(list) do
    key = to_string(field)

    val =
      case list do
        [v] -> v
        v -> v
      end

    maybe_atomize(%{key => val}, atom_keys)
  end

  # Multi-field get: response is %{"$.name" => [...], "$.age" => [...]}
  defp unwrap_result(map, fields, atom_keys) when is_map(map) and is_list(fields) do
    result =
      Enum.reduce(fields, %{}, fn field, acc ->
        path = to_path(field)
        key = to_string(field)

        case Map.get(map, path) do
          [val] -> Map.put(acc, key, val)
          val -> Map.put(acc, key, val)
        end
      end)

    maybe_atomize(result, atom_keys)
  end

  defp unwrap_result(other, _, _atom_keys), do: other

  defp unwrap_scalar([val], _atom_keys), do: val
  defp unwrap_scalar(other, _atom_keys), do: other

  defp maybe_atomize(map, false), do: map

  defp maybe_atomize(map, true) do
    Map.new(map, fn {k, v} -> {String.to_existing_atom(k), v} end)
  rescue
    ArgumentError -> map
  end

  defp parse_type([type]) when is_binary(type), do: String.to_atom(type)
  defp parse_type([[type]]) when is_binary(type), do: String.to_atom(type)
  defp parse_type(type) when is_binary(type), do: String.to_atom(type)
  defp parse_type(other), do: other

  defp unwrap_numeric([n]) when is_number(n), do: n
  defp unwrap_numeric(str) when is_binary(str), do: parse_number(str)
  defp unwrap_numeric(n) when is_number(n), do: n
  defp unwrap_numeric(other), do: other

  defp parse_number(str) do
    case Integer.parse(str) do
      {n, ""} ->
        n

      _ ->
        case Float.parse(str) do
          {f, ""} -> f
          _ -> str
        end
    end
  end

  defp safe_decode(str) do
    Jason.decode!(str)
  rescue
    _ -> str
  end
end

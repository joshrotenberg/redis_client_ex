defmodule Redis.VectorSet do
  @moduledoc """
  High-level API for Redis Vector Sets (Redis 8.0+).

  Wraps the Vector Set commands with a connection-aware interface. For raw
  command builders, see `Redis.Commands.VectorSet`.

  ## Quick Start

      # Add elements with vectors
      {:ok, 1} = Redis.VectorSet.vadd(conn, "movies", "matrix", [0.1, 0.8, 0.3])

      # Search by vector similarity
      {:ok, results} = Redis.VectorSet.search(conn, "movies", [0.1, 0.8, 0.3], count: 5)

      # Search by existing element
      {:ok, results} = Redis.VectorSet.vsim(conn, "movies", {:element, "matrix"}, count: 10)

      # Manage attributes
      {:ok, "OK"} = Redis.VectorSet.vsetattr(conn, "movies", "matrix", ~s({"year": 1999}))
      {:ok, json} = Redis.VectorSet.vgetattr(conn, "movies", "matrix")

  ## Attribute Filtering

  When searching with `vsim/4` or `search/4`, the `:filter` option accepts
  a filter expression string that is evaluated against element attributes:

      Redis.VectorSet.search(conn, "movies", vector, filter: ".year > 2000")
  """

  alias Redis.Commands.VectorSet, as: Cmd
  alias Redis.Connection

  @doc """
  Adds an element with a vector to a vector set.

  See `Redis.Commands.VectorSet.vadd/4` for available options.
  """
  def vadd(conn, key, element, vector, opts \\ []) do
    Connection.command(conn, Cmd.vadd(key, element, vector, opts))
  end

  @doc """
  Removes an element from a vector set.
  """
  def vrem(conn, key, element) do
    Connection.command(conn, Cmd.vrem(key, element))
  end

  @doc """
  Returns the number of elements in a vector set.
  """
  def vcard(conn, key) do
    Connection.command(conn, Cmd.vcard(key))
  end

  @doc """
  Returns the vector dimensions of a vector set.
  """
  def vdim(conn, key) do
    Connection.command(conn, Cmd.vdim(key))
  end

  @doc """
  Gets the embedding vector of an element.

  See `Redis.Commands.VectorSet.vemb/3` for available options.
  """
  def vemb(conn, key, element, opts \\ []) do
    Connection.command(conn, Cmd.vemb(key, element, opts))
  end

  @doc """
  Gets the JSON attributes of an element.
  """
  def vgetattr(conn, key, element) do
    Connection.command(conn, Cmd.vgetattr(key, element))
  end

  @doc """
  Sets JSON attributes on an element.
  """
  def vsetattr(conn, key, element, json) do
    Connection.command(conn, Cmd.vsetattr(key, element, json))
  end

  @doc """
  Returns one or more random elements from a vector set.

  See `Redis.Commands.VectorSet.vrandmember/2` for available options.
  """
  def vrandmember(conn, key, opts \\ []) do
    Connection.command(conn, Cmd.vrandmember(key, opts))
  end

  @doc """
  Performs a similarity search on a vector set.

  The `search_input` is either `{:element, name}` to search by an existing
  element, or `{:vector, [floats]}` to search by a raw vector.

  See `Redis.Commands.VectorSet.vsim/3` for available options.
  """
  def vsim(conn, key, search_input, opts \\ []) do
    Connection.command(conn, Cmd.vsim(key, search_input, opts))
  end

  @doc """
  Searches for similar elements using a vector.

  This is a convenience wrapper around `vsim/4` that accepts a plain list of
  floats as the query vector instead of requiring the `{:vector, v}` tuple.

      {:ok, results} = Redis.VectorSet.search(conn, "movies", [0.1, 0.8, 0.3], count: 5)
  """
  def search(conn, key, vector, opts \\ []) when is_list(vector) do
    vsim(conn, key, {:vector, vector}, opts)
  end

  @doc """
  Returns information about a vector set.
  """
  def vinfo(conn, key) do
    Connection.command(conn, Cmd.vinfo(key))
  end

  @doc """
  Gets the graph links of an element.

  See `Redis.Commands.VectorSet.vlinks/3` for available options.
  """
  def vlinks(conn, key, element, opts \\ []) do
    Connection.command(conn, Cmd.vlinks(key, element, opts))
  end
end

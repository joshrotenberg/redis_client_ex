defmodule Redis.Commands.VectorSet do
  @moduledoc """
  Command builders for Redis Vector Set operations (Redis 8.0+).

  Vector Sets are a data type for approximate nearest-neighbor similarity
  search. Each element is associated with a high-dimensional vector, and
  the set supports efficient queries for the most similar elements.

  Every function returns a plain list of strings (a command). To execute
  a command, pass the result to `Redis.command/2`; to batch several
  commands in a single round trip, use `Redis.pipeline/2`.

  ## Examples

  Adding elements with vectors:

      iex> Redis.command(conn, Redis.Commands.VectorSet.vadd("vs", "item1", [1.0, 2.0, 3.0]))
      {:ok, 1}

  Searching for similar elements:

      iex> Redis.command(conn, Redis.Commands.VectorSet.vsim("vs", {:vector, [1.0, 2.0, 3.0]}, count: 5))
      {:ok, ["item1", "item2"]}

  Getting element embeddings:

      iex> Redis.command(conn, Redis.Commands.VectorSet.vemb("vs", "item1"))
      {:ok, [1.0, 2.0, 3.0]}
  """

  @doc """
  Builds a VADD command to add an element with a vector to the vector set at `key`.

  The vector is provided as a list of floats and serialized using the
  `VALUES count v1 v2 ...` format.

  ## Options

    * `:reduce` - reduce dimensionality to the given integer
    * `:quantization` - quantization type: `:q8`, `:bin`, or `:noquant`
    * `:ef` - exploration factor for insertion
    * `:setattr` - JSON string of attributes to associate with the element
    * `:cas` - compare-and-swap value for conditional updates
  """
  @spec vadd(String.t(), String.t(), [float()], keyword()) :: [String.t()]
  def vadd(key, element, vector, opts \\ []) when is_list(vector) do
    cmd = ["VADD", key]
    cmd = if opts[:reduce], do: cmd ++ ["REDUCE", to_string(opts[:reduce])], else: cmd

    cmd =
      if opts[:quantization],
        do: cmd ++ ["QUANTIZATION", quantization_value(opts[:quantization])],
        else: cmd

    cmd = if opts[:ef], do: cmd ++ ["EF", to_string(opts[:ef])], else: cmd
    cmd = if opts[:setattr], do: cmd ++ ["SETATTR", opts[:setattr]], else: cmd
    cmd = if opts[:cas], do: cmd ++ ["CAS", to_string(opts[:cas])], else: cmd

    cmd ++ [element, "VALUES", to_string(length(vector)) | Enum.map(vector, &to_string/1)]
  end

  @doc """
  Builds a VREM command to remove an element from the vector set at `key`.
  """
  @spec vrem(String.t(), String.t()) :: [String.t()]
  def vrem(key, element), do: ["VREM", key, element]

  @doc """
  Builds a VCARD command to return the number of elements in the vector set at `key`.
  """
  @spec vcard(String.t()) :: [String.t()]
  def vcard(key), do: ["VCARD", key]

  @doc """
  Builds a VDIM command to return the vector dimensions of the vector set at `key`.
  """
  @spec vdim(String.t()) :: [String.t()]
  def vdim(key), do: ["VDIM", key]

  @doc """
  Builds a VEMB command to get the embedding vector of an element.

  ## Options

    * `:raw` - return raw binary representation
  """
  @spec vemb(String.t(), String.t(), keyword()) :: [String.t()]
  def vemb(key, element, opts \\ []) do
    cmd = ["VEMB", key, element]
    if opts[:raw], do: cmd ++ ["RAW"], else: cmd
  end

  @doc """
  Builds a VGETATTR command to get the JSON attributes of an element.
  """
  @spec vgetattr(String.t(), String.t()) :: [String.t()]
  def vgetattr(key, element), do: ["VGETATTR", key, element]

  @doc """
  Builds a VSETATTR command to set JSON attributes on an element.
  """
  @spec vsetattr(String.t(), String.t(), String.t()) :: [String.t()]
  def vsetattr(key, element, json), do: ["VSETATTR", key, element, json]

  @doc """
  Builds a VRANDMEMBER command to return one or more random elements.

  ## Options

    * `:count` - number of random elements to return
  """
  @spec vrandmember(String.t(), keyword()) :: [String.t()]
  def vrandmember(key, opts \\ []) do
    cmd = ["VRANDMEMBER", key]
    if opts[:count], do: cmd ++ [to_string(opts[:count])], else: cmd
  end

  @doc """
  Builds a VSIM command for similarity search.

  The `search_input` is either `{:element, name}` to search by an existing
  element, or `{:vector, [floats]}` to search by a raw vector.

  ## Options

    * `:count` - maximum number of results
    * `:ef` - exploration factor for search
    * `:filter` - FILTER expression string for attribute-based filtering
    * `:filter_ef` - exploration factor for filtered search
    * `:truth` - use brute-force exact search (boolean)
    * `:nothread` - disable multi-threading (boolean)
    * `:withscores` - include similarity scores in the reply (boolean)
  """
  @spec vsim(String.t(), {:element, String.t()} | {:vector, [float()]}, keyword()) :: [
          String.t()
        ]
  def vsim(key, search_input, opts \\ []) do
    ["VSIM", key]
    |> append_search_input(search_input)
    |> append_vsim_opts(opts)
  end

  defp append_search_input(cmd, {:element, name}), do: cmd ++ ["ELE", name]

  defp append_search_input(cmd, {:vector, vector}) when is_list(vector) do
    cmd ++ ["VALUES", to_string(length(vector)) | Enum.map(vector, &to_string/1)]
  end

  defp append_vsim_opts(cmd, opts) do
    cmd
    |> maybe_append_kv(opts[:count], "COUNT")
    |> maybe_append_kv(opts[:ef], "EF")
    |> maybe_append_str(opts[:filter], "FILTER")
    |> maybe_append_kv(opts[:filter_ef], "FILTER-EF")
    |> maybe_append_flag(opts[:truth], "TRUTH")
    |> maybe_append_flag(opts[:nothread], "NOTHREAD")
    |> maybe_append_flag(opts[:withscores], "WITHSCORES")
  end

  defp maybe_append_kv(cmd, nil, _label), do: cmd
  defp maybe_append_kv(cmd, val, label), do: cmd ++ [label, to_string(val)]

  defp maybe_append_str(cmd, nil, _label), do: cmd
  defp maybe_append_str(cmd, val, label), do: cmd ++ [label, val]

  defp maybe_append_flag(cmd, true, label), do: cmd ++ [label]
  defp maybe_append_flag(cmd, _val, _label), do: cmd

  @doc """
  Builds a VINFO command to return information about the vector set at `key`.
  """
  @spec vinfo(String.t()) :: [String.t()]
  def vinfo(key), do: ["VINFO", key]

  @doc """
  Builds a VLINKS command to get the graph links of an element.

  ## Options

    * `:withscores` - include link scores in the reply
  """
  @spec vlinks(String.t(), String.t(), keyword()) :: [String.t()]
  def vlinks(key, element, opts \\ []) do
    cmd = ["VLINKS", key, element]
    if opts[:withscores], do: cmd ++ ["WITHSCORES"], else: cmd
  end

  defp quantization_value(:q8), do: "Q8"
  defp quantization_value(:bin), do: "BIN"
  defp quantization_value(:noquant), do: "NOQUANT"
end

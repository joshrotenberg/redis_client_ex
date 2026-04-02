defmodule Redis.Commands.Geo do
  @moduledoc """
  Command builders for Redis geospatial operations.

  Provides pure functions that build command lists for storing, querying, and
  measuring geographic coordinates using Redis sorted sets. Supports adding
  members with longitude/latitude (GEOADD), searching by radius or bounding box
  (GEOSEARCH), computing distances (GEODIST), and retrieving positions (GEOPOS).
  Each function returns a plain list of strings suitable for passing to
  `Redis.command/2` or `Redis.pipeline/2`.

  These functions contain no connection or networking logic -- they only construct
  the Redis protocol command as a list.

  ## Examples

  Add geographic coordinates for several locations:

      iex> Redis.Commands.Geo.geoadd("restaurants", [{-122.4194, 37.7749, "San Francisco"}, {-73.9857, 40.7484, "New York"}])
      ["GEOADD", "restaurants", "-122.4194", "37.7749", "San Francisco", "-73.9857", "40.7484", "New York"]

  Search for members within a radius of a given point:

      iex> Redis.Commands.Geo.geosearch("restaurants", fromlonlat: {-122.4194, 37.7749}, byradius: {50, "km"}, asc: true)
      ["GEOSEARCH", "restaurants", "FROMLONLAT", "-122.4194", "37.7749", "BYRADIUS", "50", "km", "ASC"]

  Compute the distance between two members:

      iex> Redis.Commands.Geo.geodist("restaurants", "San Francisco", "New York", "mi")
      ["GEODIST", "restaurants", "San Francisco", "New York", "mi"]
  """

  @doc """
  Builds a GEOADD command to add members with longitude/latitude to a geo set.

  Each member is a `{longitude, latitude, name}` tuple. Supports `:nx` (only add
  new members), `:xx` (only update existing), and `:ch` (return count of changed
  elements).

  ## Example

      iex> Redis.Commands.Geo.geoadd("places", [{13.361389, 38.115556, "Palermo"}], ch: true)
      ["GEOADD", "places", "CH", "13.361389", "38.115556", "Palermo"]
  """
  @spec geoadd(String.t(), [{float(), float(), String.t()}], keyword()) :: [String.t()]
  def geoadd(key, members, opts \\ []) when is_list(members) do
    cmd = ["GEOADD", key]
    cmd = if opts[:nx], do: cmd ++ ["NX"], else: cmd
    cmd = if opts[:xx], do: cmd ++ ["XX"], else: cmd
    cmd = if opts[:ch], do: cmd ++ ["CH"], else: cmd

    cmd ++
      Enum.flat_map(members, fn {lng, lat, member} -> [to_string(lng), to_string(lat), member] end)
  end

  @doc """
  Builds a GEODIST command to compute the distance between two members.

  The optional unit argument can be "m" (meters, default), "km", "mi", or "ft".

  ## Examples

      iex> Redis.Commands.Geo.geodist("places", "Palermo", "Catania")
      ["GEODIST", "places", "Palermo", "Catania"]

      iex> Redis.Commands.Geo.geodist("places", "Palermo", "Catania", "km")
      ["GEODIST", "places", "Palermo", "Catania", "km"]
  """
  @spec geodist(String.t(), String.t(), String.t(), String.t() | nil) :: [String.t()]
  def geodist(key, member1, member2, unit \\ nil) do
    cmd = ["GEODIST", key, member1, member2]
    if unit, do: cmd ++ [unit], else: cmd
  end

  @spec geohash(String.t(), [String.t()]) :: [String.t()]
  def geohash(key, members) when is_list(members), do: ["GEOHASH", key | members]

  @doc """
  Builds a GEOPOS command to retrieve the longitude/latitude of one or more members.

  ## Example

      iex> Redis.Commands.Geo.geopos("places", ["Palermo", "Catania"])
      ["GEOPOS", "places", "Palermo", "Catania"]
  """
  @spec geopos(String.t(), [String.t()]) :: [String.t()]
  def geopos(key, members) when is_list(members), do: ["GEOPOS", key | members]

  @doc """
  Builds a GEOSEARCH command to query members within a geographic area.

  Requires an origin (`:fromlonlat` or `:frommember`) and a shape (`:byradius`
  or `:bybox`). Supports ordering (`:asc`/`:desc`), result limiting (`:count`),
  and optional coordinate/distance/hash output (`:withcoord`, `:withdist`,
  `:withhash`).

  ## Example

      iex> Redis.Commands.Geo.geosearch("places", frommember: "Palermo", byradius: {200, "km"}, count: 5, withcoord: true)
      ["GEOSEARCH", "places", "FROMMEMBER", "Palermo", "BYRADIUS", "200", "km", "COUNT", "5", "WITHCOORD"]
  """
  @spec geosearch(String.t(), keyword()) :: [String.t()]
  def geosearch(key, opts \\ []) do
    ["GEOSEARCH", key]
    |> append_search_origin(opts)
    |> append_search_shape(opts)
    |> append_search_order(opts)
    |> append_search_result_opts(opts)
  end

  @spec geosearchstore(String.t(), String.t(), keyword()) :: [String.t()]
  def geosearchstore(destination, source, opts \\ []) do
    cmd =
      ["GEOSEARCHSTORE", destination, source]
      |> append_search_origin(opts)
      |> append_search_shape(opts)
      |> append_search_order(opts)

    cmd = if opts[:storedist], do: cmd ++ ["STOREDIST"], else: cmd
    cmd
  end

  defp append_search_origin(cmd, opts) do
    cmd = if opts[:frommember], do: cmd ++ ["FROMMEMBER", opts[:frommember]], else: cmd

    if opts[:fromlonlat] do
      cmd ++
        [
          "FROMLONLAT",
          to_string(elem(opts[:fromlonlat], 0)),
          to_string(elem(opts[:fromlonlat], 1))
        ]
    else
      cmd
    end
  end

  defp append_search_shape(cmd, opts) do
    cmd =
      if opts[:byradius],
        do: cmd ++ ["BYRADIUS", to_string(elem(opts[:byradius], 0)), elem(opts[:byradius], 1)],
        else: cmd

    if opts[:bybox] do
      cmd ++
        [
          "BYBOX",
          to_string(elem(opts[:bybox], 0)),
          to_string(elem(opts[:bybox], 1)),
          elem(opts[:bybox], 2)
        ]
    else
      cmd
    end
  end

  defp append_search_order(cmd, opts) do
    cmd = if opts[:asc], do: cmd ++ ["ASC"], else: cmd
    cmd = if opts[:desc], do: cmd ++ ["DESC"], else: cmd
    cmd = if opts[:count], do: cmd ++ ["COUNT", to_string(opts[:count])], else: cmd
    cmd = if opts[:any], do: cmd ++ ["ANY"], else: cmd
    cmd
  end

  defp append_search_result_opts(cmd, opts) do
    cmd = if opts[:withcoord], do: cmd ++ ["WITHCOORD"], else: cmd
    cmd = if opts[:withdist], do: cmd ++ ["WITHDIST"], else: cmd
    cmd = if opts[:withhash], do: cmd ++ ["WITHHASH"], else: cmd
    cmd
  end

  @doc "Deprecated: use geosearch/2 instead."
  @spec georadius(String.t(), float(), float(), float() | integer(), String.t(), keyword()) :: [
          String.t()
        ]
  def georadius(key, longitude, latitude, radius, unit, opts \\ []) do
    cmd = ["GEORADIUS", key, to_string(longitude), to_string(latitude), to_string(radius), unit]
    cmd = if opts[:withcoord], do: cmd ++ ["WITHCOORD"], else: cmd
    cmd = if opts[:withdist], do: cmd ++ ["WITHDIST"], else: cmd
    cmd = if opts[:withhash], do: cmd ++ ["WITHHASH"], else: cmd
    cmd = if opts[:count], do: cmd ++ ["COUNT", to_string(opts[:count])], else: cmd
    cmd = if opts[:asc], do: cmd ++ ["ASC"], else: cmd
    cmd = if opts[:desc], do: cmd ++ ["DESC"], else: cmd
    cmd = if opts[:store], do: cmd ++ ["STORE", opts[:store]], else: cmd
    cmd = if opts[:storedist], do: cmd ++ ["STOREDIST", opts[:storedist]], else: cmd
    cmd
  end

  @doc "Deprecated: use geosearch/2 instead."
  @spec georadiusbymember(String.t(), String.t(), float() | integer(), String.t(), keyword()) :: [
          String.t()
        ]
  def georadiusbymember(key, member, radius, unit, opts \\ []) do
    cmd = ["GEORADIUSBYMEMBER", key, member, to_string(radius), unit]
    cmd = if opts[:withcoord], do: cmd ++ ["WITHCOORD"], else: cmd
    cmd = if opts[:withdist], do: cmd ++ ["WITHDIST"], else: cmd
    cmd = if opts[:withhash], do: cmd ++ ["WITHHASH"], else: cmd
    cmd = if opts[:count], do: cmd ++ ["COUNT", to_string(opts[:count])], else: cmd
    cmd = if opts[:asc], do: cmd ++ ["ASC"], else: cmd
    cmd = if opts[:desc], do: cmd ++ ["DESC"], else: cmd
    cmd = if opts[:store], do: cmd ++ ["STORE", opts[:store]], else: cmd
    cmd = if opts[:storedist], do: cmd ++ ["STOREDIST", opts[:storedist]], else: cmd
    cmd
  end
end

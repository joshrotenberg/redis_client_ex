defmodule RedisEx.Commands.Geo do
  @moduledoc """
  Command builders for Redis geospatial operations.
  """

  @spec geoadd(String.t(), [{float(), float(), String.t()}], keyword()) :: [String.t()]
  def geoadd(key, members, opts \\ []) when is_list(members) do
    cmd = ["GEOADD", key]
    cmd = if opts[:nx], do: cmd ++ ["NX"], else: cmd
    cmd = if opts[:xx], do: cmd ++ ["XX"], else: cmd
    cmd = if opts[:ch], do: cmd ++ ["CH"], else: cmd
    cmd ++ Enum.flat_map(members, fn {lng, lat, member} -> [to_string(lng), to_string(lat), member] end)
  end

  @spec geodist(String.t(), String.t(), String.t(), String.t() | nil) :: [String.t()]
  def geodist(key, member1, member2, unit \\ nil) do
    cmd = ["GEODIST", key, member1, member2]
    if unit, do: cmd ++ [unit], else: cmd
  end

  @spec geohash(String.t(), [String.t()]) :: [String.t()]
  def geohash(key, members) when is_list(members), do: ["GEOHASH", key | members]

  @spec geopos(String.t(), [String.t()]) :: [String.t()]
  def geopos(key, members) when is_list(members), do: ["GEOPOS", key | members]

  @spec geosearch(String.t(), keyword()) :: [String.t()]
  def geosearch(key, opts \\ []) do
    cmd = ["GEOSEARCH", key]
    cmd = if opts[:frommember], do: cmd ++ ["FROMMEMBER", opts[:frommember]], else: cmd
    cmd = if opts[:fromlonlat], do: cmd ++ ["FROMLONLAT", to_string(elem(opts[:fromlonlat], 0)), to_string(elem(opts[:fromlonlat], 1))], else: cmd
    cmd = if opts[:byradius], do: cmd ++ ["BYRADIUS", to_string(elem(opts[:byradius], 0)), elem(opts[:byradius], 1)], else: cmd
    cmd = if opts[:bybox], do: cmd ++ ["BYBOX", to_string(elem(opts[:bybox], 0)), to_string(elem(opts[:bybox], 1)), elem(opts[:bybox], 2)], else: cmd
    cmd = if opts[:asc], do: cmd ++ ["ASC"], else: cmd
    cmd = if opts[:desc], do: cmd ++ ["DESC"], else: cmd
    cmd = if opts[:count], do: cmd ++ ["COUNT", to_string(opts[:count])], else: cmd
    cmd = if opts[:any], do: cmd ++ ["ANY"], else: cmd
    cmd = if opts[:withcoord], do: cmd ++ ["WITHCOORD"], else: cmd
    cmd = if opts[:withdist], do: cmd ++ ["WITHDIST"], else: cmd
    cmd = if opts[:withhash], do: cmd ++ ["WITHHASH"], else: cmd
    cmd
  end

  @spec geosearchstore(String.t(), String.t(), keyword()) :: [String.t()]
  def geosearchstore(destination, source, opts \\ []) do
    cmd = ["GEOSEARCHSTORE", destination, source]
    cmd = if opts[:frommember], do: cmd ++ ["FROMMEMBER", opts[:frommember]], else: cmd
    cmd = if opts[:fromlonlat], do: cmd ++ ["FROMLONLAT", to_string(elem(opts[:fromlonlat], 0)), to_string(elem(opts[:fromlonlat], 1))], else: cmd
    cmd = if opts[:byradius], do: cmd ++ ["BYRADIUS", to_string(elem(opts[:byradius], 0)), elem(opts[:byradius], 1)], else: cmd
    cmd = if opts[:bybox], do: cmd ++ ["BYBOX", to_string(elem(opts[:bybox], 0)), to_string(elem(opts[:bybox], 1)), elem(opts[:bybox], 2)], else: cmd
    cmd = if opts[:asc], do: cmd ++ ["ASC"], else: cmd
    cmd = if opts[:desc], do: cmd ++ ["DESC"], else: cmd
    cmd = if opts[:count], do: cmd ++ ["COUNT", to_string(opts[:count])], else: cmd
    cmd = if opts[:any], do: cmd ++ ["ANY"], else: cmd
    cmd = if opts[:storedist], do: cmd ++ ["STOREDIST"], else: cmd
    cmd
  end
end

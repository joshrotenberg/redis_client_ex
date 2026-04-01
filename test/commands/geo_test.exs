defmodule Redis.Commands.GeoTest do
  use ExUnit.Case, async: true

  alias Redis.Commands.Geo

  describe "GEOADD" do
    test "basic" do
      assert Geo.geoadd("geo", [{13.361389, 38.115556, "Palermo"}]) ==
               ["GEOADD", "geo", "13.361389", "38.115556", "Palermo"]
    end

    test "with NX" do
      cmd = Geo.geoadd("geo", [{13.361389, 38.115556, "Palermo"}], nx: true)
      assert cmd == ["GEOADD", "geo", "NX", "13.361389", "38.115556", "Palermo"]
    end

    test "with XX and CH" do
      cmd = Geo.geoadd("geo", [{1.0, 2.0, "m"}], xx: true, ch: true)
      assert cmd == ["GEOADD", "geo", "XX", "CH", "1.0", "2.0", "m"]
    end

    test "multiple members" do
      cmd = Geo.geoadd("geo", [{1.0, 2.0, "a"}, {3.0, 4.0, "b"}])
      assert cmd == ["GEOADD", "geo", "1.0", "2.0", "a", "3.0", "4.0", "b"]
    end
  end

  describe "GEODIST" do
    test "without unit" do
      assert Geo.geodist("geo", "a", "b") == ["GEODIST", "geo", "a", "b"]
    end

    test "with unit" do
      assert Geo.geodist("geo", "a", "b", "km") == ["GEODIST", "geo", "a", "b", "km"]
    end
  end

  describe "GEOHASH" do
    test "basic" do
      assert Geo.geohash("geo", ["a", "b"]) == ["GEOHASH", "geo", "a", "b"]
    end
  end

  describe "GEOPOS" do
    test "basic" do
      assert Geo.geopos("geo", ["a", "b"]) == ["GEOPOS", "geo", "a", "b"]
    end
  end

  describe "GEOSEARCH" do
    test "by member and radius" do
      cmd = Geo.geosearch("geo", frommember: "Palermo", byradius: {100, "km"}, asc: true)
      assert cmd == ["GEOSEARCH", "geo", "FROMMEMBER", "Palermo", "BYRADIUS", "100", "km", "ASC"]
    end

    test "by lonlat and box" do
      cmd = Geo.geosearch("geo", fromlonlat: {15.0, 37.0}, bybox: {200, 400, "km"})

      assert cmd == [
               "GEOSEARCH",
               "geo",
               "FROMLONLAT",
               "15.0",
               "37.0",
               "BYBOX",
               "200",
               "400",
               "km"
             ]
    end

    test "with count and any" do
      cmd = Geo.geosearch("geo", frommember: "x", byradius: {10, "mi"}, count: 5, any: true)
      assert "COUNT" in cmd
      assert "ANY" in cmd
    end

    test "with withcoord, withdist, withhash" do
      cmd =
        Geo.geosearch("geo",
          frommember: "x",
          byradius: {10, "m"},
          withcoord: true,
          withdist: true,
          withhash: true
        )

      assert "WITHCOORD" in cmd
      assert "WITHDIST" in cmd
      assert "WITHHASH" in cmd
    end

    test "with desc" do
      cmd = Geo.geosearch("geo", frommember: "x", byradius: {10, "m"}, desc: true)
      assert "DESC" in cmd
    end
  end

  describe "GEOSEARCHSTORE" do
    test "basic" do
      cmd = Geo.geosearchstore("dest", "src", frommember: "x", byradius: {100, "km"})
      assert cmd == ["GEOSEARCHSTORE", "dest", "src", "FROMMEMBER", "x", "BYRADIUS", "100", "km"]
    end

    test "with storedist" do
      cmd =
        Geo.geosearchstore("dest", "src", frommember: "x", byradius: {10, "km"}, storedist: true)

      assert "STOREDIST" in cmd
    end
  end

  describe "GEORADIUS (deprecated)" do
    test "basic" do
      assert Geo.georadius("geo", 15.0, 37.0, 100, "km") ==
               ["GEORADIUS", "geo", "15.0", "37.0", "100", "km"]
    end

    test "with options" do
      cmd = Geo.georadius("geo", 15.0, 37.0, 100, "km", withcoord: true, count: 5, asc: true)
      assert "WITHCOORD" in cmd
      assert "COUNT" in cmd
      assert "ASC" in cmd
    end

    test "with store and storedist" do
      cmd = Geo.georadius("geo", 15.0, 37.0, 100, "km", store: "dest", storedist: "dest2")

      assert cmd == [
               "GEORADIUS",
               "geo",
               "15.0",
               "37.0",
               "100",
               "km",
               "STORE",
               "dest",
               "STOREDIST",
               "dest2"
             ]
    end
  end

  describe "GEORADIUSBYMEMBER (deprecated)" do
    test "basic" do
      assert Geo.georadiusbymember("geo", "Palermo", 100, "km") ==
               ["GEORADIUSBYMEMBER", "geo", "Palermo", "100", "km"]
    end

    test "with options" do
      cmd = Geo.georadiusbymember("geo", "Palermo", 100, "km", withdist: true, desc: true)
      assert "WITHDIST" in cmd
      assert "DESC" in cmd
    end
  end
end

defmodule Redis.Commands.TimeSeriesTest do
  use ExUnit.Case, async: true

  alias Redis.Commands.TimeSeries

  describe "TS.CREATE" do
    test "basic" do
      assert TimeSeries.ts_create("ts") == ["TS.CREATE", "ts"]
    end

    test "with retention" do
      assert TimeSeries.ts_create("ts", retention: 60000) ==
               ["TS.CREATE", "ts", "RETENTION", "60000"]
    end

    test "with labels" do
      cmd = TimeSeries.ts_create("ts", labels: [{"sensor", "temp"}])
      assert cmd == ["TS.CREATE", "ts", "LABELS", "sensor", "temp"]
    end

    test "with encoding, chunk_size, duplicate_policy" do
      cmd =
        TimeSeries.ts_create("ts",
          encoding: "COMPRESSED",
          chunk_size: 4096,
          duplicate_policy: "LAST"
        )

      assert cmd == [
               "TS.CREATE",
               "ts",
               "ENCODING",
               "COMPRESSED",
               "CHUNK_SIZE",
               "4096",
               "DUPLICATE_POLICY",
               "LAST"
             ]
    end
  end

  describe "TS.ALTER" do
    test "basic" do
      assert TimeSeries.ts_alter("ts") == ["TS.ALTER", "ts"]
    end

    test "with retention" do
      assert TimeSeries.ts_alter("ts", retention: 30000) ==
               ["TS.ALTER", "ts", "RETENTION", "30000"]
    end
  end

  describe "TS.ADD" do
    test "basic" do
      assert TimeSeries.ts_add("ts", "*", 42.5) == ["TS.ADD", "ts", "*", "42.5"]
    end

    test "with on_duplicate" do
      assert TimeSeries.ts_add("ts", 1000, 10, on_duplicate: "SUM") ==
               ["TS.ADD", "ts", "1000", "10", "ON_DUPLICATE", "SUM"]
    end
  end

  describe "TS.MADD" do
    test "basic" do
      assert TimeSeries.ts_madd([{"ts1", 1000, 1.0}, {"ts2", 1000, 2.0}]) ==
               ["TS.MADD", "ts1", "1000", "1.0", "ts2", "1000", "2.0"]
    end
  end

  describe "TS.INCRBY" do
    test "basic" do
      assert TimeSeries.ts_incrby("ts", 5) == ["TS.INCRBY", "ts", "5"]
    end

    test "with timestamp" do
      assert TimeSeries.ts_incrby("ts", 5, timestamp: 1000) ==
               ["TS.INCRBY", "ts", "5", "TIMESTAMP", "1000"]
    end
  end

  describe "TS.DECRBY" do
    test "basic" do
      assert TimeSeries.ts_decrby("ts", 3) == ["TS.DECRBY", "ts", "3"]
    end

    test "with timestamp" do
      assert TimeSeries.ts_decrby("ts", 3, timestamp: 2000) ==
               ["TS.DECRBY", "ts", "3", "TIMESTAMP", "2000"]
    end
  end

  describe "TS.DEL" do
    test "basic" do
      assert TimeSeries.ts_del("ts", 1000, 2000) == ["TS.DEL", "ts", "1000", "2000"]
    end
  end

  describe "TS.GET" do
    test "basic" do
      assert TimeSeries.ts_get("ts") == ["TS.GET", "ts"]
    end

    test "with latest" do
      assert TimeSeries.ts_get("ts", latest: true) == ["TS.GET", "ts", "LATEST"]
    end
  end

  describe "TS.MGET" do
    test "basic" do
      assert TimeSeries.ts_mget(["sensor=temp"]) == ["TS.MGET", "FILTER", "sensor=temp"]
    end

    test "with options" do
      assert TimeSeries.ts_mget(["sensor=temp"], latest: true, withlabels: true) ==
               ["TS.MGET", "LATEST", "WITHLABELS", "FILTER", "sensor=temp"]
    end
  end

  describe "TS.RANGE" do
    test "basic" do
      assert TimeSeries.ts_range("ts", "-", "+") == ["TS.RANGE", "ts", "-", "+"]
    end

    test "with count" do
      assert TimeSeries.ts_range("ts", 1000, 2000, count: 10) ==
               ["TS.RANGE", "ts", "1000", "2000", "COUNT", "10"]
    end

    test "with aggregation" do
      assert TimeSeries.ts_range("ts", "-", "+", aggregation: {"avg", 5000}) ==
               ["TS.RANGE", "ts", "-", "+", "AGGREGATION", "avg", "5000"]
    end

    test "with filter_by_value" do
      assert TimeSeries.ts_range("ts", "-", "+", filter_by_value: {10, 100}) ==
               ["TS.RANGE", "ts", "-", "+", "FILTER_BY_VALUE", "10", "100"]
    end
  end

  describe "TS.REVRANGE" do
    test "basic" do
      assert TimeSeries.ts_revrange("ts", "-", "+") == ["TS.REVRANGE", "ts", "-", "+"]
    end
  end

  describe "TS.MRANGE" do
    test "basic" do
      assert TimeSeries.ts_mrange("-", "+", ["sensor=temp"]) ==
               ["TS.MRANGE", "-", "+", "FILTER", "sensor=temp"]
    end

    test "with options" do
      cmd = TimeSeries.ts_mrange("-", "+", ["sensor=temp"], withlabels: true, count: 5)
      assert "WITHLABELS" in cmd
      assert "COUNT" in cmd
      assert "FILTER" in cmd
    end
  end

  describe "TS.MREVRANGE" do
    test "basic" do
      assert TimeSeries.ts_mrevrange("-", "+", ["sensor=temp"]) ==
               ["TS.MREVRANGE", "-", "+", "FILTER", "sensor=temp"]
    end
  end

  describe "TS.QUERYINDEX" do
    test "basic" do
      assert TimeSeries.ts_queryindex(["sensor=temp"]) == ["TS.QUERYINDEX", "sensor=temp"]
    end
  end

  describe "TS.INFO" do
    test "basic" do
      assert TimeSeries.ts_info("ts") == ["TS.INFO", "ts"]
    end

    test "with debug" do
      assert TimeSeries.ts_info("ts", debug: true) == ["TS.INFO", "ts", "DEBUG"]
    end
  end
end

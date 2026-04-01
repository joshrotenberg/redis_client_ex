defmodule Redis.Commands.TDigestTest do
  use ExUnit.Case, async: true

  alias Redis.Commands.TDigest

  describe "CREATE" do
    test "without options" do
      assert TDigest.create("td") == ["TDIGEST.CREATE", "td"]
    end

    test "with compression" do
      assert TDigest.create("td", compression: 100) ==
               ["TDIGEST.CREATE", "td", "COMPRESSION", "100"]
    end
  end

  describe "ADD" do
    test "basic" do
      assert TDigest.add("td", [1.0, 2.5, 3.7]) == ["TDIGEST.ADD", "td", "1.0", "2.5", "3.7"]
    end
  end

  describe "CDF" do
    test "basic" do
      assert TDigest.cdf("td", [1.0, 2.0]) == ["TDIGEST.CDF", "td", "1.0", "2.0"]
    end
  end

  describe "QUANTILE" do
    test "basic" do
      assert TDigest.quantile("td", [0.5, 0.9]) == ["TDIGEST.QUANTILE", "td", "0.5", "0.9"]
    end
  end

  describe "MIN" do
    test "basic" do
      assert TDigest.min("td") == ["TDIGEST.MIN", "td"]
    end
  end

  describe "MAX" do
    test "basic" do
      assert TDigest.max("td") == ["TDIGEST.MAX", "td"]
    end
  end

  describe "INFO" do
    test "basic" do
      assert TDigest.info("td") == ["TDIGEST.INFO", "td"]
    end
  end

  describe "MERGE" do
    test "without options" do
      assert TDigest.merge("dest", ["s1", "s2"]) ==
               ["TDIGEST.MERGE", "dest", "2", "s1", "s2"]
    end

    test "with compression" do
      assert TDigest.merge("dest", ["s1"], compression: 200) ==
               ["TDIGEST.MERGE", "dest", "1", "s1", "COMPRESSION", "200"]
    end

    test "with override" do
      assert TDigest.merge("dest", ["s1"], override: true) ==
               ["TDIGEST.MERGE", "dest", "1", "s1", "OVERRIDE"]
    end
  end

  describe "RESET" do
    test "basic" do
      assert TDigest.reset("td") == ["TDIGEST.RESET", "td"]
    end
  end

  describe "TRIMMED_MEAN" do
    test "basic" do
      assert TDigest.trimmed_mean("td", 0.1, 0.9) ==
               ["TDIGEST.TRIMMED_MEAN", "td", "0.1", "0.9"]
    end
  end

  describe "RANK" do
    test "basic" do
      assert TDigest.rank("td", [1.0, 2.0]) == ["TDIGEST.RANK", "td", "1.0", "2.0"]
    end
  end

  describe "REVRANK" do
    test "basic" do
      assert TDigest.revrank("td", [1.0, 2.0]) == ["TDIGEST.REVRANK", "td", "1.0", "2.0"]
    end
  end

  describe "BYRANK" do
    test "basic" do
      assert TDigest.byrank("td", [0, 1, 2]) == ["TDIGEST.BYRANK", "td", "0", "1", "2"]
    end
  end

  describe "BYREVRANK" do
    test "basic" do
      assert TDigest.byrevrank("td", [0, 1]) == ["TDIGEST.BYREVRANK", "td", "0", "1"]
    end
  end
end

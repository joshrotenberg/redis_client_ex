defmodule Redis.Commands.BloomTest do
  use ExUnit.Case, async: true

  alias Redis.Commands.Bloom

  describe "ADD" do
    test "basic" do
      assert Bloom.add("bf", "item1") == ["BF.ADD", "bf", "item1"]
    end
  end

  describe "EXISTS" do
    test "basic" do
      assert Bloom.exists("bf", "item1") == ["BF.EXISTS", "bf", "item1"]
    end
  end

  describe "MADD" do
    test "multiple items" do
      assert Bloom.madd("bf", ["a", "b", "c"]) == ["BF.MADD", "bf", "a", "b", "c"]
    end
  end

  describe "MEXISTS" do
    test "multiple items" do
      assert Bloom.mexists("bf", ["a", "b"]) == ["BF.MEXISTS", "bf", "a", "b"]
    end
  end

  describe "RESERVE" do
    test "basic" do
      assert Bloom.reserve("bf", 0.01, 1000) == ["BF.RESERVE", "bf", "0.01", "1000"]
    end

    test "with expansion" do
      assert Bloom.reserve("bf", 0.01, 1000, expansion: 2) ==
               ["BF.RESERVE", "bf", "0.01", "1000", "EXPANSION", "2"]
    end

    test "with nonscaling" do
      assert Bloom.reserve("bf", 0.01, 1000, nonscaling: true) ==
               ["BF.RESERVE", "bf", "0.01", "1000", "NONSCALING"]
    end
  end

  describe "INFO" do
    test "basic" do
      assert Bloom.info("bf") == ["BF.INFO", "bf"]
    end
  end

  describe "INSERT" do
    test "basic" do
      assert Bloom.insert("bf", ["a", "b"]) == ["BF.INSERT", "bf", "ITEMS", "a", "b"]
    end

    test "with options" do
      assert Bloom.insert("bf", ["a"], capacity: 5000, error: 0.001, nocreate: true) ==
               ["BF.INSERT", "bf", "CAPACITY", "5000", "ERROR", "0.001", "NOCREATE", "ITEMS", "a"]
    end

    test "with expansion and nonscaling" do
      assert Bloom.insert("bf", ["x"], expansion: 4, nonscaling: true) ==
               ["BF.INSERT", "bf", "EXPANSION", "4", "NONSCALING", "ITEMS", "x"]
    end
  end

  describe "SCANDUMP" do
    test "basic" do
      assert Bloom.scandump("bf", 0) == ["BF.SCANDUMP", "bf", "0"]
    end
  end

  describe "LOADCHUNK" do
    test "basic" do
      assert Bloom.loadchunk("bf", 1, "data") == ["BF.LOADCHUNK", "bf", "1", "data"]
    end
  end
end

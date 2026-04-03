defmodule Redis.Commands.CuckooTest do
  use ExUnit.Case, async: true

  alias Redis.Commands.Cuckoo

  describe "ADD" do
    test "basic" do
      assert Cuckoo.add("cf", "item1") == ["CF.ADD", "cf", "item1"]
    end
  end

  describe "ADDNX" do
    test "basic" do
      assert Cuckoo.addnx("cf", "item1") == ["CF.ADDNX", "cf", "item1"]
    end
  end

  describe "EXISTS" do
    test "basic" do
      assert Cuckoo.exists("cf", "item1") == ["CF.EXISTS", "cf", "item1"]
    end
  end

  describe "DEL" do
    test "basic" do
      assert Cuckoo.del("cf", "item1") == ["CF.DEL", "cf", "item1"]
    end
  end

  describe "COUNT" do
    test "basic" do
      assert Cuckoo.count("cf", "item1") == ["CF.COUNT", "cf", "item1"]
    end
  end

  describe "RESERVE" do
    test "basic" do
      assert Cuckoo.reserve("cf", 1000) == ["CF.RESERVE", "cf", "1000"]
    end

    test "with bucketsize" do
      assert Cuckoo.reserve("cf", 1000, bucketsize: 4) ==
               ["CF.RESERVE", "cf", "1000", "BUCKETSIZE", "4"]
    end

    test "with maxiterations" do
      assert Cuckoo.reserve("cf", 1000, maxiterations: 20) ==
               ["CF.RESERVE", "cf", "1000", "MAXITERATIONS", "20"]
    end

    test "with expansion" do
      assert Cuckoo.reserve("cf", 1000, expansion: 2) ==
               ["CF.RESERVE", "cf", "1000", "EXPANSION", "2"]
    end
  end

  describe "INFO" do
    test "basic" do
      assert Cuckoo.info("cf") == ["CF.INFO", "cf"]
    end
  end

  describe "INSERT" do
    test "basic" do
      assert Cuckoo.insert("cf", ["a", "b"]) == ["CF.INSERT", "cf", "ITEMS", "a", "b"]
    end

    test "with capacity and nocreate" do
      assert Cuckoo.insert("cf", ["a"], capacity: 5000, nocreate: true) ==
               ["CF.INSERT", "cf", "CAPACITY", "5000", "NOCREATE", "ITEMS", "a"]
    end
  end

  describe "INSERTNX" do
    test "basic" do
      assert Cuckoo.insertnx("cf", ["a", "b"]) == ["CF.INSERTNX", "cf", "ITEMS", "a", "b"]
    end

    test "with options" do
      assert Cuckoo.insertnx("cf", ["a"], capacity: 1000, nocreate: true) ==
               ["CF.INSERTNX", "cf", "CAPACITY", "1000", "NOCREATE", "ITEMS", "a"]
    end
  end
end

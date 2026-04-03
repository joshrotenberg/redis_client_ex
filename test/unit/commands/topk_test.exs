defmodule Redis.Commands.TopKTest do
  use ExUnit.Case, async: true

  alias Redis.Commands.TopK

  describe "ADD" do
    test "basic" do
      assert TopK.add("tk", ["a", "b", "c"]) == ["TOPK.ADD", "tk", "a", "b", "c"]
    end
  end

  describe "QUERY" do
    test "basic" do
      assert TopK.query("tk", ["a", "b"]) == ["TOPK.QUERY", "tk", "a", "b"]
    end
  end

  describe "COUNT" do
    test "basic" do
      assert TopK.count("tk", ["a", "b"]) == ["TOPK.COUNT", "tk", "a", "b"]
    end
  end

  describe "LIST" do
    test "without options" do
      assert TopK.list("tk") == ["TOPK.LIST", "tk"]
    end

    test "with WITHCOUNT" do
      assert TopK.list("tk", withcount: true) == ["TOPK.LIST", "tk", "WITHCOUNT"]
    end
  end

  describe "RESERVE" do
    test "basic" do
      assert TopK.reserve("tk", 10) == ["TOPK.RESERVE", "tk", "10"]
    end

    test "with width, depth, decay" do
      assert TopK.reserve("tk", 10, width: 50, depth: 5, decay: 0.9) ==
               ["TOPK.RESERVE", "tk", "10", "50", "5", "0.9"]
    end
  end

  describe "INFO" do
    test "basic" do
      assert TopK.info("tk") == ["TOPK.INFO", "tk"]
    end
  end

  describe "INCRBY" do
    test "basic" do
      assert TopK.incrby("tk", [{"a", 3}, {"b", 5}]) ==
               ["TOPK.INCRBY", "tk", "a", "3", "b", "5"]
    end
  end
end

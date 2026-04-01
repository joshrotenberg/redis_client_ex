defmodule Redis.Commands.CMSTest do
  use ExUnit.Case, async: true

  alias Redis.Commands.CMS

  describe "INITBYDIM" do
    test "basic" do
      assert CMS.initbydim("cms", 2000, 5) == ["CMS.INITBYDIM", "cms", "2000", "5"]
    end
  end

  describe "INITBYPROB" do
    test "basic" do
      assert CMS.initbyprob("cms", 0.001, 0.01) == ["CMS.INITBYPROB", "cms", "0.001", "0.01"]
    end
  end

  describe "INCRBY" do
    test "basic" do
      assert CMS.incrby("cms", [{"a", 1}, {"b", 2}]) ==
               ["CMS.INCRBY", "cms", "a", "1", "b", "2"]
    end
  end

  describe "QUERY" do
    test "basic" do
      assert CMS.query("cms", ["a", "b"]) == ["CMS.QUERY", "cms", "a", "b"]
    end
  end

  describe "MERGE" do
    test "without weights" do
      assert CMS.merge("dest", ["s1", "s2"]) == ["CMS.MERGE", "dest", "2", "s1", "s2"]
    end

    test "with weights" do
      assert CMS.merge("dest", ["s1", "s2"], weights: [1, 2]) ==
               ["CMS.MERGE", "dest", "2", "s1", "s2", "WEIGHTS", "1", "2"]
    end
  end

  describe "INFO" do
    test "basic" do
      assert CMS.info("cms") == ["CMS.INFO", "cms"]
    end
  end
end

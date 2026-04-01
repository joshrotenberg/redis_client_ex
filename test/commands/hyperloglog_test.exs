defmodule Redis.Commands.HyperLogLogTest do
  use ExUnit.Case, async: true

  alias Redis.Commands.HyperLogLog

  describe "PFADD" do
    test "basic" do
      assert HyperLogLog.pfadd("hll", ["a", "b", "c"]) == ["PFADD", "hll", "a", "b", "c"]
    end
  end

  describe "PFCOUNT" do
    test "single key" do
      assert HyperLogLog.pfcount(["hll"]) == ["PFCOUNT", "hll"]
    end

    test "multiple keys" do
      assert HyperLogLog.pfcount(["hll1", "hll2"]) == ["PFCOUNT", "hll1", "hll2"]
    end
  end

  describe "PFMERGE" do
    test "basic" do
      assert HyperLogLog.pfmerge("dest", ["src1", "src2"]) ==
               ["PFMERGE", "dest", "src1", "src2"]
    end
  end
end

defmodule Redis.Commands.VectorSetTest do
  use ExUnit.Case, async: true

  alias Redis.Commands.VectorSet

  describe "VADD" do
    test "basic with vector" do
      assert VectorSet.vadd("vs", "item1", [1.0, 2.0, 3.0]) ==
               ["VADD", "vs", "item1", "VALUES", "3", "1.0", "2.0", "3.0"]
    end

    test "with reduce" do
      assert VectorSet.vadd("vs", "item1", [1.0, 2.0, 3.0], reduce: 2) ==
               ["VADD", "vs", "REDUCE", "2", "item1", "VALUES", "3", "1.0", "2.0", "3.0"]
    end

    test "with quantization q8" do
      assert VectorSet.vadd("vs", "item1", [1.0, 2.0], quantization: :q8) ==
               ["VADD", "vs", "QUANTIZATION", "Q8", "item1", "VALUES", "2", "1.0", "2.0"]
    end

    test "with quantization bin" do
      assert VectorSet.vadd("vs", "item1", [1.0, 2.0], quantization: :bin) ==
               ["VADD", "vs", "QUANTIZATION", "BIN", "item1", "VALUES", "2", "1.0", "2.0"]
    end

    test "with quantization noquant" do
      assert VectorSet.vadd("vs", "item1", [1.0, 2.0], quantization: :noquant) ==
               ["VADD", "vs", "QUANTIZATION", "NOQUANT", "item1", "VALUES", "2", "1.0", "2.0"]
    end

    test "with ef" do
      assert VectorSet.vadd("vs", "item1", [1.0, 2.0], ef: 200) ==
               ["VADD", "vs", "EF", "200", "item1", "VALUES", "2", "1.0", "2.0"]
    end

    test "with setattr" do
      json = ~s({"color":"red"})

      assert VectorSet.vadd("vs", "item1", [1.0, 2.0], setattr: json) ==
               ["VADD", "vs", "SETATTR", json, "item1", "VALUES", "2", "1.0", "2.0"]
    end

    test "with cas" do
      assert VectorSet.vadd("vs", "item1", [1.0, 2.0], cas: 42) ==
               ["VADD", "vs", "CAS", "42", "item1", "VALUES", "2", "1.0", "2.0"]
    end

    test "with multiple options" do
      cmd = VectorSet.vadd("vs", "item1", [1.0, 2.0, 3.0], reduce: 2, quantization: :q8, ef: 100)

      assert cmd ==
               [
                 "VADD",
                 "vs",
                 "REDUCE",
                 "2",
                 "QUANTIZATION",
                 "Q8",
                 "EF",
                 "100",
                 "item1",
                 "VALUES",
                 "3",
                 "1.0",
                 "2.0",
                 "3.0"
               ]
    end
  end

  describe "VREM" do
    test "basic" do
      assert VectorSet.vrem("vs", "item1") == ["VREM", "vs", "item1"]
    end
  end

  describe "VCARD" do
    test "basic" do
      assert VectorSet.vcard("vs") == ["VCARD", "vs"]
    end
  end

  describe "VDIM" do
    test "basic" do
      assert VectorSet.vdim("vs") == ["VDIM", "vs"]
    end
  end

  describe "VEMB" do
    test "basic" do
      assert VectorSet.vemb("vs", "item1") == ["VEMB", "vs", "item1"]
    end

    test "with raw" do
      assert VectorSet.vemb("vs", "item1", raw: true) == ["VEMB", "vs", "item1", "RAW"]
    end
  end

  describe "VGETATTR" do
    test "basic" do
      assert VectorSet.vgetattr("vs", "item1") == ["VGETATTR", "vs", "item1"]
    end
  end

  describe "VSETATTR" do
    test "basic" do
      json = ~s({"color":"blue"})
      assert VectorSet.vsetattr("vs", "item1", json) == ["VSETATTR", "vs", "item1", json]
    end
  end

  describe "VRANDMEMBER" do
    test "basic" do
      assert VectorSet.vrandmember("vs") == ["VRANDMEMBER", "vs"]
    end

    test "with count" do
      assert VectorSet.vrandmember("vs", count: 5) == ["VRANDMEMBER", "vs", "5"]
    end
  end

  describe "VSIM" do
    test "search by element" do
      assert VectorSet.vsim("vs", {:element, "item1"}) == ["VSIM", "vs", "ELE", "item1"]
    end

    test "search by vector" do
      assert VectorSet.vsim("vs", {:vector, [1.0, 2.0, 3.0]}) ==
               ["VSIM", "vs", "VALUES", "3", "1.0", "2.0", "3.0"]
    end

    test "with count" do
      assert VectorSet.vsim("vs", {:element, "item1"}, count: 10) ==
               ["VSIM", "vs", "ELE", "item1", "COUNT", "10"]
    end

    test "with ef" do
      assert VectorSet.vsim("vs", {:element, "item1"}, ef: 200) ==
               ["VSIM", "vs", "ELE", "item1", "EF", "200"]
    end

    test "with filter" do
      assert VectorSet.vsim("vs", {:element, "item1"}, filter: ".year > 2000") ==
               ["VSIM", "vs", "ELE", "item1", "FILTER", ".year > 2000"]
    end

    test "with filter_ef" do
      assert VectorSet.vsim("vs", {:element, "item1"}, filter_ef: 50) ==
               ["VSIM", "vs", "ELE", "item1", "FILTER-EF", "50"]
    end

    test "with truth" do
      assert VectorSet.vsim("vs", {:element, "item1"}, truth: true) ==
               ["VSIM", "vs", "ELE", "item1", "TRUTH"]
    end

    test "with nothread" do
      assert VectorSet.vsim("vs", {:element, "item1"}, nothread: true) ==
               ["VSIM", "vs", "ELE", "item1", "NOTHREAD"]
    end

    test "with withscores" do
      assert VectorSet.vsim("vs", {:element, "item1"}, withscores: true) ==
               ["VSIM", "vs", "ELE", "item1", "WITHSCORES"]
    end

    test "with multiple options" do
      cmd =
        VectorSet.vsim("vs", {:vector, [1.0, 2.0]},
          count: 5,
          ef: 100,
          filter: ".active == true",
          withscores: true
        )

      assert cmd ==
               [
                 "VSIM",
                 "vs",
                 "VALUES",
                 "2",
                 "1.0",
                 "2.0",
                 "COUNT",
                 "5",
                 "EF",
                 "100",
                 "FILTER",
                 ".active == true",
                 "WITHSCORES"
               ]
    end
  end

  describe "VINFO" do
    test "basic" do
      assert VectorSet.vinfo("vs") == ["VINFO", "vs"]
    end
  end

  describe "VLINKS" do
    test "basic" do
      assert VectorSet.vlinks("vs", "item1") == ["VLINKS", "vs", "item1"]
    end

    test "with withscores" do
      assert VectorSet.vlinks("vs", "item1", withscores: true) ==
               ["VLINKS", "vs", "item1", "WITHSCORES"]
    end
  end
end

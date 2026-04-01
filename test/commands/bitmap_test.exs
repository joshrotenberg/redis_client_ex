defmodule Redis.Commands.BitmapTest do
  use ExUnit.Case, async: true

  alias Redis.Commands.Bitmap

  describe "GETBIT" do
    test "basic" do
      assert Bitmap.getbit("key", 7) == ["GETBIT", "key", "7"]
    end
  end

  describe "SETBIT" do
    test "basic" do
      assert Bitmap.setbit("key", 7, 1) == ["SETBIT", "key", "7", "1"]
    end
  end

  describe "BITCOUNT" do
    test "without options" do
      assert Bitmap.bitcount("key") == ["BITCOUNT", "key"]
    end

    test "with start and end" do
      assert Bitmap.bitcount("key", start: 0, end: -1) == ["BITCOUNT", "key", "0", "-1"]
    end

    test "with BYTE unit" do
      assert Bitmap.bitcount("key", start: 0, end: 1, byte: true) ==
               ["BITCOUNT", "key", "0", "1", "BYTE"]
    end

    test "with BIT unit" do
      assert Bitmap.bitcount("key", start: 0, end: 7, bit: true) ==
               ["BITCOUNT", "key", "0", "7", "BIT"]
    end
  end

  describe "BITPOS" do
    test "without options" do
      assert Bitmap.bitpos("key", 1) == ["BITPOS", "key", "1"]
    end

    test "with start" do
      assert Bitmap.bitpos("key", 0, start: 2) == ["BITPOS", "key", "0", "2"]
    end

    test "with start, end, and BIT" do
      assert Bitmap.bitpos("key", 1, start: 0, end: 10, bit: true) ==
               ["BITPOS", "key", "1", "0", "10", "BIT"]
    end
  end

  describe "BITOP" do
    test "AND" do
      assert Bitmap.bitop("and", "dest", ["k1", "k2"]) == ["BITOP", "AND", "dest", "k1", "k2"]
    end

    test "OR" do
      assert Bitmap.bitop("or", "dest", ["k1", "k2"]) == ["BITOP", "OR", "dest", "k1", "k2"]
    end

    test "XOR" do
      assert Bitmap.bitop("xor", "dest", ["k1"]) == ["BITOP", "XOR", "dest", "k1"]
    end

    test "NOT" do
      assert Bitmap.bitop("not", "dest", ["k1"]) == ["BITOP", "NOT", "dest", "k1"]
    end
  end

  describe "BITFIELD" do
    test "basic" do
      assert Bitmap.bitfield("key", ["GET", "u8", "0"]) ==
               ["BITFIELD", "key", "GET", "u8", "0"]
    end
  end

  describe "BITFIELD_RO" do
    test "basic" do
      assert Bitmap.bitfield_ro("key", ["GET", "u8", "0"]) ==
               ["BITFIELD_RO", "key", "GET", "u8", "0"]
    end
  end
end

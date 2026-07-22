require "./spec_helper"

describe "TOON options" do
  describe "indent" do
    it "rejects non-positive values when encoding" do
      expect_raises(ArgumentError, "indent must be greater than 0") do
        Toon.encode({"key" => "value"}, indent: 0)
      end
    end

    it "rejects non-positive values when decoding" do
      expect_raises(ArgumentError, "indent must be greater than 0") do
        Toon.decode("key: value", indent: -1)
      end
    end
  end

  describe "delimiter" do
    it "rejects an empty string" do
      expect_raises(ArgumentError, "delimiter must be comma, tab, or pipe") do
        Toon.encode([1, 2], delimiter: "")
      end
    end

    it "rejects an unsupported character" do
      expect_raises(ArgumentError, "delimiter must be comma, tab, or pipe") do
        Toon.encode([1, 2], delimiter: ';')
      end
    end
  end
end

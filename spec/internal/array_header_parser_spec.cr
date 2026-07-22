require "../spec_helper"

module Toon
  module Decoders
    def self.spec_parse_array_header_line(content : String)
      parse_array_header_line(content)
    end
  end
end

describe "TOON decode array header parser" do
  it "parses a basic array header" do
    parsed = Toon::Decoders.spec_parse_array_header_line("users[2]:")
    parsed.should_not be_nil

    header, inline_values = parsed.not_nil!
    header.key.should eq("users")
    header.length.should eq(2)
    header.delimiter.should eq(",")
    header.fields.should be_nil
    inline_values.should be_nil
  end

  it "parses a quoted key and inline values" do
    parsed = Toon::Decoders.spec_parse_array_header_line(%("user.name"[3|]{id|name}: 1|2|3))
    parsed.should_not be_nil

    header, inline_values = parsed.not_nil!
    header.key.should eq("user.name")
    header.length.should eq(3)
    header.delimiter.should eq("|")
    header.fields.should eq(["id", "name"])
    inline_values.should eq("1|2|3")
  end

  it "returns nil for non headers" do
    Toon::Decoders.spec_parse_array_header_line("plain:value").should be_nil
  end
end

require "../spec_helper"

module Toon
  module Decoders
    def self.spec_parse_primitive_token(token : String) : JsonValue
      parse_primitive_token(token)
    end

    def self.spec_parse_string_literal(raw : String) : String
      parse_string_literal(raw)
    end
  end
end

describe "TOON decode string parser" do
  it "parses primitive literals" do
    Toon::Decoders.spec_parse_primitive_token("null").should be_nil
    Toon::Decoders.spec_parse_primitive_token("true").should be_true
    Toon::Decoders.spec_parse_primitive_token("false").should be_false
    Toon::Decoders.spec_parse_primitive_token("42").should eq(42_i64)
    Toon::Decoders.spec_parse_primitive_token("-3.5").should eq(-3.5)
    Toon::Decoders.spec_parse_primitive_token("05").should eq("05")
  end

  it "parses escaped string literals" do
    Toon::Decoders.spec_parse_string_literal(%("line\nnext\t\u0041")).should eq("line\nnext\tA")
  end

  it "rejects invalid escape sequences" do
    bad_escape = String.build do |io|
      io << '"'
      io << "bad"
      io << '\\'
      io << 'u'
      io << '1'
      io << '2'
      io << '"'
    end

    expect_raises(Toon::DecodeError) do
      Toon::Decoders.spec_parse_string_literal(bad_escape)
    end
  end
end

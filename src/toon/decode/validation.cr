module Toon
  module Decoders
    private def validate_malformed_array_header_strict!(content : String, strict : Bool)
      return unless strict

      colon_idx = find_unquoted_colon_index(content)
      return unless colon_idx

      bracket_idx = find_unquoted_char_index(content, '[')
      return unless bracket_idx && bracket_idx < colon_idx
      parsed = parse_array_header_line(content)
      unless parsed && parsed[0].length >= 0
        raise DecodeError.new("Invalid array header syntax")
      end
    end

    private def assert_expected_count(actual : Int32, expected : Int32, what : String)
      if actual != expected
        raise DecodeError.new("Expected #{expected} #{what}, got #{actual}")
      end
    end
  end
end

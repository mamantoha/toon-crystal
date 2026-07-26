module Toon
  module Decoders
    private def validate_malformed_array_header_strict!(content : String, strict : Bool)
      return unless strict

      colon_idx = find_unquoted_colon_index(content)
      return unless colon_idx

      header_part = content[0, colon_idx]
      bracket_idx = find_unquoted_char_index(header_part, '[')
      return unless bracket_idx
      prefix = header_part[0, bracket_idx]
      raise DecodeError.new("Invalid array header syntax") if !prefix.empty? && prefix[-1].ascii_whitespace?

      close_idx = header_part.index(']', bracket_idx + 1)
      return unless close_idx

      inside = header_part[bracket_idx + 1, close_idx - bracket_idx - 1]
      suffix = header_part[close_idx + 1, header_part.size - close_idx - 1]

      if suffix.empty?
        validate_array_header_bracket_segment!(inside)
        return
      end

      if suffix.starts_with?('{') && suffix.ends_with?('}')
        validate_array_header_bracket_segment!(inside)
        delimiter = array_header_delimiter(inside)
        fields = suffix[1, suffix.size - 2]
        if contains_inactive_delimiter?(fields, delimiter)
          raise DecodeError.new("Invalid array header syntax")
        end
        return
      end

      raise DecodeError.new("Invalid array header syntax")
    end

    private def validate_array_header_bracket_segment!(segment : String)
      length = segment

      if length.size > 0
        last = length[-1]

        if delimiter_char?(last)
          length = length.byte_slice(0, length.size - 1)
        elsif !last.ascii_number?
          raise DecodeError.new("Invalid array header syntax")
        end
      end

      unless length =~ /^(0|[1-9]\d*)$/
        raise DecodeError.new("Invalid array header syntax")
      end
    end

    private def array_header_delimiter(segment : String) : String
      return PIPE.to_s if segment.ends_with?(PIPE)
      return TAB.to_s if segment.ends_with?(TAB)

      DEFAULT_DELIMITER.to_s
    end

    private def assert_expected_count(actual : Int32, expected : Int32, what : String)
      if actual != expected
        raise DecodeError.new("Expected #{expected} #{what}, got #{actual}")
      end
    end
  end
end

require "../constants"
require "./error"
require "./line_cursor"
require "./array_header_parser"
require "./string_parser"
require "./object_parser"
require "./collection_parser"
require "./validation"

module Toon
  module Decoders
    extend self

    # decode TOON string into Crystal JSON-like values
    def decode_value(input : String, indent : Int32 = 2, strict : Bool = true) : JsonValue
      input = input.byte_slice(3, input.bytesize - 3) if input.starts_with?('\uFEFF')
      lines, blanks = tokenize_lines(input, indent, strict)
      cursor = LineCursor.new(lines, blanks)
      value = decode_value_from_lines(cursor, delimiter: DEFAULT_DELIMITER.to_s, strict: strict)
      raise DecodeError.new("Unexpected trailing content") if strict && !cursor.at_end?
      value
    end

    private def tokenize_lines(input : String, indent : Int32, strict : Bool) : {Array(ParsedLine), Array(Int32)}
      result = [] of ParsedLine
      blank_lines = [] of Int32

      input.each_line.with_index do |raw, i|
        line_number = i + 1
        raw = raw.chomp('\n').chomp('\r').rstrip(' ')

        # Comments are removed lexically before blank-line and indentation
        # processing. Only U+0020 space may precede the marker.
        next if raw.lstrip(' ').starts_with?('#')

        if raw.strip.empty?
          blank_lines << line_number
          next
        end

        leading_len = 0

        while leading_len < raw.size && (raw[leading_len] == ' ' || raw[leading_len] == '\t')
          leading_len += 1
        end

        leading = raw[0, leading_len]

        if strict
          if leading.includes?('\t')
            raise DecodeError.new("indentation error: tab character not allowed")
          end

          if leading.size % indent != 0
            raise DecodeError.new("indentation error: indentation must be an exact multiple of #{indent}")
          end
        end

        spaces_count = leading.gsub(/\t+/, "").size
        depth = (spaces_count // indent).to_i
        content = raw.byte_slice(leading_len)
        result << ParsedLine.new(depth, content, line_number)
      end

      {result, blank_lines}
    end

    private def decode_value_from_lines(cursor : LineCursor, delimiter : String, strict : Bool) : JsonValue
      first = cursor.peek
      return {} of String => JsonValue unless first

      if cursor.length == 1 && first.content.strip == "[]"
        cursor.advance
        return [] of JsonValue
      end

      if parsed = parse_array_header_line(first.content)
        header, inline_values = parsed

        unless header.key
          cursor.advance
          return decode_array_from_header(header, inline_values, cursor, first.depth, delimiter, strict)
        end
      end

      if colon_idx = find_unquoted_colon_index(first.content)
        header_candidate = first.content[0, colon_idx + 1]

        if parsed = parse_array_header_line(header_candidate)
          header, _ = parsed

          unless header.key
            inline_values = first.content[colon_idx + 1, first.content.size - colon_idx - 1]
            cursor.advance
            return decode_array_from_header(header, inline_values, cursor, first.depth, delimiter, strict)
          end
        end
      end

      if cursor.length == 1 && !key_value_line?(first.content)
        cursor.advance
        return parse_primitive_token(first.content)
      end

      decode_object(cursor, first.depth, delimiter, strict)
    end
  end
end

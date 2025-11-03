require "../constants"
require "./error"

module Toon
  # Lightweight line representation for decoding
  struct ParsedLine
    getter depth : Int32
    getter content : String
    getter line_number : Int32

    def initialize(@depth : Int32, @content : String, @line_number : Int32)
    end
  end

  # Cursor over parsed lines
  class LineCursor
    @lines : Array(ParsedLine)
    @index : Int32 = 0
    @current_line : ParsedLine?
    @blank_lines : Array(Int32)

    def initialize(@lines : Array(ParsedLine), @blank_lines : Array(Int32))
    end

    def length : Int32
      @lines.size
    end

    def at_end? : Bool
      @index >= @lines.size
    end

    def peek : ParsedLine?
      @lines[@index]?
    end

    def next : ParsedLine?
      line = @lines[@index]?

      if line
        @current_line = line
        @index += 1
      end

      line
    end

    def advance
      self.next
    end

    def current : ParsedLine?
      @current_line
    end

    def blank_lines : Array(Int32)
      @blank_lines
    end
  end

  module Decoders
    extend self

    alias JsonValue = (Nil | Bool | Int64 | Float64 | String | Array(JsonValue) | Hash(String, JsonValue))

    # Internal representation of an array header
    struct ArrayHeader
      property key : String?
      property length : Int32
      property delimiter : String
      property fields : Array(String)?

      def initialize(@key : String?, @length : Int32, @delimiter : String, @fields : Array(String)?)
      end
    end

    # decode TOON string into Crystal JSON-like values
    def decode_value(input : String, indent : Int32 = 2, strict : Bool = true) : JsonValue
      lines, blanks = tokenize_lines(input, indent, strict)
      cursor = LineCursor.new(lines, blanks)
      decode_value_from_lines(cursor, delimiter: DEFAULT_DELIMITER.to_s, strict: strict)
    end

    private def tokenize_lines(input : String, indent : Int32, strict : Bool) : {Array(ParsedLine), Array(Int32)}
      result = [] of ParsedLine
      blank_lines = [] of Int32

      input.each_line.with_index do |raw, i|
        line_number = i + 1

        if raw.strip.empty?
          blank_lines << line_number
          next
        end

        # Collect leading indentation characters
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

        # Non-strict: ignore tabs when counting indent (treat as zero-width)
        spaces_count = leading.gsub(/\t+/, "").size
        depth = (spaces_count // indent).to_i
        content = raw.lstrip
        result << ParsedLine.new(depth, content, line_number)
      end

      {result, blank_lines}
    end

    private def decode_value_from_lines(cursor : LineCursor, delimiter : String, strict : Bool) : JsonValue
      first = cursor.peek
      raise DecodeError.new("No content to decode") unless first

      if parsed = parse_array_header_line(first.content)
        header, inline_values = parsed

        if header.key
          # Treat as object field; decode via object path to allow following fields
        else
          cursor.advance
          value = decode_array_from_header(header, inline_values, cursor, first.depth, delimiter, strict)

          return value
        end
      end

      # Fallback: try parsing header segment up to first unquoted colon
      if colon_idx = find_unquoted_colon_index(first.content)
        header_candidate = first.content[0, colon_idx + 1]

        if parsed2 = parse_array_header_line(header_candidate)
          header2, _ = parsed2

          if header2.key
            # Object path
          else
            inline_values = first.content[colon_idx + 1, first.content.size - (colon_idx + 1)]
            cursor.advance
            value = decode_array_from_header(header2, inline_values, cursor, first.depth, delimiter, strict)

            return value
          end
        end
      end

      if cursor.length == 1 && !key_value_line?(first.content)
        return parse_primitive_token(first.content)
      end

      decode_object(cursor, first.depth, delimiter, strict)
    end

    private def decode_object(cursor : LineCursor, base_depth : Int32, delimiter : String, strict : Bool) : Hash(String, JsonValue)
      obj = {} of String => JsonValue

      until cursor.at_end?
        line = cursor.peek

        break unless line && line.depth >= base_depth

        if line.depth == base_depth
          key, value = decode_key_value_pair(line, cursor, base_depth, delimiter, strict)
          obj[key] = value
        else
          break
        end
      end

      obj
    end

    private def decode_key_value_pair(line : ParsedLine, cursor : LineCursor, base_depth : Int32, delimiter : String, strict : Bool) : {String, JsonValue}
      cursor.advance
      key, value, _follow = decode_key_value(line.content, cursor, base_depth, delimiter, strict)

      {key, value}
    end

    private def decode_key_value(content : String, cursor : LineCursor, base_depth : Int32, delimiter : String, strict : Bool) : {String, JsonValue, Int32}
      # Array header with key
      if parsed = parse_array_header_line(content)
        header, inline_values = parsed

        if header.key
          value = decode_array_from_header(header, inline_values, cursor, base_depth, delimiter, strict)

          return {header.key.to_s, value, base_depth + 1}
        end
      end

      # Fallback: try parsing header segment up to first unquoted colon
      if colon_idx = find_unquoted_colon_index(content)
        header_candidate = content[0, colon_idx + 1]

        if parsed2 = parse_array_header_line(header_candidate)
          header2, _ = parsed2

          if header2.key
            inline_values = content[colon_idx + 1, content.size - (colon_idx + 1)]
            value = decode_array_from_header(header2, inline_values, cursor, base_depth, delimiter, strict)

            return {header2.key.to_s, value, base_depth + 1}
          end
        end
      end

      key, rest = parse_key_token(content)
      rest = rest.strip

      if rest.empty?
        next_line = cursor.peek

        if next_line && next_line.depth > base_depth
          # For nested objects: decode at the correct depth
          # In list items (base_depth is list item depth), nested objects are at +2
          # In regular objects (base_depth is object depth), nested objects are at +1
          # We detect list item context by checking if the previous token was after "- "
          # For now, use the next_line's depth to determine nesting depth
          nested_depth = next_line.depth
          nested = decode_object(cursor, nested_depth, delimiter, strict)
          # Return depth for subsequent fields
          return {key, nested, nested_depth}
        end

        return {key, {} of String => JsonValue, base_depth + 1}
      end

      {key, parse_primitive_token(rest), base_depth + 1}
    end

    private def decode_array_from_header(header : ArrayHeader, inline_values : String?, cursor : LineCursor, base_depth : Int32, default_delim : String, strict : Bool) : Array(JsonValue)
      active_delim = header.delimiter || default_delim

      if inline_values && !inline_values.strip.empty?
        values = parse_delimited_values(inline_values, active_delim)
        primitives = values.map { |v| parse_primitive_token(v) }
        assert_expected_count(primitives.size, header.length, "inline array items")

        return primitives.map { |v| v.as(JsonValue) }
      end

      if header.fields
        return decode_tabular_array(header, cursor, base_depth, active_delim, strict)
      end

      decode_list_array(header, cursor, base_depth, active_delim, strict)
    end

    private def decode_list_array(header : ArrayHeader, cursor : LineCursor, base_depth : Int32, delimiter : String, strict : Bool) : Array(JsonValue)
      items = [] of JsonValue
      item_depth = base_depth + 1
      start_line : Int32? = nil
      end_line : Int32? = nil

      while !cursor.at_end? && items.size < header.length
        line = cursor.peek

        break unless line && line.depth >= item_depth

        # Handle both "- " (with space) and "-" (empty item)
        if line.depth == item_depth && (line.content.starts_with?(LIST_ITEM_PREFIX) || line.content == "-")
          start_line = line.line_number if start_line.nil?
          items << decode_list_item(cursor, item_depth, delimiter, strict)
          current = cursor.current
          end_line = current.line_number if current
        else
          break
        end
      end

      assert_expected_count(items.size, header.length, "list array items")

      # strict: blank lines inside the array are not allowed
      if strict && start_line && end_line
        blanks = cursor.blank_lines

        blanks.each do |ln|
          if ln >= start_line && ln <= end_line
            raise DecodeError.new("blank line inside list array")
          end
        end
      end

      if strict
        line = cursor.peek

        if line && line.depth == item_depth && line.content.starts_with?(LIST_ITEM_PREFIX)
          raise DecodeError.new("Unexpected extra list array items")
        end
      end

      items
    end

    private def decode_tabular_array(header : ArrayHeader, cursor : LineCursor, base_depth : Int32, delimiter : String, strict : Bool) : Array(JsonValue)
      objects = [] of JsonValue
      row_depth = base_depth + 1
      fields = header.fields
      start_line : Int32? = nil
      end_line : Int32? = nil

      while !cursor.at_end? && objects.size < header.length
        line = cursor.peek

        break unless line && line.depth >= row_depth

        if line.depth == row_depth
          start_line = line.line_number if start_line.nil?
          cursor.advance
          values = parse_delimited_values(line.content, delimiter)
          assert_expected_count(values.size, fields.try(&.size) || 0, "tabular row values")
          primitives = values.map { |v| parse_primitive_token(v) }
          obj = {} of String => JsonValue
          fields.try(&.each_with_index { |k, i| obj[k] = primitives[i] })
          objects << obj.as(JsonValue)
          current = cursor.current
          end_line = current.line_number if current
        else
          break
        end
      end

      assert_expected_count(objects.size, header.length, "tabular rows")

      # strict: blank lines inside the array are not allowed
      if strict && start_line && end_line
        blanks = cursor.blank_lines
        blanks.each do |ln|
          if ln >= start_line && ln <= end_line
            raise DecodeError.new("blank line inside tabular array")
          end
        end
      end

      if strict
        line = cursor.peek
        if line && line.depth == row_depth
          # Only raise if it's truly another row (not a following key/value field)
          unless key_value_line?(line.content) || line.content.starts_with?(LIST_ITEM_PREFIX)
            raise DecodeError.new("Unexpected extra tabular rows")
          end
        end
      end

      objects
    end

    private def decode_list_item(cursor : LineCursor, base_depth : Int32, delimiter : String, strict : Bool) : JsonValue
      line = cursor.next

      raise DecodeError.new("Expected list item") unless line

      # Handle both "- " and "-" (empty item)
      if line.content == "-"
        return {} of String => JsonValue
      end

      after_hyphen = line.content.byte_slice(LIST_ITEM_PREFIX.size)

      # Empty list item (just "- " with nothing after) should be an empty object
      if after_hyphen.strip.empty?
        return {} of String => JsonValue
      end

      # Only treat as header when list item starts directly with '[' (no key)
      if after_hyphen.lstrip.starts_with?('[')
        if parsed = parse_array_header_line(after_hyphen)
          header, inline_values = parsed

          return decode_array_from_header(header, inline_values, cursor, base_depth, delimiter, strict)
        end
      end

      if object_field_after_hyphen?(after_hyphen)
        return decode_object_from_list_item(line, cursor, base_depth, delimiter, strict)
      end

      parse_primitive_token(after_hyphen)
    end

    private def decode_object_from_list_item(first_line : ParsedLine, cursor : LineCursor, base_depth : Int32, delimiter : String, strict : Bool) : Hash(String, JsonValue)
      after_hyphen = first_line.content.byte_slice(LIST_ITEM_PREFIX.size)
      key, value, follow = decode_key_value(after_hyphen, cursor, base_depth, delimiter, strict)
      obj = {key => value} of String => JsonValue

      # If the first field was a nested object (- key:), nested fields are at +2, subsequent fields at +1
      # follow_depth is the depth returned by decode_key_value for nested objects
      # For list items: if first field is nested object, follow = base_depth + 2; subsequent fields = base_depth + 1
      subsequent_depth = base_depth + 1

      until cursor.at_end?
        line = cursor.peek

        # Check if this is a subsequent field of the same list item (at base_depth + 1)
        # or if it's a nested field of the first field's object (at follow depth, which would be base_depth + 2)
        # We want to stop when we hit the next list item or a field at the wrong depth
        break unless line && (line.depth == subsequent_depth || line.depth == follow)

        # Stop if it's the next list item
        break if line.depth == subsequent_depth && line.content.starts_with?(LIST_ITEM_PREFIX)

        # Process as a subsequent field of this list item
        if line.depth == subsequent_depth && !line.content.starts_with?(LIST_ITEM_PREFIX)
          k, v = decode_key_value_pair(line, cursor, subsequent_depth, delimiter, strict)
          obj[k] = v
        else
          # This shouldn't happen - nested fields should already be handled in decode_key_value
          break
        end
      end

      obj
    end

    # --- Parsing helpers ---
    private def key_value_line?(content : String) : Bool
      # detect a colon outside of quotes
      i = 0
      in_quotes = false
      escaped = false

      while i < content.size
        ch = content[i]

        if in_quotes
          if !escaped && ch == '"'
            in_quotes = false
          end
          escaped = (!escaped && ch == '\\')
        else
          return true if ch == ':'
          in_quotes = true if ch == '"'
        end
        i += 1
      end

      false
    end

    private def find_unquoted_colon_index(content : String) : Int32?
      i = 0
      in_quotes = false
      escaped = false

      while i < content.size
        ch = content[i]
        if in_quotes
          if !escaped && ch == '"'
            in_quotes = false
          end
          escaped = (!escaped && ch == '\\')
        else
          return i if ch == ':'
          in_quotes = true if ch == '"'
        end
        i += 1
      end
      nil
    end

    private def parse_key_token(content : String) : {String, String}
      # returns key and remainder after colon
      i = 0
      in_quotes = false
      escaped = false

      while i < content.size
        ch = content[i]
        if in_quotes
          if !escaped && ch == '"'
            in_quotes = false
          end
          escaped = (!escaped && ch == '\\')
        else
          if ch == ':'
            key = content[0, i]
            rest = content[i + 1, content.size - (i + 1)]
            return {parse_key_token_value(key.strip), rest}
          end
          in_quotes = true if ch == '"'
        end
        i += 1
      end

      raise DecodeError.new("Invalid key-value line: #{content}")
    end

    private def parse_key_token_value(raw : String) : String
      if raw.starts_with?(DOUBLE_QUOTE)
        parse_string_literal(raw)
      else
        raw
      end
    end

    private def parse_primitive_token(token : String) : JsonValue
      str = token.strip
      return nil if str == NULL_LITERAL
      return true if str == TRUE_LITERAL
      return false if str == FALSE_LITERAL

      if str.starts_with?(DOUBLE_QUOTE)
        return parse_string_literal(str)
      end

      # number?
      if str.match(/^[-+]?(?:\d+\.\d*|\d*\.\d+|\d+)(?:[eE][+-]?\d+)?$/)
        if str.match(/^[-+]?\d+$/)
          s = str
          s = s.byte_slice(1) if s.starts_with?('+') || s.starts_with?('-')

          # leading zeros (e.g., 05) are treated as strings
          return str if s.size > 1 && s.starts_with?('0')
          return str.to_i64
        end

        return str.to_f64
      end

      # bare string
      str
    end

    private def parse_string_literal(raw : String) : String
      s = raw.strip

      # Must start and end with quotes
      unless s.starts_with?(DOUBLE_QUOTE)
        return s
      end

      raise DecodeError.new("Unterminated string: missing closing quote") unless s.ends_with?(DOUBLE_QUOTE)

      inner = s[1, s.size - 2]

      # unescape with validation
      result = String.build do |io|
        i = 0
        while i < inner.size
          ch = inner[i]
          if ch == '\\'
            raise DecodeError.new("Unterminated escape sequence") if i + 1 >= inner.size
            nxt = inner[i + 1]
            case nxt
            when 'n'  then io << '\n'
            when 'r'  then io << '\r'
            when 't'  then io << '\t'
            when '"'  then io << '"'
            when '\\' then io << '\\'
            else
              raise DecodeError.new("Invalid escape sequence: \\#{nxt}")
            end
            i += 2
          else
            io << ch
            i += 1
          end
        end
      end
      result
    end

    private def parse_array_header_line(content : String) : {ArrayHeader, String?}?
      # pattern: optional key, then [#?len<opt delim>]{<opt fields>}:<opt inline>
      trimmed = content.lstrip

      # Check if this is just a quoted string (not a quoted key with array header)
      # A quoted key with array header would have '[' after the closing quote
      if trimmed.starts_with?(DOUBLE_QUOTE)
        # Find the closing quote
        quote_end = trimmed.index(DOUBLE_QUOTE, 1)
        if quote_end
          # Check if there's a '[' after the quoted section
          after_quote = trimmed.byte_slice(quote_end + 1).lstrip
          return nil unless after_quote.starts_with?('[')
        else
          # Unterminated quote, not an array header
          return nil
        end
      end

      key : String? = nil
      rest = content

      # Find the first unquoted '[' (not inside quotes)
      idx = nil
      in_quotes = false
      escaped = false
      i = 0
      while i < rest.size
        ch = rest[i]
        if in_quotes
          if !escaped && ch == '"'
            in_quotes = false
          end
          escaped = (!escaped && ch == '\\')
        else
          if ch == '['
            idx = i
            break
          end
          if ch == '"'
            in_quotes = true
          end
        end
        i += 1
      end

      # key can be quoted or unquoted up to '['
      if idx
        before = rest.byte_slice(0, idx).strip

        if !before.empty?
          key = before.starts_with?(DOUBLE_QUOTE) ? parse_string_literal(before) : before
        end

        rest = rest.byte_slice(idx)
      end

      # [#?len<opt delim>]...
      return nil unless rest.starts_with?('[')

      # find closing bracket
      bracket_start = 0
      bracket_end = rest.index(']', bracket_start)

      return nil unless bracket_end

      # look for optional fields braces
      search_start = bracket_end + 1
      brace_start = rest.index('{', bracket_end)

      if brace_start
        brace_end = rest.index('}', brace_start)
        return nil unless brace_end
        search_start = brace_end + 1
      end

      colon_idx = rest.index(':', search_start)

      return nil unless colon_idx

      header_seg = rest.byte_slice(0, colon_idx)
      tail = rest.byte_slice(colon_idx + 1)

      # strip [ and ]
      close_idx = header_seg.index(']') || (header_seg.size - 1)
      inside = header_seg.byte_slice(1, close_idx - 1)

      length_marker = inside.starts_with?('#')
      len_and_delim = length_marker ? inside.byte_slice(1) : inside
      len_str = len_and_delim
      delim : String? = nil

      if len_and_delim.size > 0
        # if last char is a non-digit, treat as delimiter override
        last = len_and_delim[-1]

        if !(last.ascii_number?)
          delim = last.to_s
          len_str = len_and_delim.byte_slice(0, len_and_delim.size - 1)
        end
      end

      length = len_str.strip.to_i

      fields : Array(String)? = nil
      brace_idx = header_seg.index('{')

      if brace_idx
        close_brace = header_seg.rindex('}')

        if close_brace && close_brace > brace_idx
          inside_fields = header_seg.byte_slice(brace_idx + 1, close_brace - brace_idx - 1)
          # fields are key-encoded; split respecting quotes using active delimiter (fallback COMMA)
          delim_for_fields = delim || DEFAULT_DELIMITER.to_s
          tokens = parse_delimited_values(inside_fields, delim_for_fields)
          fields = tokens.map { |f| f.starts_with?(DOUBLE_QUOTE) ? parse_string_literal(f) : f }
        end
      end

      header = ArrayHeader.new(key, length, (delim || DEFAULT_DELIMITER.to_s), fields)

      inline_values = tail.strip.empty? ? nil : tail.strip
      {header, inline_values}
    end

    private def object_field_after_hyphen?(after_hyphen : String) : Bool
      key_value_line?(after_hyphen)
    end

    # no longer used

    private def parse_delimited_values(values_str : String, delimiter : String) : Array(String)
      result = [] of String
      return result if values_str.empty?

      in_quotes = false
      escaped = false
      token_start = 0
      i = 0

      while i < values_str.size
        ch = values_str[i]
        if in_quotes
          if !escaped && ch == '"'
            in_quotes = false
          end
          escaped = (!escaped && ch == '\\')
        else
          if ch == '"'
            in_quotes = true
          elsif ch == delimiter[0]
            # delimiter match (single-char delimiters supported)
            result << values_str[token_start, i - token_start].strip
            token_start = i + 1
          end
        end
        i += 1
      end

      # last token
      result << values_str[token_start, values_str.size - token_start].strip

      result
    end

    private def assert_expected_count(actual : Int32, expected : Int32, what : String)
      if actual != expected
        raise DecodeError.new("Expected #{expected} #{what}, got #{actual}")
      end
    end
  end
end

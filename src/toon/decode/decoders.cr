require "../constants"
require "./error"
require "./line_cursor"
require "./array_header_parser"
require "./string_parser"

module Toon
  module Decoders
    extend self

    # decode TOON string into Crystal JSON-like values
    def decode_value(input : String, indent : Int32 = 2, strict : Bool = true) : JsonValue
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
        raw = raw.chomp('\n').chomp('\r')

        # Comments are removed lexically before blank-line and indentation
        # processing. Only U+0020 space may precede the marker.
        next if raw.lstrip(' ').starts_with?('#')

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
        content = raw.byte_slice(leading_len)
        result << ParsedLine.new(depth, content, line_number)
      end

      {result, blank_lines}
    end

    private def decode_value_from_lines(cursor : LineCursor, delimiter : String, strict : Bool) : JsonValue
      first = cursor.peek
      # Empty document decodes to empty object
      return {} of String => JsonValue unless first

      if cursor.length == 1 && first.content.strip == "[]"
        cursor.advance
        return [] of JsonValue
      end

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
        cursor.advance
        return parse_primitive_token(first.content)
      end

      decode_object(cursor, first.depth, delimiter, strict)
    end

    private def decode_object(cursor : LineCursor, base_depth : Int32, delimiter : String, strict : Bool) : JsonValue
      obj = {} of String => JsonValue

      until cursor.at_end?
        line = cursor.peek

        break unless line && line.depth >= base_depth

        if line.depth == base_depth
          key_token, value = decode_key_value_pair(line, cursor, base_depth, delimiter, strict)
          insert_key!(obj, key_token, value, strict)
        else
          break
        end
      end

      obj
    end

    private def decode_key_value_pair(line : ParsedLine, cursor : LineCursor, base_depth : Int32, delimiter : String, strict : Bool) : {KeyToken, JsonValue}
      cursor.advance
      key_token, value, _follow = decode_key_value(line.content, cursor, base_depth, delimiter, strict)

      {key_token, value}
    end

    private def decode_key_value(content : String, cursor : LineCursor, base_depth : Int32, delimiter : String, strict : Bool) : {KeyToken, JsonValue, Int32}
      validate_malformed_array_header_strict!(content, strict)

      # Array header with key
      if parsed = parse_array_header_line(content)
        header, inline_values = parsed

        if key_token = header.key_token
          value = decode_array_from_header(header, inline_values, cursor, base_depth, delimiter, strict)

          return {key_token, value, base_depth + 1}
        elsif strict
          raise DecodeError.new("Keyless array header in object field position")
        end
      end

      # Fallback: try parsing header segment up to first unquoted colon
      if colon_idx = find_unquoted_colon_index(content)
        header_candidate = content[0, colon_idx + 1]

        if parsed2 = parse_array_header_line(header_candidate)
          header2, _ = parsed2

          if key_token2 = header2.key_token
            inline_values = content[colon_idx + 1, content.size - (colon_idx + 1)]
            value = decode_array_from_header(header2, inline_values, cursor, base_depth, delimiter, strict)

            return {key_token2, value, base_depth + 1}
          end
        end
      end

      key_token, rest = parse_key_token(content)
      rest = trim_token_spaces(rest)

      if rest == "[]"
        return {key_token, [] of JsonValue, base_depth + 1}
      end

      if rest.empty?
        next_line = cursor.peek

        if next_line && next_line.depth > base_depth
          # For nested objects: decode at the correct depth
          # In list items (base_depth is list item depth), nested objects are at +2
          # In regular objects (base_depth is object depth), nested objects are at +1
          # We detect list item context by checking if the previous token was after "- "
          # For now, use the next_line's depth to determine nesting depth
          if strict && next_line.depth != base_depth + 1
            raise DecodeError.new("indentation error: depth jump")
          end
          nested_depth = next_line.depth
          nested = decode_object(cursor, nested_depth, delimiter, strict)
          # Return depth for subsequent fields
          return {key_token, nested, nested_depth}
        end

        return {key_token, {} of String => JsonValue, base_depth + 1}
      end

      {key_token, parse_primitive_token(rest), base_depth + 1}
    end

    private def decode_array_from_header(header : ArrayHeader, inline_values : String?, cursor : LineCursor, base_depth : Int32, default_delim : String, strict : Bool) : JsonValue
      active_delim = header.delimiter || default_delim

      if header.keyed?
        raise DecodeError.new("Inline content after keyed header") if inline_values
        return decode_keyed_object(header, cursor, base_depth, active_delim, strict)
      end

      if inline_values && !inline_values.strip.empty?
        raise DecodeError.new("Inline content after tabular header") if header.fields
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

      assert_expected_count(items.size, header.length, "list array items") if strict

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
      fields = header.fields || [] of FieldNode
      validate_unique_fields!(fields) if strict
      leaf_count = fields.sum(&.leaf_count)
      start_line : Int32? = nil
      end_line : Int32? = nil

      while !cursor.at_end? && objects.size < header.length
        line = cursor.peek

        break unless line && line.depth >= row_depth

        if line.depth == row_depth
          start_line = line.line_number if start_line.nil?
          cursor.advance
          values = parse_delimited_values(line.content, delimiter)
          assert_expected_count(values.size, leaf_count, "tabular row values")
          primitives = values.map { |v| parse_primitive_token(v) }
          obj = {} of String => JsonValue
          assign_field_values!(obj, fields, primitives, 0)
          objects << obj.as(JsonValue)
          current = cursor.current
          end_line = current.line_number if current
        else
          break
        end
      end

      assert_expected_count(objects.size, header.length, "tabular rows") if strict

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

    private def validate_unique_fields!(fields : Array(FieldNode))
      seen = Set(String).new
      fields.each do |field|
        raise DecodeError.new("Duplicate tabular field '#{field.name}'") if seen.includes?(field.name)
        seen << field.name
        if children = field.children
          validate_unique_fields!(children)
        end
      end
    end

    private def decode_keyed_object(header : ArrayHeader, cursor : LineCursor, base_depth : Int32, delimiter : String, strict : Bool) : Hash(String, JsonValue)
      object = {} of String => JsonValue
      fields = header.fields || [] of FieldNode
      validate_unique_fields!(fields) if strict
      leaf_count = fields.sum(&.leaf_count)
      row_depth = base_depth + 1
      start_line : Int32? = nil
      end_line : Int32? = nil
      count = 0

      while count < header.length
        line = cursor.peek
        break unless line && line.depth == row_depth
        start_line ||= line.line_number
        cursor.advance
        colon = find_unquoted_colon_index(line.content)
        raise DecodeError.new("Invalid keyed entry row") unless colon
        key = parse_key_token_value(trim_token_spaces(line.content[0, colon]))
        cell_text = trim_token_spaces(line.content[colon + 1, line.content.size - colon - 1])
        raise DecodeError.new("Keyed entry row has no cells") if cell_text.empty?
        values = parse_delimited_values(cell_text, delimiter)
        assert_expected_count(values.size, leaf_count, "keyed row values")
        row = {} of String => JsonValue
        assign_field_values!(row, fields, values.map { |v| parse_primitive_token(v) }, 0)
        raise DecodeError.new("Duplicate entry key '#{key.value}'") if strict && object.has_key?(key.value)
        object[key.value] = row
        count += 1
        end_line = line.line_number
      end

      assert_expected_count(count, header.length, "keyed rows") if strict
      if strict && start_line && end_line
        cursor.blank_lines.each do |line_number|
          raise DecodeError.new("blank line inside keyed object") if line_number >= start_line && line_number <= end_line
        end
      end
      object
    end

    private def assign_field_values!(object : Hash(String, JsonValue), fields : Array(FieldNode), values : Array(JsonValue), offset : Int32) : Int32
      index = offset
      fields.each do |field|
        if children = field.children
          child = {} of String => JsonValue
          index = assign_field_values!(child, children, values, index)
          object[field.name] = child
        else
          object[field.name] = values[index]
          index += 1
        end
      end
      index
    end

    private def decode_list_item(cursor : LineCursor, base_depth : Int32, delimiter : String, strict : Bool) : JsonValue
      line = cursor.next

      raise DecodeError.new("Expected list item") unless line

      # Handle both "- " and "-" (empty item). If the hyphen is alone but
      # followed by indented fields, treat it as the start of an object and
      # decode the nested object at the subsequent depth.
      if line.content == "-"
        next_line = cursor.peek
        if next_line && next_line.depth > base_depth
          return decode_object(cursor, next_line.depth, delimiter, strict)
        end

        return {} of String => JsonValue
      end

      after_hyphen = line.content.byte_slice(LIST_ITEM_PREFIX.size)

      # Empty list item (just "- " with nothing after) should be an empty object
      if after_hyphen.strip.empty?
        return {} of String => JsonValue
      end

      return [] of JsonValue if after_hyphen == "[]"

      # Only treat as header when list item starts directly with '[' (no key).
      # Pass an increased base depth so nested rows are parsed at the deeper
      # indentation level used when the header is on the hyphen line.
      if after_hyphen.lstrip.starts_with?('[')
        if parsed = parse_array_header_line(after_hyphen)
          header, inline_values = parsed

          if strict && header.key.nil? && (header.keyed? || header.fields)
            raise DecodeError.new("Keyless structured header cannot be a list item")
          end

          # If the header includes a key (e.g., "users[2]{...}:" on the hyphen
          # line) then rows are expected at base_depth + 2, so pass an
          # increased base_depth. For bare array headers (no key) the nested
          # items are list items at base_depth + 1, so pass the unchanged
          # base_depth.
          if header.key
            return decode_array_from_header(header, inline_values, cursor, base_depth + 1, delimiter, strict)
          else
            return decode_array_from_header(header, inline_values, cursor, base_depth, delimiter, strict)
          end
        end
      end

      if object_field_after_hyphen?(after_hyphen)
        return decode_object_from_list_item(line, cursor, base_depth, delimiter, strict)
      end

      parse_primitive_token(after_hyphen)
    end

    private def decode_object_from_list_item(first_line : ParsedLine, cursor : LineCursor, base_depth : Int32, delimiter : String, strict : Bool) : Hash(String, JsonValue)
      after_hyphen = first_line.content.byte_slice(LIST_ITEM_PREFIX.size)
      # When decoding the first field of a list-item object, treat array headers
      # as if they are nested one level deeper (the hyphen line contains the
      # header), so pass an increased base depth to `decode_key_value`.
      key_token, value, _follow = decode_key_value(after_hyphen, cursor, base_depth + 1, delimiter, strict)
      obj = {} of String => JsonValue
      insert_key!(obj, key_token, value, strict)

      # If the first field was a nested object (- key:), nested fields are at +2, subsequent fields at +1
      # follow_depth is the depth returned by decode_key_value for nested objects
      # For list items: if first field is nested object, follow = base_depth + 2; subsequent fields = base_depth + 1
      subsequent_depth = base_depth + 1

      until cursor.at_end?
        line = cursor.peek
        break unless line && line.depth == subsequent_depth
        break if line.content.starts_with?(LIST_ITEM_PREFIX)

        k_token, v = decode_key_value_pair(line, cursor, subsequent_depth, delimiter, strict)
        insert_key!(obj, k_token, v, strict)
      end

      obj
    end

    private def insert_key!(obj : Hash(String, JsonValue), token : KeyToken, value : JsonValue, strict : Bool)
      raise DecodeError.new("Duplicate key '#{token.value}'") if strict && obj.has_key?(token.value)
      obj[token.value] = value
    end

    private def parse_key_token(content : String) : {KeyToken, String}
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
            key_raw = content[0, i]
            rest = content[i + 1, content.size - (i + 1)]
            token = parse_key_token_value(key_raw.strip)
            return {token, rest}
          end
          in_quotes = true if ch == '"'
        end
        i += 1
      end

      raise DecodeError.new("Invalid key-value line: #{content}")
    end

    private def parse_key_token_value(raw : String) : KeyToken
      if raw.starts_with?(DOUBLE_QUOTE)
        KeyToken.new(parse_string_literal(raw))
      else
        KeyToken.new(raw)
      end
    end

    private def validate_malformed_array_header_strict!(content : String, strict : Bool)
      return unless strict

      colon_idx = find_unquoted_colon_index(content)
      return unless colon_idx

      header_part = content[0, colon_idx]

      bracket_idx = find_unquoted_char_index(header_part, '[')
      return unless bracket_idx

      close_idx = header_part.index(']', bracket_idx + 1)
      return unless close_idx

      inside = header_part[bracket_idx + 1, close_idx - bracket_idx - 1]
      suffix = header_part[close_idx + 1, header_part.size - (close_idx + 1)]

      if suffix.empty?
        validate_array_header_bracket_segment!(inside)
        return
      end

      if suffix.starts_with?('{') && suffix.ends_with?('}')
        validate_array_header_bracket_segment!(inside)
        return
      end

      raise DecodeError.new("Invalid array header syntax")
    end

    private def validate_array_header_bracket_segment!(segment : String)
      len_str = segment

      if len_str.size > 0
        last = len_str[-1]

        if delimiter_char?(last)
          len_str = len_str.byte_slice(0, len_str.size - 1)
        elsif !last.ascii_number?
          raise DecodeError.new("Invalid array header syntax")
        end
      end

      unless len_str =~ /^(0|[1-9]\d*)$/
        raise DecodeError.new("Invalid array header syntax")
      end
    end

    private def object_field_after_hyphen?(after_hyphen : String) : Bool
      key_value_line?(after_hyphen)
    end

    private def assert_expected_count(actual : Int32, expected : Int32, what : String)
      if actual != expected
        raise DecodeError.new("Expected #{expected} #{what}, got #{actual}")
      end
    end
  end
end

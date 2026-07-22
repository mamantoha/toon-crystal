module Toon
  module Decoders
    private def decode_array_from_header(header : ArrayHeader, inline_values : String?, cursor : LineCursor, base_depth : Int32, default_delimiter : String, strict : Bool) : JsonValue
      delimiter = header.delimiter || default_delimiter

      if header.keyed?
        raise DecodeError.new("Inline content after keyed header") if inline_values
        return decode_keyed_object(header, cursor, base_depth, delimiter, strict)
      end

      if inline_values && !inline_values.strip.empty?
        raise DecodeError.new("Inline content after tabular header") if header.fields
        values = parse_delimited_values(inline_values, delimiter)
        primitives = values.map { |value| parse_primitive_token(value) }
        assert_expected_count(primitives.size, header.length, "inline array items")
        return primitives.map(&.as(JsonValue))
      end

      if header.fields
        return decode_tabular_array(header, cursor, base_depth, delimiter, strict)
      end

      decode_list_array(header, cursor, base_depth, delimiter, strict)
    end

    private def decode_list_array(header : ArrayHeader, cursor : LineCursor, base_depth : Int32, delimiter : String, strict : Bool) : Array(JsonValue)
      items = [] of JsonValue
      item_depth = base_depth + 1
      start_line : Int32? = nil
      end_line : Int32? = nil

      while !cursor.at_end? && items.size < header.length
        line = cursor.peek
        break unless line && line.depth >= item_depth

        if line.depth == item_depth && (line.content.starts_with?(LIST_ITEM_PREFIX) || line.content == "-")
          start_line ||= line.line_number
          items << decode_list_item(cursor, item_depth, delimiter, strict)
          end_line = cursor.current.try(&.line_number)
        else
          break
        end
      end

      assert_expected_count(items.size, header.length, "list array items") if strict
      validate_no_blank_lines!(cursor, start_line, end_line, "list array") if strict

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
          start_line ||= line.line_number
          cursor.advance
          values = parse_delimited_values(line.content, delimiter)
          assert_expected_count(values.size, leaf_count, "tabular row values")
          object = {} of String => JsonValue
          assign_field_values!(object, fields, values.map { |value| parse_primitive_token(value) }, 0)
          objects << object.as(JsonValue)
          end_line = cursor.current.try(&.line_number)
        else
          break
        end
      end

      assert_expected_count(objects.size, header.length, "tabular rows") if strict
      validate_no_blank_lines!(cursor, start_line, end_line, "tabular array") if strict

      if strict
        line = cursor.peek
        if line && line.depth == row_depth
          unless key_value_line?(line.content) || line.content.starts_with?(LIST_ITEM_PREFIX)
            raise DecodeError.new("Unexpected extra tabular rows")
          end
        end
      end

      objects
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
        assign_field_values!(row, fields, values.map { |value| parse_primitive_token(value) }, 0)
        raise DecodeError.new("Duplicate entry key '#{key.value}'") if strict && object.has_key?(key.value)
        object[key.value] = row
        count += 1
        end_line = line.line_number
      end

      assert_expected_count(count, header.length, "keyed rows") if strict
      validate_no_blank_lines!(cursor, start_line, end_line, "keyed object") if strict
      object
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

    private def validate_no_blank_lines!(cursor : LineCursor, start_line : Int32?, end_line : Int32?, scope : String)
      return unless start_line && end_line

      cursor.blank_lines.each do |line_number|
        if line_number >= start_line && line_number <= end_line
          raise DecodeError.new("blank line inside #{scope}")
        end
      end
    end
  end
end

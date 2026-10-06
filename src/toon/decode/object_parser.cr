module Toon
  module Decoders
    private def decode_object(cursor : LineCursor, base_depth : Int32, delimiter : String, strict : Bool, parent_depth : Int32 = -1) : JsonValue
      object = {} of String => JsonValue

      until cursor.at_end?
        line = cursor.peek
        break unless line && line.depth > parent_depth

        if line.depth == base_depth
          key_token, value = decode_key_value_pair(line, cursor, base_depth, delimiter, strict)
          insert_key!(object, key_token, value, strict)
        else
          skip_orphan_line!(cursor, strict)
        end
      end

      object
    end

    private def decode_key_value_pair(line : ParsedLine, cursor : LineCursor, base_depth : Int32, delimiter : String, strict : Bool) : {KeyToken, JsonValue}
      cursor.advance
      key_token, value = decode_key_value(line.content, cursor, base_depth, delimiter, strict)
      {key_token, value}
    end

    private def decode_key_value(content : String, cursor : LineCursor, base_depth : Int32, delimiter : String, strict : Bool) : {KeyToken, JsonValue}
      validate_malformed_array_header_strict!(content, strict)

      if parsed = parse_array_header_line(content)
        header, inline_values = parsed

        if key_token = header.key_token
          value = decode_array_from_header(header, inline_values, cursor, base_depth, delimiter, strict)
          return {key_token, value}
        elsif strict
          raise DecodeError.new("Keyless array header in object field position")
        end
      end

      key_token, rest = parse_key_token(content)
      rest = trim_token_spaces(rest)

      return {key_token, [] of JsonValue} if rest == "[]"

      if rest.empty?
        next_line = cursor.peek

        if next_line && next_line.depth > base_depth
          if strict && next_line.depth != base_depth + 1
            raise DecodeError.new("indentation error: depth jump")
          end

          nested_depth = next_line.depth
          nested = decode_object(cursor, nested_depth, delimiter, strict, base_depth)
          return {key_token, nested}
        end

        return {key_token, {} of String => JsonValue}
      end

      {key_token, parse_primitive_token(rest)}
    end

    private def decode_list_item(cursor : LineCursor, base_depth : Int32, delimiter : String, strict : Bool) : JsonValue
      line = cursor.next
      raise DecodeError.new("Expected list item") unless line

      if line.content == "-"
        next_line = cursor.peek
        if next_line && next_line.depth > base_depth
          return decode_object(cursor, next_line.depth, delimiter, strict, base_depth)
        end

        return {} of String => JsonValue
      end

      after_hyphen = line.content.byte_slice(LIST_ITEM_PREFIX.size)
      return {} of String => JsonValue if after_hyphen.strip.empty?
      return [] of JsonValue if after_hyphen == "[]"

      validate_malformed_array_header_strict!(after_hyphen, strict)

      if after_hyphen.lstrip.starts_with?('[')
        if parsed = parse_array_header_line(after_hyphen)
          header, inline_values = parsed

          if header.key.nil? && (header.keyed? || header.fields)
            raise DecodeError.new("Keyless structured header cannot be a list item")
          end

          header_depth = header.key ? base_depth + 1 : base_depth
          return decode_array_from_header(header, inline_values, cursor, header_depth, delimiter, strict)
        end
      end

      if key_value_line?(after_hyphen)
        return decode_object_from_list_item(line, cursor, base_depth, delimiter, strict)
      end

      parse_primitive_token(after_hyphen)
    end

    private def decode_object_from_list_item(first_line : ParsedLine, cursor : LineCursor, base_depth : Int32, delimiter : String, strict : Bool) : Hash(String, JsonValue)
      after_hyphen = first_line.content.byte_slice(LIST_ITEM_PREFIX.size)
      key_token, value = decode_key_value(after_hyphen, cursor, base_depth + 1, delimiter, strict)
      object = {} of String => JsonValue
      insert_key!(object, key_token, value, strict)
      subsequent_depth = base_depth + 1

      until cursor.at_end?
        line = cursor.peek
        break unless line && line.depth > base_depth
        if line.depth != subsequent_depth
          skip_orphan_line!(cursor, strict)
          next
        end

        key_token, value = decode_key_value_pair(line, cursor, subsequent_depth, delimiter, strict)
        insert_key!(object, key_token, value, strict)
      end

      object
    end

    private def skip_orphan_line!(cursor : LineCursor, strict : Bool)
      return unless line = cursor.next
      if strict || !key_value_line?(line.content)
        raise DecodeError.new("Unexpected line outside its scope")
      end
    end

    private def insert_key!(object : Hash(String, JsonValue), token : KeyToken, value : JsonValue, strict : Bool)
      raise DecodeError.new("Duplicate key '#{token.value}'") if strict && object.has_key?(token.value)
      object[token.value] = value
    end

    private def parse_key_token(content : String) : {KeyToken, String}
      i = 0
      in_quotes = false
      escaped = false

      while i < content.size
        ch = content[i]
        if in_quotes
          in_quotes = false if !escaped && ch == '"'
          escaped = !escaped && ch == '\\'
        else
          if ch == ':'
            key_raw = content[0, i]
            rest = content[i + 1, content.size - i - 1]
            return {parse_key_token_value(trim_token_spaces(key_raw)), rest}
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
  end
end

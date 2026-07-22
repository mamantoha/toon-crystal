require "../constants"
require "./options"
require "./normalizer"
require "./primitives"
require "./writer"

module Toon
  module Encoders
    extend self

    private class TabularField
      getter name : String
      getter children : Array(TabularField)?

      def initialize(@name : String, @children : Array(TabularField)? = nil)
      end
    end

    # Encode normalized value
    def encode_value(value, options : EncodeOptions)
      if Normalizer.json_primitive?(value)
        return Primitives.encode_primitive(value, options.delimiter)
      end

      writer = LineWriter.new(options.indent)

      if value.is_a?(Array)
        encode_array(nil, value.as(Array), writer, 0, options)
      elsif value.is_a?(Hash)
        object = value.as(Hash(String, JsonValue))
        if fields = detect_keyed_tabular_fields(object)
          encode_keyed_object(nil, object, fields, writer, 0, options)
        else
          encode_object(object, writer, 0, options)
        end
      end

      writer.to_s
    end

    # Object encoding
    def encode_object(value : Hash(String, JsonValue), writer : LineWriter, depth : Int32, options : EncodeOptions)
      value.each do |key, item|
        emit_key_value_pair(key, item, writer, depth, options)
      end
    end

    private def emit_key_value_pair(key : String, value, writer : LineWriter, depth : Int32, options : EncodeOptions)
      encoded_key = Primitives.encode_key(key)

      if Normalizer.json_primitive?(value)
        writer.push(depth, "#{encoded_key}: #{Primitives.encode_primitive(value, options.delimiter)}")
      elsif value.is_a?(Array)
        encode_array(key, value, writer, depth, options)
      elsif value.is_a?(Hash)
        object = value.as(Hash(String, JsonValue))

        if fields = detect_keyed_tabular_fields(object)
          encode_keyed_object(key, object, fields, writer, depth, options)
          return
        end

        nested_keys = object.keys

        if nested_keys.empty?
          # Empty object
          writer.push(depth, "#{encoded_key}:")
        else
          writer.push(depth, "#{encoded_key}:")

          encode_object(object, writer, depth + 1, options)
        end
      end
    end

    # Array encoding
    def encode_array(key : String?, value : Array, writer : LineWriter, depth : Int32, options : EncodeOptions)
      if value.empty?
        if key
          writer.push(depth, "#{Primitives.encode_key(key)}: []")
        else
          writer.push(depth, "[]")
        end

        return
      end

      # Primitive array
      if Normalizer.array_of_primitives?(value)
        encode_inline_primitive_array(key, value, writer, depth, options)

        return
      end

      # Array of arrays (all primitives)
      if Normalizer.array_of_arrays?(value)
        all_primitive_arrays = value.all? { |arr| arr.is_a?(Array) && Normalizer.array_of_primitives?(arr) }

        if all_primitive_arrays
          encode_array_of_arrays_as_list_items(key, value, writer, depth, options)

          return
        end
      end

      # Array of objects
      if Normalizer.array_of_objects?(value)
        header = detect_tabular_header(value)

        if header
          encode_array_of_objects_as_tabular(key, value, header, writer, depth, options)
        else
          encode_mixed_array_as_list_items(key, value, writer, depth, options)
        end

        return
      end

      # Mixed array: fallback to expanded format
      encode_mixed_array_as_list_items(key, value, writer, depth, options)
    end

    # Primitive array encoding (inline)
    def encode_inline_primitive_array(key : String?, values : Array, writer : LineWriter, depth : Int32, options : EncodeOptions)
      formatted = format_inline_array(values, options.delimiter, key)
      writer.push(depth, formatted)
    end

    # Array of arrays (expanded format)
    def encode_array_of_arrays_as_list_items(key : String?, values : Array, writer : LineWriter, depth : Int32, options : EncodeOptions)
      header = Primitives.format_header(values.size, key: key, delimiter: options.delimiter)
      writer.push(depth, header)

      values.each do |arr|
        if arr.is_a?(Array) && Normalizer.array_of_primitives?(arr)
          inline = format_inline_array(arr, options.delimiter, nil)
          writer.push(depth + 1, "#{LIST_ITEM_PREFIX}#{inline}")
        end
      end
    end

    def format_inline_array(values, delimiter : String, key : String? = nil)
      header = Primitives.format_header(values.size, key: key, delimiter: delimiter)
      joined_value = Primitives.join_encoded_values(values, delimiter)

      # Only add space if there are values
      if values.empty?
        header
      else
        "#{header} #{joined_value}"
      end
    end

    # Array of objects (tabular format)
    def encode_array_of_objects_as_tabular(key : String?, rows : Array, header : Array(TabularField), writer : LineWriter, depth : Int32, options : EncodeOptions)
      header_str = format_tabular_header(rows.size, key, header, options.delimiter)
      writer.push(depth, header_str)

      write_tabular_rows(rows, header, writer, depth + 1, options)
    end

    def detect_tabular_header(rows)
      return if rows.empty?

      first_row = rows[0]
      return unless first_row.is_a?(Hash)

      fields = build_tabular_fields(first_row)
      return unless fields
      fields if rows.all? { |row| row.is_a?(Hash) && tabular_shape?(row, fields) }
    end

    private def build_tabular_fields(row : Hash) : Array(TabularField)?
      return if row.empty?

      fields = [] of TabularField
      row.each do |key, value|
        if Normalizer.json_primitive?(value)
          fields << TabularField.new(key)
        elsif value.is_a?(Hash) && (children = build_tabular_fields(value))
          fields << TabularField.new(key, children)
        else
          return
        end
      end
      fields
    end

    private def tabular_shape?(row : Hash, fields : Array(TabularField)) : Bool
      return false unless row.size == fields.size
      fields.all? do |field|
        next false unless row.has_key?(field.name)
        value = row[field.name]
        if children = field.children
          value.is_a?(Hash) && tabular_shape?(value, children)
        else
          Normalizer.json_primitive?(value)
        end
      end
    end

    private def format_tabular_fields(fields : Array(TabularField), delimiter : String) : String
      fields.map do |field|
        name = Primitives.encode_key(field.name)
        if children = field.children
          "#{name}{#{format_tabular_fields(children, delimiter)}}"
        else
          name
        end
      end.join(delimiter)
    end

    private def format_tabular_header(length : Int32, key : String?, fields : Array(TabularField), delimiter : String, keyed : Bool = false) : String
      prefix = key ? Primitives.encode_key(key) : ""
      delimiter_suffix = delimiter == DEFAULT_DELIMITER.to_s ? "" : delimiter
      marker = keyed ? ":" : ""
      "#{prefix}[#{length}#{marker}#{delimiter_suffix}]{#{format_tabular_fields(fields, delimiter)}}:"
    end

    private def flattened_values(row : Hash, fields : Array(TabularField)) : Array(JsonValue)
      values = [] of JsonValue
      fields.each do |field|
        value = row[field.name]
        if children = field.children
          values.concat(flattened_values(value.as(Hash), children))
        else
          values << value.as(JsonValue)
        end
      end
      values
    end

    def write_tabular_rows(rows, header : Array(TabularField), writer : LineWriter, depth : Int32, options : EncodeOptions)
      rows.each do |row|
        next unless row.is_a?(Hash)

        values = flattened_values(row, header)
        joined_value = Primitives.join_encoded_values(values, options.delimiter)
        writer.push(depth, joined_value)
      end
    end

    private def detect_keyed_tabular_fields(object : Hash(String, JsonValue)) : Array(TabularField)?
      return if object.size < 2
      first = object[object.keys.first]
      return unless first.is_a?(Hash)
      fields = build_tabular_fields(first)
      return unless fields
      fields if object.all? { |_key, value| value.is_a?(Hash) && tabular_shape?(value, fields) }
    end

    private def encode_keyed_object(key : String?, object : Hash(String, JsonValue), fields : Array(TabularField), writer : LineWriter, depth : Int32, options : EncodeOptions, list_item : Bool = false)
      header = format_tabular_header(object.size, key, fields, options.delimiter, keyed: true)
      writer.push(depth, list_item ? "#{LIST_ITEM_PREFIX}#{header}" : header)
      row_depth = depth + (list_item ? 2 : 1)
      object.each do |entry_key, value|
        cells = Primitives.join_encoded_values(flattened_values(value.as(Hash), fields), options.delimiter)
        writer.push(row_depth, "#{Primitives.encode_key(entry_key)}: #{cells}")
      end
    end

    private def emit_tabular_header_and_rows(writer : LineWriter, header_depth : Int32, row_depth : Int32, key : String?, rows : Array, header : Array(TabularField), options : EncodeOptions, include_list_prefix : Bool = false)
      header_str = format_tabular_header(rows.size, key, header, options.delimiter)

      if include_list_prefix
        writer.push(header_depth, "#{LIST_ITEM_PREFIX}#{header_str}")
      else
        writer.push(header_depth, header_str)
      end

      write_tabular_rows(rows, header, writer, row_depth, options)
    end

    private def try_emit_compact_array_list_item(writer : LineWriter, depth : Int32, key : String?, arr : Array, options : EncodeOptions) : Bool
      if Normalizer.array_of_primitives?(arr)
        if arr.empty? && key
          writer.push(depth, "#{LIST_ITEM_PREFIX}#{Primitives.encode_key(key)}: []")
        else
          formatted = format_inline_array(arr, options.delimiter, key)
          writer.push(depth, "#{LIST_ITEM_PREFIX}#{formatted}")
        end
        return true
      elsif Normalizer.array_of_objects?(arr)
        header = detect_tabular_header(arr)

        if header
          emit_tabular_header_and_rows(writer, depth, depth + 2, key, arr, header, options, true)
          return true
        end
      end

      false
    end

    # Array of objects (expanded format)
    def encode_mixed_array_as_list_items(key : String?, items : Array, writer : LineWriter, depth : Int32, options : EncodeOptions)
      header = Primitives.format_header(items.size, key: key, delimiter: options.delimiter)
      writer.push(depth, header)

      items.each do |item|
        if Normalizer.json_primitive?(item)
          # Direct primitive as list item
          writer.push(depth + 1, "#{LIST_ITEM_PREFIX}#{Primitives.encode_primitive(item, options.delimiter)}")
        elsif item.is_a?(Array)
          # Direct array as list item
          if Normalizer.array_of_primitives?(item)
            inline = format_inline_array(item, options.delimiter, nil)
            writer.push(depth + 1, "#{LIST_ITEM_PREFIX}#{inline}")
          elsif Normalizer.array_of_objects?(item)
            # Array of objects as a nested list item: emit header then inner objects
            header_str = Primitives.format_header(item.size, delimiter: options.delimiter)
            writer.push(depth + 1, "#{LIST_ITEM_PREFIX}#{header_str}")

            item.each do |sub|
              if sub.is_a?(Hash)
                # encode inner objects as list items, with increased depth
                encode_object_as_list_item(sub.as(Hash(String, JsonValue)), writer, depth + 2, options)
              end
            end
          end
        elsif item.is_a?(Hash)
          # Object as list item
          encode_object_as_list_item(item, writer, depth + 1, options)
        end
      end
    end

    def encode_object_as_list_item(obj : Hash(String, JsonValue), writer : LineWriter, depth : Int32, options : EncodeOptions)
      keys = obj.keys

      if keys.empty?
        writer.push(depth, LIST_ITEM_MARKER.to_s)

        return
      end

      # Special-case: single-field objects whose value is an inline-able array
      # (primitive array or tabular object array) should use the compact form on
      # the same hyphen line (e.g., "- key[2]: 1,2" or "- key[2]{a,b}:\n  1,2").
      if keys.size == 1
        only_key = keys.first
        value = obj[only_key]

        if value.is_a?(Array)
          arr = value.as(Array)

          if try_emit_compact_array_list_item(writer, depth, only_key, arr, options)
            return
          end
        end
      end

      if first_fields = detect_keyed_tabular_fields(obj[keys.first].as?(Hash(String, JsonValue)) || ({} of String => JsonValue))
        first_key = keys.first
        encode_keyed_object(first_key, obj[first_key].as(Hash(String, JsonValue)), first_fields, writer, depth, options, list_item: true)
        keys[1..].each do |key|
          emit_key_value_pair(key, obj[key], writer, depth + 1, options)
        end
        return
      end

      # First key-value on the same line as "- " when possible (compact form)
      first_key = keys.first
      encoded_key = Primitives.encode_key(first_key)
      first_value = obj[first_key]

      if Normalizer.json_primitive?(first_value)
        writer.push(depth, "#{LIST_ITEM_PREFIX}#{encoded_key}: #{Primitives.encode_primitive(first_value, options.delimiter)}")
      elsif first_value.is_a?(Array)
        arr = first_value

        if try_emit_compact_array_list_item(writer, depth, first_key, arr, options)
          # compact form emitted
        else
          if Normalizer.array_of_objects?(arr)
            # Fall back to list format for non-uniform arrays of objects
            writer.push(depth, "#{LIST_ITEM_PREFIX}#{encoded_key}[#{arr.size}]:")

            arr.each do |item|
              if item.is_a?(Hash)
                encode_object_as_list_item(item.as(Hash(String, JsonValue)), writer, depth + 2, options)
              end
            end
          else
            # Complex arrays on separate lines (array of arrays, etc.)
            writer.push(depth, "#{LIST_ITEM_PREFIX}#{encoded_key}[#{arr.size}]:")

            # Encode array contents at depth + 2 (header printed on hyphen line)
            arr.each do |item|
              if Normalizer.json_primitive?(item)
                writer.push(depth + 2, "#{LIST_ITEM_PREFIX}#{Primitives.encode_primitive(item, options.delimiter)}")
              elsif item.is_a?(Array) && Normalizer.array_of_primitives?(item)
                inline = format_inline_array(item, options.delimiter, nil)
                writer.push(depth + 2, "#{LIST_ITEM_PREFIX}#{inline}")
              elsif item.is_a?(Hash)
                encode_object_as_list_item(item.as(Hash(String, JsonValue)), writer, depth + 2, options)
              end
            end
          end
        end
      elsif first_value.is_a?(Hash)
        nested_keys = first_value.keys

        if nested_keys.empty?
          writer.push(depth, "#{LIST_ITEM_PREFIX}#{encoded_key}:")
        else
          writer.push(depth, "#{LIST_ITEM_PREFIX}#{encoded_key}:")
          encode_object(first_value.as(Hash(String, JsonValue)), writer, depth + 2, options)
        end
      end

      # Remaining keys on indented lines
      keys[1..].each do |key|
        emit_key_value_pair(key, obj[key], writer, depth + 1, options)
      end
    end
  end
end

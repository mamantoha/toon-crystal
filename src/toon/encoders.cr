require "./constants"
require "./writer"
require "./normalizer"
require "./primitives"

module Toon
  module Encoders
    extend self

    # Encode normalized value
    def encode_value(value, options)
      if Normalizer.json_primitive?(value)
        return Primitives.encode_primitive(value, options[:delimiter])
      end

      writer = LineWriter.new(options[:indent])

      if value.is_a?(Array)
        encode_array(nil, value.as(Array), writer, 0, options)
      elsif value.is_a?(Hash)
        encode_object(value.as(Hash), writer, 0, options)
      end

      writer.to_s
    end

    # Object encoding
    def encode_object(value : Hash, writer : LineWriter, depth : Int32, options)
      keys = value.keys

      keys.each do |key|
        encode_key_value_pair(key, value[key], writer, depth, options)
      end
    end

    def encode_key_value_pair(key : String, value, writer : LineWriter, depth : Int32, options)
      encoded_key = Primitives.encode_key(key)

      if Normalizer.json_primitive?(value)
        writer.push(depth, "#{encoded_key}: #{Primitives.encode_primitive(value, options[:delimiter])}")
      elsif value.is_a?(Array)
        encode_array(key, value, writer, depth, options)
      elsif value.is_a?(Hash)
        nested_keys = value.keys

        if nested_keys.empty?
          # Empty object
          writer.push(depth, "#{encoded_key}:")
        else
          writer.push(depth, "#{encoded_key}:")

          encode_object(value, writer, depth + 1, options)
        end
      end
    end

    # Array encoding
    def encode_array(key : String?, value : Array, writer : LineWriter, depth : Int32, options)
      if value.empty?
        header = Primitives.format_header(0, key: key, delimiter: options[:delimiter], length_marker: options[:length_marker])
        writer.push(depth, header)

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
    def encode_inline_primitive_array(key : String?, values : Array, writer : LineWriter, depth : Int32, options)
      formatted = format_inline_array(values, options[:delimiter], key, options[:length_marker])
      writer.push(depth, formatted)
    end

    # Array of arrays (expanded format)
    def encode_array_of_arrays_as_list_items(key : String?, values : Array, writer : LineWriter, depth : Int32, options)
      header = Primitives.format_header(values.size, key: key, delimiter: options[:delimiter], length_marker: options[:length_marker])
      writer.push(depth, header)

      values.each do |arr|
        if arr.is_a?(Array) && Normalizer.array_of_primitives?(arr)
          inline = format_inline_array(arr, options[:delimiter], nil, options[:length_marker])
          writer.push(depth + 1, "#{LIST_ITEM_PREFIX}#{inline}")
        end
      end
    end

    def format_inline_array(values, delimiter : String, key : String? = nil, length_marker : String | Bool = false)
      header = Primitives.format_header(values.size, key: key, delimiter: delimiter, length_marker: length_marker)
      joined_value = Primitives.join_encoded_values(values, delimiter)

      # Only add space if there are values
      if values.empty?
        header
      else
        "#{header} #{joined_value}"
      end
    end

    # Array of objects (tabular format)
    def encode_array_of_objects_as_tabular(key : String?, rows : Array, header : Array(String), writer : LineWriter, depth : Int32, options)
      header_str = Primitives.format_header(rows.size, key: key, fields: header, delimiter: options[:delimiter], length_marker: options[:length_marker])
      writer.push(depth, header_str)

      write_tabular_rows(rows, header, writer, depth + 1, options)
    end

    def detect_tabular_header(rows)
      return nil if rows.empty?

      first_row = rows[0]
      return nil unless first_row.is_a?(Hash)

      first_keys = first_row.keys
      return nil if first_keys.empty?

      if tabular_array?(rows, first_keys)
        first_keys
      end
    end

    def tabular_array?(rows, header : Array(String))
      rows.all? do |row|
        return false unless row.is_a?(Hash)

        keys = row.keys

        # All objects must have the same keys (but order can differ)
        return false if keys.size != header.size

        # Check that all header keys exist in the row and all values are primitives
        header.all? do |key|
          row.has_key?(key) && Normalizer.json_primitive?(row[key])
        end
      end
    end

    def write_tabular_rows(rows, header : Array(String), writer : LineWriter, depth : Int32, options)
      rows.each do |row|
        next unless row.is_a?(Hash)

        values = header.map { |key| row[key] }
        joined_value = Primitives.join_encoded_values(values, options[:delimiter])
        writer.push(depth, joined_value)
      end
    end

    # Array of objects (expanded format)
    def encode_mixed_array_as_list_items(key : String?, items : Array, writer : LineWriter, depth : Int32, options)
      header = Primitives.format_header(items.size, key: key, delimiter: options[:delimiter], length_marker: options[:length_marker])
      writer.push(depth, header)

      items.each do |item|
        if Normalizer.json_primitive?(item)
          # Direct primitive as list item
          writer.push(depth + 1, "#{LIST_ITEM_PREFIX}#{Primitives.encode_primitive(item, options[:delimiter])}")
        elsif item.is_a?(Array)
          # Direct array as list item
          if Normalizer.array_of_primitives?(item)
            inline = format_inline_array(item, options[:delimiter], nil, options[:length_marker])
            writer.push(depth + 1, "#{LIST_ITEM_PREFIX}#{inline}")
          end
        elsif item.is_a?(Hash)
          # Object as list item
          encode_object_as_list_item(item, writer, depth + 1, options)
        end
      end
    end

    # ameba:disable Metrics/CyclomaticComplexity
    def encode_object_as_list_item(obj : Hash, writer : LineWriter, depth : Int32, options)
      keys = obj.keys

      if keys.empty?
        writer.push(depth, LIST_ITEM_MARKER.to_s)

        return
      end

      # First key-value on the same line as "- "
      first_key = keys.first
      encoded_key = Primitives.encode_key(first_key)
      first_value = obj[first_key]

      if Normalizer.json_primitive?(first_value)
        writer.push(depth, "#{LIST_ITEM_PREFIX}#{encoded_key}: #{Primitives.encode_primitive(first_value, options[:delimiter])}")
      elsif first_value.is_a?(Array)
        arr = first_value

        if Normalizer.array_of_primitives?(arr)
          # Inline format for primitive arrays
          formatted = format_inline_array(arr, options[:delimiter], first_key, options[:length_marker])
          writer.push(depth, "#{LIST_ITEM_PREFIX}#{formatted}")
        elsif Normalizer.array_of_objects?(arr)
          # Check if array of objects can use tabular format
          header = detect_tabular_header(arr)

          if header
            # Tabular format for uniform arrays of objects
            header_str = Primitives.format_header(arr.size, key: first_key, fields: header, delimiter: options[:delimiter], length_marker: options[:length_marker])
            writer.push(depth, "#{LIST_ITEM_PREFIX}#{header_str}")
            write_tabular_rows(arr, header, writer, depth + 1, options)
          else
            # Fall back to list format for non-uniform arrays of objects
            writer.push(depth, "#{LIST_ITEM_PREFIX}#{encoded_key}[#{arr.size}]:")

            arr.each do |item|
              if item.is_a?(Hash)
                encode_object_as_list_item(item, writer, depth + 1, options)
              end
            end
          end
        else
          # Complex arrays on separate lines (array of arrays, etc.)
          writer.push(depth, "#{LIST_ITEM_PREFIX}#{encoded_key}[#{arr.size}]:")

          # Encode array contents at depth + 1
          arr.each do |item|
            if Normalizer.json_primitive?(item)
              writer.push(depth + 1, "#{LIST_ITEM_PREFIX}#{Primitives.encode_primitive(item, options[:delimiter])}")
            elsif item.is_a?(Array) && Normalizer.array_of_primitives?(item)
              inline = format_inline_array(item, options[:delimiter], nil, options[:length_marker])
              writer.push(depth + 1, "#{LIST_ITEM_PREFIX}#{inline}")
            elsif item.is_a?(Hash)
              encode_object_as_list_item(item, writer, depth + 1, options)
            end
          end
        end
      elsif first_value.is_a?(Hash)
        nested_keys = first_value.keys

        if nested_keys.empty?
          writer.push(depth, "#{LIST_ITEM_PREFIX}#{encoded_key}:")
        else
          writer.push(depth, "#{LIST_ITEM_PREFIX}#{encoded_key}:")
          encode_object(first_value, writer, depth + 2, options)
        end
      end

      # Remaining keys on indented lines
      keys[1..].each do |key|
        encode_key_value_pair(key, obj[key], writer, depth + 1, options)
      end
    end
  end
end

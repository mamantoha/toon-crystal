require "../constants"
require "./normalizer"
require "./primitives"
require "./writer"

module Toon
  module Encoders
    extend self

    IDENTIFIER_SEGMENT_REGEX = /^[A-Za-z_][A-Za-z0-9_]*$/

    private def flatten_limit(options) : Int32
      options[:flatten_limit].as(Int32)
    end

    private def folding_enabled?(options) : Bool
      key_folding_safe?(options)
    end

    # Encode normalized value
    def encode_value(value, options)
      if Normalizer.json_primitive?(value)
        return Primitives.encode_primitive(value, options[:delimiter])
      end

      writer = LineWriter.new(options[:indent])

      if value.is_a?(Array)
        encode_array(nil, value.as(Array), writer, 0, options)
      elsif value.is_a?(Hash)
        encode_object(value.as(Hash(String, Decoders::JsonValue)), writer, 0, options, folding_enabled?(options), nil)
      end

      writer.to_s
    end

    # Object encoding
    def encode_object(value : Hash(String, Decoders::JsonValue), writer : LineWriter, depth : Int32, options, folding_enabled : Bool = folding_enabled?(options), chain_limit : Int32? = nil)
      keys = value.keys

      keys.each do |key|
        raw_value = value[key]
        folded_key, folded_value, child_enabled, child_limit = maybe_fold_key(key, raw_value, value, options, folding_enabled, chain_limit)
        emit_key_value_pair(folded_key, folded_value, writer, depth, options, child_enabled, child_limit)
      end
    end

    private def maybe_fold_key(key : String, value : Decoders::JsonValue, parent : Hash(String, Decoders::JsonValue), options, folding_enabled : Bool, chain_limit : Int32?) : {String, Decoders::JsonValue, Bool, Int32?}
      return {key, value, false, nil} unless folding_enabled

      limit = chain_limit || flatten_limit(options)
      return {key, value, false, nil} if limit < 2
      return {key, value, folding_enabled, nil} unless foldable_segment?(key)

      segments = [key]
      current_value = value
      reason = :start

      while segments.size < limit
        unless current_value.is_a?(Hash(String, Decoders::JsonValue))
          reason = :leaf
          break
        end

        child_hash = current_value.as(Hash(String, Decoders::JsonValue))
        child_keys = child_hash.keys

        if child_keys.size != 1
          reason = :branch
          break
        end

        next_key = child_keys.first
        unless foldable_segment?(next_key)
          reason = :unfoldable
          break
        end

        candidate_segments = segments + [next_key]
        folded_candidate = candidate_segments.join('.')

        if parent.has_key?(folded_candidate)
          return {key, value, false, nil}
        end

        segments << next_key
        current_value = child_hash[next_key]
        reason = :continued
      end

      if segments.size == limit && current_value.is_a?(Hash(String, Decoders::JsonValue))
        reason = :limit
      end

      if segments.size == 1
        child_enabled =
          case reason
          when :unfoldable, :limit
            false
          else
            folding_enabled
          end

        return {key, value, child_enabled, nil}
      end

      # Heuristic: avoid folding two-segment chains when parent has multiple keys
      folded_key = segments.join('.')

      child_enabled = folding_enabled
      child_limit : Int32? = nil

      if current_value.is_a?(Hash(String, Decoders::JsonValue))
        case reason
        when :limit, :unfoldable
          child_enabled = false
        when :branch
          child_enabled = folding_enabled
          child_limit = nil
        else
          remaining = limit - segments.size

          if remaining >= 2
            child_limit = remaining
          else
            child_enabled = false
          end
        end
      else
        child_enabled = folding_enabled
        child_limit = nil
      end

      {folded_key, current_value, child_enabled, child_limit}
    end

    private def key_folding_safe?(options) : Bool
      options[:key_folding_mode].as(KeyFoldingMode).safe?
    end

    private def foldable_segment?(segment : String) : Bool
      IDENTIFIER_SEGMENT_REGEX.matches?(segment)
    end

    private def emit_key_value_pair(key : String, value, writer : LineWriter, depth : Int32, options, child_enabled : Bool, child_limit : Int32?)
      encoded_key = Primitives.encode_key(key)

      if Normalizer.json_primitive?(value)
        writer.push(depth, "#{encoded_key}: #{Primitives.encode_primitive(value, options[:delimiter])}")
      elsif value.is_a?(Array)
        encode_array(key, value, writer, depth, options, child_enabled)
      elsif value.is_a?(Hash)
        nested_keys = value.keys

        if nested_keys.empty?
          # Empty object
          writer.push(depth, "#{encoded_key}:")
        else
          writer.push(depth, "#{encoded_key}:")

          encode_object(value.as(Hash(String, Decoders::JsonValue)), writer, depth + 1, options, child_enabled, child_limit)
        end
      end
    end

    # Array encoding
    def encode_array(key : String?, value : Array, writer : LineWriter, depth : Int32, options, folding_enabled : Bool = folding_enabled?(options))
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
          encode_mixed_array_as_list_items(key, value, writer, depth, options, folding_enabled)
        end

        return
      end

      # Mixed array: fallback to expanded format
      encode_mixed_array_as_list_items(key, value, writer, depth, options, folding_enabled)
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
    def encode_mixed_array_as_list_items(key : String?, items : Array, writer : LineWriter, depth : Int32, options, folding_enabled : Bool = folding_enabled?(options))
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
          encode_object_as_list_item(item, writer, depth + 1, options, folding_enabled)
        end
      end
    end

    def encode_object_as_list_item(obj : Hash(String, Decoders::JsonValue), writer : LineWriter, depth : Int32, options, folding_enabled : Bool = folding_enabled?(options), chain_limit : Int32? = nil)
      keys = obj.keys

      if keys.empty?
        writer.push(depth, LIST_ITEM_MARKER.to_s)

        return
      end

      # First key-value on the same line as "- "
      first_key = keys.first
      folded_first_key, folded_first_value, first_child_enabled, first_child_limit = maybe_fold_key(first_key, obj[first_key], obj, options, folding_enabled, chain_limit)
      encoded_key = Primitives.encode_key(folded_first_key)
      first_value = folded_first_value

      if Normalizer.json_primitive?(first_value)
        writer.push(depth, "#{LIST_ITEM_PREFIX}#{encoded_key}: #{Primitives.encode_primitive(first_value, options[:delimiter])}")
      elsif first_value.is_a?(Array)
        arr = first_value

        if Normalizer.array_of_primitives?(arr)
          # Inline format for primitive arrays
          formatted = format_inline_array(arr, options[:delimiter], folded_first_key, options[:length_marker])
          writer.push(depth, "#{LIST_ITEM_PREFIX}#{formatted}")
        elsif Normalizer.array_of_objects?(arr)
          # Check if array of objects can use tabular format
          header = detect_tabular_header(arr)

          if header
            # Tabular format for uniform arrays of objects
            header_str = Primitives.format_header(arr.size, key: folded_first_key, fields: header, delimiter: options[:delimiter], length_marker: options[:length_marker])
            writer.push(depth, "#{LIST_ITEM_PREFIX}#{header_str}")
            write_tabular_rows(arr, header, writer, depth + 1, options)
          else
            # Fall back to list format for non-uniform arrays of objects
            writer.push(depth, "#{LIST_ITEM_PREFIX}#{encoded_key}[#{arr.size}]:")

            arr.each do |item|
              if item.is_a?(Hash)
                encode_object_as_list_item(item.as(Hash(String, Decoders::JsonValue)), writer, depth + 1, options, first_child_enabled)
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
              encode_object_as_list_item(item.as(Hash(String, Decoders::JsonValue)), writer, depth + 1, options, first_child_enabled)
            end
          end
        end
      elsif first_value.is_a?(Hash)
        nested_keys = first_value.keys

        if nested_keys.empty?
          writer.push(depth, "#{LIST_ITEM_PREFIX}#{encoded_key}:")
        else
          writer.push(depth, "#{LIST_ITEM_PREFIX}#{encoded_key}:")
          encode_object(first_value.as(Hash(String, Decoders::JsonValue)), writer, depth + 2, options, first_child_enabled, first_child_limit)
        end
      end

      # Remaining keys on indented lines
      keys[1..].each do |key|
        raw = obj[key]
        folded_key, folded_value, child_enabled, child_limit = maybe_fold_key(key, raw, obj, options, folding_enabled, chain_limit)
        emit_key_value_pair(folded_key, folded_value, writer, depth + 1, options, child_enabled, child_limit)
      end
    end
  end
end

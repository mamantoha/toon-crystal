require "../constants"
require "./options"
require "./normalizer"
require "./primitives"
require "./writer"

module Toon
  module Encoders
    extend self

    private struct FoldChain
      getter segments : Array(String)
      getter leaf_value : JsonValue
      getter stop : Symbol
      getter collision_key : String?

      def initialize(@segments : Array(String), @leaf_value : JsonValue, @stop : Symbol, @collision_key : String? = nil)
      end

      def folded_key : String
        segments.join('.')
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
        encode_object(value.as(Hash(String, JsonValue)), writer, 0, options, options.key_folding_mode.safe?, nil)
      end

      writer.to_s
    end

    # Object encoding
    def encode_object(value : Hash(String, JsonValue), writer : LineWriter, depth : Int32, options : EncodeOptions, folding_enabled : Bool = options.key_folding_mode.safe?, chain_limit : Int32? = nil)
      keys = value.keys

      keys.each do |key|
        raw_value = value[key]
        folded_key, folded_value, child_enabled, child_limit = maybe_fold_key(key, raw_value, value, options, folding_enabled, chain_limit)
        emit_key_value_pair(folded_key, folded_value, writer, depth, options, child_enabled, child_limit)
      end
    end

    private def maybe_fold_key(key : String, value : JsonValue, parent : Hash(String, JsonValue), options : EncodeOptions, folding_enabled : Bool, chain_limit : Int32?) : {String, JsonValue, Bool, Int32?}
      return {key, value, false, nil} unless folding_enabled

      limit = chain_limit || options.flatten_limit
      return {key, value, false, nil} if limit < 2
      return {key, value, folding_enabled, nil} unless foldable_segment?(key)

      chain = walk_fold_chain(key, value, parent, limit)
      folded_key = chain.folded_key

      if chain.segments.size == 1 && chain.stop == :unfoldable
        return {key, value, folding_enabled, nil}
      end

      if chain.collision_key && parent.has_key?(chain.collision_key)
        return {key, value, false, nil}
      end

      child_enabled, child_limit = child_fold_options(chain, limit, folding_enabled)
      {folded_key, chain.leaf_value, child_enabled, child_limit}
    end

    private def walk_fold_chain(key : String, value : JsonValue, parent : Hash(String, JsonValue), limit : Int32) : FoldChain
      segments = [key]
      current_value = value
      stop : Symbol = :start
      collision_key : String? = nil

      while segments.size < limit
        unless current_value.is_a?(Hash(String, JsonValue))
          stop = :leaf
          break
        end

        child_hash = current_value.as(Hash(String, JsonValue))
        child_keys = child_hash.keys

        if child_keys.size != 1
          stop = :branch
          break
        end

        next_key = child_keys.first
        unless foldable_segment?(next_key)
          stop = :unfoldable
          break
        end

        candidate_segments = segments + [next_key]
        folded_candidate = candidate_segments.join('.')

        if parent.has_key?(folded_candidate)
          stop = :unfoldable
          collision_key = folded_candidate
          break
        end

        segments << next_key
        current_value = child_hash[next_key]
        stop = :continued
      end

      if segments.size == limit && current_value.is_a?(Hash(String, JsonValue))
        stop = :limit
      end

      FoldChain.new(segments, current_value, stop, collision_key)
    end

    private def child_fold_options(chain : FoldChain, limit : Int32, folding_enabled : Bool) : {Bool, Int32?}
      child_enabled = folding_enabled
      child_limit : Int32? = nil

      if chain.segments.size == 1
        case chain.stop
        when :unfoldable, :limit
          child_enabled = false
        else
          child_enabled = folding_enabled
        end

        return {child_enabled, nil}
      end

      if chain.leaf_value.is_a?(Hash(String, JsonValue))
        case chain.stop
        when :limit, :unfoldable
          child_enabled = false
        when :branch
          child_enabled = folding_enabled
          child_limit = nil
        else
          remaining = limit - chain.segments.size

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

      {child_enabled, child_limit}
    end

    private def foldable_segment?(segment : String) : Bool
      IDENTIFIER_SEGMENT_REGEX.matches?(segment)
    end

    private def emit_key_value_pair(key : String, value, writer : LineWriter, depth : Int32, options : EncodeOptions, child_enabled : Bool, child_limit : Int32?)
      encoded_key = Primitives.encode_key(key)

      if Normalizer.json_primitive?(value)
        writer.push(depth, "#{encoded_key}: #{Primitives.encode_primitive(value, options.delimiter)}")
      elsif value.is_a?(Array)
        encode_array(key, value, writer, depth, options, child_enabled)
      elsif value.is_a?(Hash)
        nested_keys = value.keys

        if nested_keys.empty?
          # Empty object
          writer.push(depth, "#{encoded_key}:")
        else
          writer.push(depth, "#{encoded_key}:")

          encode_object(value.as(Hash(String, JsonValue)), writer, depth + 1, options, child_enabled, child_limit)
        end
      end
    end

    # Array encoding
    def encode_array(key : String?, value : Array, writer : LineWriter, depth : Int32, options : EncodeOptions, folding_enabled : Bool = options.key_folding_mode.safe?)
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
          encode_mixed_array_as_list_items(key, value, writer, depth, options, folding_enabled)
        end

        return
      end

      # Mixed array: fallback to expanded format
      encode_mixed_array_as_list_items(key, value, writer, depth, options, folding_enabled)
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
    def encode_array_of_objects_as_tabular(key : String?, rows : Array, header : Array(String), writer : LineWriter, depth : Int32, options : EncodeOptions)
      header_str = Primitives.format_header(rows.size, key: key, fields: header, delimiter: options.delimiter)
      writer.push(depth, header_str)

      write_tabular_rows(rows, header, writer, depth + 1, options)
    end

    def detect_tabular_header(rows)
      return if rows.empty?

      first_row = rows[0]
      return unless first_row.is_a?(Hash)

      first_keys = first_row.keys
      return if first_keys.empty?

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

    def write_tabular_rows(rows, header : Array(String), writer : LineWriter, depth : Int32, options : EncodeOptions)
      rows.each do |row|
        next unless row.is_a?(Hash)

        values = header.map { |key| row[key] }
        joined_value = Primitives.join_encoded_values(values, options.delimiter)
        writer.push(depth, joined_value)
      end
    end

    private def emit_tabular_header_and_rows(writer : LineWriter, header_depth : Int32, row_depth : Int32, key : String?, rows : Array, header : Array(String), options : EncodeOptions, include_list_prefix : Bool = false)
      header_str = Primitives.format_header(rows.size, key: key, fields: header, delimiter: options.delimiter)

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
    def encode_mixed_array_as_list_items(key : String?, items : Array, writer : LineWriter, depth : Int32, options : EncodeOptions, folding_enabled : Bool = options.key_folding_mode.safe?)
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
                encode_object_as_list_item(sub.as(Hash(String, JsonValue)), writer, depth + 2, options, folding_enabled)
              end
            end
          end
        elsif item.is_a?(Hash)
          # Object as list item
          encode_object_as_list_item(item, writer, depth + 1, options, folding_enabled)
        end
      end
    end

    def encode_object_as_list_item(obj : Hash(String, JsonValue), writer : LineWriter, depth : Int32, options : EncodeOptions, folding_enabled : Bool = options.key_folding_mode.safe?, chain_limit : Int32? = nil)
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
        raw = obj[only_key]
        folded_key, folded_value, child_enabled, child_limit = maybe_fold_key(only_key, raw, obj, options, folding_enabled, chain_limit)

        if folded_value.is_a?(Array)
          arr = folded_value.as(Array)

          if try_emit_compact_array_list_item(writer, depth, folded_key, arr, options)
            return
          end
        end
      end

      # First key-value on the same line as "- " when possible (compact form)
      first_key = keys.first
      folded_first_key, folded_first_value, first_child_enabled, first_child_limit = maybe_fold_key(first_key, obj[first_key], obj, options, folding_enabled, chain_limit)
      encoded_key = Primitives.encode_key(folded_first_key)
      first_value = folded_first_value

      if Normalizer.json_primitive?(first_value)
        writer.push(depth, "#{LIST_ITEM_PREFIX}#{encoded_key}: #{Primitives.encode_primitive(first_value, options.delimiter)}")
      elsif first_value.is_a?(Array)
        arr = first_value

        if try_emit_compact_array_list_item(writer, depth, folded_first_key, arr, options)
          # compact form emitted
        else
          if Normalizer.array_of_objects?(arr)
            # Fall back to list format for non-uniform arrays of objects
            writer.push(depth, "#{LIST_ITEM_PREFIX}#{encoded_key}[#{arr.size}]:")

            arr.each do |item|
              if item.is_a?(Hash)
                encode_object_as_list_item(item.as(Hash(String, JsonValue)), writer, depth + 2, options, first_child_enabled)
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
                encode_object_as_list_item(item.as(Hash(String, JsonValue)), writer, depth + 2, options, first_child_enabled)
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
          encode_object(first_value.as(Hash(String, JsonValue)), writer, depth + 2, options, first_child_enabled, first_child_limit)
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

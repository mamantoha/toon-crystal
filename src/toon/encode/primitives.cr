require "../constants"

module Toon
  module Primitives
    extend self

    # Primitive encoding
    def encode_primitive(value : Nil?, delimiter : String | Char = COMMA)
      NULL_LITERAL
    end

    def encode_primitive(value : Bool, delimiter : String | Char = COMMA)
      value.to_s
    end

    def encode_primitive(value : Int32, delimiter : String | Char = COMMA)
      value.to_s
    end

    def encode_primitive(value : Float32, delimiter : String | Char = COMMA)
      format_number(value)
    end

    def encode_primitive(value : Float64, delimiter : String | Char = COMMA)
      format_number(value)
    end

    def encode_primitive(value : Number, delimiter : String | Char = COMMA)
      value.to_s
    end

    def encode_primitive(value : String, delimiter : String | Char = COMMA)
      encode_string_literal(value, delimiter.to_s)
    end

    # Generic dispatch for union types
    def encode_primitive(value, delimiter : String | Char = COMMA)
      case value
      when Nil
        NULL_LITERAL
      when Bool
        value.to_s
      when String
        encode_string_literal(value, delimiter.to_s)
      when Float32, Float64
        format_number(value)
      when Int32, Int64, Number
        value.to_s
      else
        value.to_s
      end
    end

    private def format_number(n : Float)
      n.to_s
    end

    def encode_string_literal(value : String, delimiter : String = COMMA.to_s)
      if safe_unquoted?(value, delimiter)
        value
      else
        "#{DOUBLE_QUOTE}#{escape_string(value)}#{DOUBLE_QUOTE}"
      end
    end

    def escape_string(value : String)
      value
        .gsub("\\", "\\\\")
        .gsub("\"", "\\\"")
        .gsub("\n", "\\n")
        .gsub("\r", "\\r")
        .gsub("\t", "\\t")
    end

    # ameba:disable Metrics/CyclomaticComplexity
    def safe_unquoted?(value : String, delimiter : String = COMMA.to_s)
      return false if value.empty?
      return false if padded_with_whitespace?(value)
      return false if value == TRUE_LITERAL || value == FALSE_LITERAL || value == NULL_LITERAL
      return false if numeric_like?(value)
      return false if value.includes?(COLON)
      return false if value.includes?(DOUBLE_QUOTE) || value.includes?('\\')
      return false if value =~ /[\[\]{}]/
      return false if value =~ /[\n\r\t]/
      return false if value.includes?(delimiter)
      return false if value.starts_with?(LIST_ITEM_MARKER.to_s)

      true
    end

    def numeric_like?(value : String)
      # Match numbers like: 42, -3.14, 1e-6, 05, etc.
      value =~ /^-?\d+(?:\.\d+)?(?:e[+-]?\d+)?$/i || value =~ /^0\d+$/
    end

    def padded_with_whitespace?(value : String)
      value != value.strip
    end

    # Key encoding
    def encode_key(key : String)
      if valid_unquoted_key?(key)
        key
      else
        "#{DOUBLE_QUOTE}#{escape_string(key)}#{DOUBLE_QUOTE}"
      end
    end

    def valid_unquoted_key?(key : String)
      # Keys must not contain control characters or special characters
      return false if key =~ /[\n\r\t]/
      return false if key.includes?(COLON)
      return false if key.includes?(DOUBLE_QUOTE) || key.includes?('\\')
      return false if key =~ /[\[\]{}]/
      return false if key.includes?(COMMA)
      return false if key.starts_with?(LIST_ITEM_MARKER.to_s)
      return false if key.empty?
      return false if key =~ /^\d+$/   # Numeric keys
      return false if key != key.strip # Leading/trailing spaces

      key =~ /^[A-Z_][\w.]*$/i
    end

    # Value joining
    def join_encoded_values(values, delimiter : String = COMMA.to_s)
      values.each_with_object([] of String) do |v, result|
        result << encode_primitive(v, delimiter)
      end.join(delimiter)
    end

    # Header formatters
    def format_header(length : Int32, key : String? = nil, fields : Array(String)? = nil, delimiter : String = COMMA.to_s, length_marker : String | Bool = false)
      header = ""

      key.try { |k| header += encode_key(k) }

      # Only include delimiter if it's not the default (comma)
      delimiter_suffix = delimiter != DEFAULT_DELIMITER.to_s ? delimiter : ""
      length_prefix = length_marker != false ? length_marker.to_s : ""
      header += "[#{length_prefix}#{length}#{delimiter_suffix}]"

      if fields
        quoted_fields = fields.map { |field| encode_key(field) }
        header += "{#{quoted_fields.join(delimiter)}}"
      end

      header += COLON.to_s

      header
    end
  end
end

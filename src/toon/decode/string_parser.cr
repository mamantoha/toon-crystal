require "./error"

module Toon
  module Decoders
    private def key_value_line?(content : String) : Bool
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

    private def parse_primitive_token(token : String) : JsonValue
      str = trim_token_spaces(token)
      return if str == NULL_LITERAL
      return true if str == TRUE_LITERAL
      return false if str == FALSE_LITERAL

      if str.starts_with?(DOUBLE_QUOTE)
        return parse_string_literal(str)
      end

      if str.match(/^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?$/)
        if str.match(/^-?(?:0|[1-9]\d*)$/)
          return str.to_i64
        end

        float_val = str.to_f64

        if float_val == 0.0 && str.starts_with?('-')
          return 0_i64
        end

        if float_val == float_val.trunc
          return float_val.to_i64
        end

        return float_val
      end

      str
    end

    private def parse_string_literal(raw : String) : String
      s = raw.strip

      unless s.starts_with?(DOUBLE_QUOTE)
        return s
      end

      raise DecodeError.new("Unterminated string: missing closing quote") unless s.ends_with?(DOUBLE_QUOTE)

      inner = s[1, s.size - 2]

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
            when 'u'
              raise DecodeError.new("Invalid unicode escape sequence") if i + 5 >= inner.size

              hex = inner[i + 2, 4]
              unless hex =~ /^[0-9a-fA-F]{4}$/
                raise DecodeError.new("Invalid unicode escape sequence")
              end

              codepoint = hex.to_i(16)
              if codepoint >= 0xD800 && codepoint <= 0xDFFF
                raise DecodeError.new("Invalid unicode escape sequence")
              end

              io << codepoint.chr
              i += 6
              next
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

    private def find_unquoted_char_index(content : String, target : Char) : Int32?
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
          return i if ch == target
          in_quotes = true if ch == '"'
        end

        i += 1
      end

      nil
    end

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
            result << trim_token_spaces(values_str[token_start, i - token_start])
            token_start = i + 1
          end
        end
        i += 1
      end

      result << trim_token_spaces(values_str[token_start, values_str.size - token_start])
      result
    end

    private def trim_token_spaces(value : String) : String
      value.gsub(/^ +| +$/, "")
    end
  end
end

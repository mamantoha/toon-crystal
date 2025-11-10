require "../constants"
require "./error"

module Toon
  # Helper module for parsing quoted strings and handling escape sequences
  module StringParser
    extend self

    # Find the index of an unquoted character in a string
    def find_unquoted_char_index(content : String, target_char : Char) : Int32?
      i = 0
      in_quotes = false
      escaped = false

      while i < content.size
        ch = content[i]

        if in_quotes
          if !escaped && ch == DOUBLE_QUOTE
            in_quotes = false
          end
          escaped = (!escaped && ch == BACKSLASH)
        else
          return i if ch == target_char
          in_quotes = true if ch == DOUBLE_QUOTE
        end
        i += 1
      end

      nil
    end

    # Check if a string contains an unquoted character
    def contains_unquoted_char?(content : String, target_char : Char) : Bool
      find_unquoted_char_index(content, target_char) != nil
    end

    # Find the first unquoted bracket '[' in a string
    def find_unquoted_bracket_index(content : String) : Int32?
      find_unquoted_char_index(content, OPEN_BRACKET)
    end

    # Find the first unquoted colon ':' in a string
    def find_unquoted_colon_index(content : String) : Int32?
      find_unquoted_char_index(content, COLON)
    end

    # Check if a string contains an unquoted colon (key-value line detection)
    def contains_unquoted_colon?(content : String) : Bool
      contains_unquoted_char?(content, COLON)
    end

    # Parse and unescape a quoted string literal
    def parse_string_literal(raw : String) : String
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
          if ch == BACKSLASH
            raise DecodeError.new("Unterminated escape sequence") if i + 1 >= inner.size
            nxt = inner[i + 1]
            case nxt
            when 'n'          then io << NEWLINE
            when 'r'          then io << CARRIAGE_RETURN
            when 't'          then io << TAB
            when DOUBLE_QUOTE then io << DOUBLE_QUOTE
            when BACKSLASH    then io << BACKSLASH
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

    # Split a key-value line at the first unquoted colon
    def split_key_value(content : String) : {String, String}?
      colon_idx = find_unquoted_colon_index(content)
      return nil unless colon_idx

      key_raw = content[0, colon_idx]
      rest = content[colon_idx + 1, content.size - (colon_idx + 1)]
      {key_raw.strip, rest}
    end

    # Find the closing quote for a quoted string starting at a given position
    def find_closing_quote(content : String, start_pos : Int32) : Int32?
      return nil unless start_pos < content.size && content[start_pos] == DOUBLE_QUOTE

      i = start_pos + 1
      escaped = false

      while i < content.size
        ch = content[i]
        if !escaped && ch == DOUBLE_QUOTE
          return i
        end
        escaped = (!escaped && ch == BACKSLASH)
        i += 1
      end

      nil
    end
  end
end

require "./error"

module Toon
  module Decoders
    struct KeyToken
      getter value : String
      getter? quoted : Bool

      def initialize(@value : String, @quoted : Bool)
      end
    end

    # Internal representation of an array header
    struct ArrayHeader
      property key_token : KeyToken?
      property length : Int32
      property delimiter : String
      property fields : Array(String)?

      def initialize(@key_token : KeyToken?, @length : Int32, @delimiter : String, @fields : Array(String)?)
      end

      def key : String?
        @key_token.try(&.value)
      end

      def key_quoted? : Bool
        @key_token.try(&.quoted) || false
      end
    end

    private def parse_array_header_line(content : String) : {ArrayHeader, String?}?
      # pattern: optional key, then [#?len<opt delim>]{<opt fields>}:<opt inline>
      trimmed = content.lstrip

      # Check if this is just a quoted string (not a quoted key with array header)
      # A quoted key with array header would have '[' after the closing quote
      if trimmed.starts_with?(DOUBLE_QUOTE)
        # Find the closing quote
        quote_end = trimmed.index(DOUBLE_QUOTE, 1)
        if quote_end
          # Check if there's a '[' after the quoted section
          after_quote = trimmed.byte_slice(quote_end + 1).lstrip
          return unless after_quote.starts_with?('[')
        else
          # Unterminated quote, not an array header
          return
        end
      end

      key_token : KeyToken? = nil
      rest = content

      # Find the first unquoted '[' (not inside quotes)
      idx = nil
      in_quotes = false
      escaped = false
      i = 0
      while i < rest.size
        ch = rest[i]
        if in_quotes
          if !escaped && ch == '"'
            in_quotes = false
          end
          escaped = (!escaped && ch == '\\')
        else
          if ch == '['
            idx = i
            break
          end
          if ch == '"'
            in_quotes = true
          end
        end
        i += 1
      end

      # key can be quoted or unquoted up to '['
      if idx
        before = rest.byte_slice(0, idx).strip

        if !before.empty?
          if before.starts_with?(DOUBLE_QUOTE)
            key_token = KeyToken.new(parse_string_literal(before), true)
          else
            key_token = KeyToken.new(before, false)
          end
        end

        rest = rest.byte_slice(idx)
      end

      # [#?len<opt delim>]...
      return unless rest.starts_with?('[')

      # find closing bracket
      bracket_start = 0
      bracket_end = rest.index(']', bracket_start)

      return unless bracket_end

      # Optional fields braces must appear immediately after optional whitespace
      # following the closing bracket. Any other token means this is not an
      # array header and should be treated as a normal key.
      cursor = bracket_end + 1
      while cursor < rest.size && rest[cursor].ascii_whitespace?
        cursor += 1
      end

      if cursor < rest.size && rest[cursor] == '{'
        brace_end = rest.index('}', cursor)
        return unless brace_end
        cursor = brace_end + 1
      end

      while cursor < rest.size && rest[cursor].ascii_whitespace?
        cursor += 1
      end

      return unless cursor < rest.size && rest[cursor] == ':'

      colon_idx = cursor

      header_seg = rest.byte_slice(0, colon_idx)
      tail = rest.byte_slice(colon_idx + 1)

      # strip [ and ]
      close_idx = header_seg.index(']') || (header_seg.size - 1)
      inside = header_seg.byte_slice(1, close_idx - 1)

      len_and_delim = inside
      len_str = len_and_delim
      delim : String? = nil

      if len_and_delim.size > 0
        # if last char is a non-digit, treat as delimiter override
        last = len_and_delim[-1]

        if !(last.ascii_number?)
          delim = last.to_s
          len_str = len_and_delim.byte_slice(0, len_and_delim.size - 1)
        end
      end

      len_str = len_str.strip
      return unless len_str =~ /^\d+$/
      length = len_str.to_i?
      return unless length

      fields : Array(String)? = nil
      brace_idx = header_seg.index('{')

      if brace_idx
        close_brace = header_seg.rindex('}')

        if close_brace && close_brace > brace_idx
          inside_fields = header_seg.byte_slice(brace_idx + 1, close_brace - brace_idx - 1)
          # fields are key-encoded; split respecting quotes using active delimiter (fallback COMMA)
          delim_for_fields = delim || DEFAULT_DELIMITER.to_s
          tokens = parse_delimited_values(inside_fields, delim_for_fields)
          fields = tokens.map { |f| f.starts_with?(DOUBLE_QUOTE) ? parse_string_literal(f) : f }
        end
      end

      header = ArrayHeader.new(key_token, length, (delim || DEFAULT_DELIMITER.to_s), fields)

      inline_values = tail.strip.empty? ? nil : tail.strip
      {header, inline_values}
    end
  end
end

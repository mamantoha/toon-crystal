require "./error"

module Toon
  module Decoders
    struct KeyToken
      getter value : String
      getter? quoted : Bool

      def initialize(@value : String, @quoted : Bool)
      end
    end

    class FieldNode
      getter name : String
      getter children : Array(FieldNode)?

      def initialize(@name : String, @children : Array(FieldNode)? = nil)
      end

      def leaf_count : Int32
        @children.try(&.sum(&.leaf_count)) || 1
      end

      def ==(other : String)
        @children.nil? && @name == other
      end
    end

    # Internal representation of an array header
    struct ArrayHeader
      property key_token : KeyToken?
      property length : Int32
      property delimiter : String
      property fields : Array(FieldNode)?
      property? keyed : Bool

      def initialize(@key_token : KeyToken?, @length : Int32, @delimiter : String, @fields : Array(FieldNode)?, @keyed : Bool = false)
      end

      def key : String?
        @key_token.try(&.value)
      end

      def key_quoted? : Bool
        @key_token.try(&.quoted?) || false
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
          return if find_unquoted_colon_index(before)
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
        brace_end = matching_brace_index(rest, cursor)
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
      keyed = false

      if marker = len_and_delim.index(':')
        keyed = true
        len_str = len_and_delim.byte_slice(0, marker)
        return if len_str != len_str.strip
        delimiter_part = len_and_delim.byte_slice(marker + 1)
        return unless delimiter_part.empty? || delimiter_part == PIPE.to_s || delimiter_part == TAB.to_s
        delim = delimiter_part unless delimiter_part.empty?
      end

      if !keyed && len_and_delim.size > 0
        # if last char is a delimiter override, separate it from the length
        last = len_and_delim[-1]

        if delimiter_char?(last)
          delim = last.to_s
          len_str = len_and_delim.byte_slice(0, len_and_delim.size - 1)
        end
      end

      len_str = len_str.strip
      return unless len_str =~ /^(0|[1-9]\d*)$/
      length = len_str.to_i?
      return unless length

      fields : Array(FieldNode)? = nil
      brace_idx = header_seg.index('{')

      if brace_idx
        close_brace = header_seg.rindex('}')

        if close_brace && close_brace > brace_idx
          inside_fields = header_seg.byte_slice(brace_idx + 1, close_brace - brace_idx - 1)
          # fields are key-encoded; split respecting quotes using active delimiter (fallback COMMA)
          delim_for_fields = delim || DEFAULT_DELIMITER.to_s
          fields = parse_field_nodes(inside_fields, delim_for_fields)
          return if fields.nil? || fields.empty?
        end
      end

      return if keyed && fields.nil?
      header = ArrayHeader.new(key_token, length, (delim || DEFAULT_DELIMITER.to_s), fields, keyed)

      trimmed_tail = trim_token_spaces(tail)
      inline_values = trimmed_tail.empty? ? nil : trimmed_tail
      {header, inline_values}
    end

    private def delimiter_char?(ch : Char) : Bool
      ch == COMMA || ch == TAB || ch == PIPE
    end

    private def matching_brace_index(value : String, start : Int32) : Int32?
      depth = 0
      in_quotes = false
      escaped = false
      (start...value.size).each do |i|
        ch = value[i]
        if in_quotes
          in_quotes = false if !escaped && ch == '"'
          escaped = !escaped && ch == '\\'
        elsif ch == '"'
          in_quotes = true
        elsif ch == '{'
          depth += 1
        elsif ch == '}'
          depth -= 1
          return i if depth == 0
        end
      end
      nil
    end

    private def parse_field_nodes(value : String, delimiter : String) : Array(FieldNode)?
      tokens = split_field_tokens(value, delimiter)
      return unless tokens
      nodes = [] of FieldNode
      tokens.each do |token|
        return if token.empty?
        if brace = find_unquoted_char_index(token, '{')
          return unless token.ends_with?('}')
          name_token = token.byte_slice(0, brace)
          children = parse_field_nodes(token.byte_slice(brace + 1, token.size - brace - 2), delimiter)
          return if children.nil? || children.empty?
          name = name_token.starts_with?(DOUBLE_QUOTE) ? parse_string_literal(name_token) : name_token
          nodes << FieldNode.new(name, children)
        else
          name = token.starts_with?(DOUBLE_QUOTE) ? parse_string_literal(token) : token
          nodes << FieldNode.new(name)
        end
      end
      nodes
    end

    private def split_field_tokens(value : String, delimiter : String) : Array(String)?
      result = [] of String
      depth = 0
      in_quotes = false
      escaped = false
      start = 0
      value.each_char_with_index do |ch, i|
        if in_quotes
          in_quotes = false if !escaped && ch == '"'
          escaped = !escaped && ch == '\\'
        elsif ch == '"'
          in_quotes = true
        elsif ch == '{'
          depth += 1
        elsif ch == '}'
          depth -= 1
          return if depth < 0
        elsif ch == delimiter[0] && depth == 0
          result << trim_token_spaces(value.byte_slice(start, i - start))
          start = i + 1
        end
      end
      return if depth != 0 || in_quotes
      result << trim_token_spaces(value.byte_slice(start))
      result
    end
  end
end

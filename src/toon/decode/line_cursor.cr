module Toon
  # Lightweight line representation for decoding
  struct ParsedLine
    getter depth : Int32
    getter content : String
    getter line_number : Int32

    def initialize(@depth : Int32, @content : String, @line_number : Int32)
    end
  end

  # Cursor over parsed lines
  class LineCursor
    @lines : Array(ParsedLine)
    @index : Int32 = 0
    @current_line : ParsedLine?
    @blank_lines : Array(Int32)

    def initialize(@lines : Array(ParsedLine), @blank_lines : Array(Int32))
    end

    def length : Int32
      @lines.size
    end

    def at_end? : Bool
      @index >= @lines.size
    end

    def peek : ParsedLine?
      @lines[@index]?
    end

    def next : ParsedLine?
      line = @lines[@index]?

      if line
        @current_line = line
        @index += 1
      end

      line
    end

    def advance
      self.next
    end

    def current : ParsedLine?
      @current_line
    end

    def blank_lines : Array(Int32)
      @blank_lines
    end
  end
end

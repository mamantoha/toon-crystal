module Toon
  class LineWriter
    @lines : Array(String)
    @indentation_string : String

    def initialize(indent_size : Int32)
      @lines = [] of String
      @indentation_string = " " * indent_size
    end

    def push(depth : Int32, content : String)
      indent = @indentation_string * depth
      @lines << indent + content
    end

    def to_s(io : IO)
      @lines.join("\n", io)
    end

    def to_s : String
      @lines.join("\n")
    end
  end
end

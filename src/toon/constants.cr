module Toon
  # List markers
  LIST_ITEM_MARKER = '-'
  LIST_ITEM_PREFIX = "- "

  # Structural characters
  COMMA = ','
  COLON = ':'
  SPACE = ' '
  PIPE  = '|'

  # Brackets and braces
  OPEN_BRACKET  = '['
  CLOSE_BRACKET = ']'
  OPEN_BRACE    = '{'
  CLOSE_BRACE   = '}'

  # Literals
  NULL_LITERAL  = "null"
  TRUE_LITERAL  = "true"
  FALSE_LITERAL = "false"

  # Escape characters
  BACKSLASH       = '\\'
  DOUBLE_QUOTE    = '"'
  NEWLINE         = '\n'
  CARRIAGE_RETURN = '\r'
  TAB             = '\t'

  DEFAULT_DELIMITER = COMMA

  enum ExpandPathsMode
    Off
    Safe

    def safe?
      self == Safe
    end

    def self.parse(value : String) : self
      case value.downcase
      when "off"
        Off
      when "safe"
        Safe
      else
        raise ArgumentError.new("Unknown expandPaths mode: #{value}")
      end
    end

    def self.parse(value : Symbol) : self
      parse(value.to_s)
    end
  end

  enum KeyFoldingMode
    Off
    Safe

    def safe?
      self == Safe
    end

    def self.parse(value : String) : self
      case value.downcase
      when "off"
        Off
      when "safe"
        Safe
      else
        raise ArgumentError.new("Unknown keyFolding mode: #{value}")
      end
    end

    def self.parse(value : Symbol) : self
      parse(value.to_s)
    end
  end
end

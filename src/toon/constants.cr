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

  # Shared type alias used by both encoder and decoder
  alias JsonValue = Bool | Int64 | Float64 | String | Array(JsonValue) | Hash(String, JsonValue)?
end

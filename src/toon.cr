require "./toon/version"
require "./toon/constants"
require "./toon/writer"
require "./toon/normalizer"
require "./toon/primitives"
require "./toon/encoders"

module Toon
  extend self

  # Encode any value to TOON format
  #
  # @param input : Any value to encode
  # @param indent : Number of spaces per indentation level (default: 2)
  # @param delimiter : Delimiter for array values and tabular rows (default: ',')
  # @param length_marker : Optional marker to prefix array lengths (default: false)
  # @return : TOON-formatted string
  def encode(input, indent : Int32 = 2, delimiter : String | Char = DEFAULT_DELIMITER, length_marker : String | Bool = false)
    normalized_value = Normalizer.normalize_value(input)
    options = resolve_options(indent: indent, delimiter: delimiter, length_marker: length_marker)
    Encoders.encode_value(normalized_value, options)
  end

  private def resolve_options(indent : Int32, delimiter : String | Char, length_marker : String | Bool)
    {
      indent:        indent,
      delimiter:     delimiter.to_s,
      length_marker: length_marker,
    }
  end
end

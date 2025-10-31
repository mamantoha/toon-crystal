require "./toon/version"
require "./toon/constants"
require "./toon/encode/encoders"
require "./toon/encode/normalizer"
require "./toon/encode/primitives"
require "./toon/encode/writer"
require "./toon/decode/decoders"

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

  # Decode TOON-formatted string to a Crystal value
  #
  # @param input : TOON-formatted string
  # @param indent : Number of spaces per indentation level (default: 2)
  # @param strict : Whether to enable strict validations (currently minimal)
  # @return : Decoded Crystal value
  def decode(input : String, indent : Int32 = 2, strict : Bool = true)
    Decoders.decode_value(input, indent, strict)
  end

  private def resolve_options(indent : Int32, delimiter : String | Char, length_marker : String | Bool)
    {
      indent:        indent,
      delimiter:     delimiter.to_s,
      length_marker: length_marker,
    }
  end
end

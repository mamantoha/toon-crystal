require "./toon/version"
require "./toon/constants"
require "./toon/encode/options"
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
  # @return : TOON-formatted string
  def encode(input, indent : Int32 = 2, delimiter : String | Char = DEFAULT_DELIMITER)
    validate_indent!(indent)
    delimiter = delimiter.to_s
    validate_delimiter!(delimiter)
    normalized_value = Normalizer.normalize_value(input)
    options = EncodeOptions.new(indent, delimiter)
    Encoders.encode_value(normalized_value, options)
  end

  # Decode TOON-formatted string to a Crystal value
  #
  # @param input : TOON-formatted string
  # @param indent : Number of spaces per indentation level (default: 2)
  # @param strict : Enable strict validations (indentation, no tabs, no blank lines inside arrays, exact counts) (default: true)
  # @return : Decoded Crystal value
  def decode(input : String, indent : Int32 = 2, strict : Bool = true)
    validate_indent!(indent)
    Decoders.decode_value(input, indent, strict)
  end

  private def validate_indent!(indent : Int32)
    raise ArgumentError.new("indent must be greater than 0") unless indent > 0
  end

  private def validate_delimiter!(delimiter : String)
    return if delimiter == COMMA.to_s || delimiter == TAB.to_s || delimiter == PIPE.to_s

    raise ArgumentError.new("delimiter must be comma, tab, or pipe")
  end
end

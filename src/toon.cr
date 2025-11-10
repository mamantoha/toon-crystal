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
  def encode(input, indent : Int32 = 2, delimiter : String | Char = DEFAULT_DELIMITER, length_marker : String | Bool = false, key_folding : String | Symbol = "off", flatten_depth : Int32? = nil)
    normalized_value = Normalizer.normalize_value(input)
    options = resolve_options(
      indent: indent,
      delimiter: delimiter,
      length_marker: length_marker,
      key_folding: key_folding,
      flatten_depth: flatten_depth
    )
    Encoders.encode_value(normalized_value, options)
  end

  # Decode TOON-formatted string to a Crystal value
  #
  # @param input : TOON-formatted string
  # @param indent : Number of spaces per indentation level (default: 2)
  # @param strict : Whether to enable strict validations (currently minimal)
  # @return : Decoded Crystal value
  def decode(input : String, indent : Int32 = 2, strict : Bool = true, expand_paths : ExpandPathsMode = ExpandPathsMode::Off)
    Decoders.decode_value(input, indent, strict, expand_paths)
  end

  private def resolve_options(indent : Int32, delimiter : String | Char, length_marker : String | Bool, key_folding : String | Symbol, flatten_depth : Int32?)
    {
      indent:        indent,
      delimiter:     delimiter.to_s,
      length_marker: length_marker,
      key_folding:   normalize_key_folding(key_folding),
      flatten_depth: flatten_depth,
      flatten_limit: flatten_depth ? flatten_depth : Int32::MAX,
    }
  end

  private def normalize_key_folding(mode : String | Symbol) : String
    case mode.to_s.downcase
    when "safe"
      "safe"
    else
      "off"
    end
  end
end

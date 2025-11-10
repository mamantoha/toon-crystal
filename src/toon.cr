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
  # @param key_folding : Key folding mode (KeyFoldingMode::Off | KeyFoldingMode::Safe), default: Off
  # @param flatten_depth : Max number of segments to fold when key_folding is Safe (nil = Infinity)
  # @return : TOON-formatted string
  def encode(input, indent : Int32 = 2, delimiter : String | Char = DEFAULT_DELIMITER, key_folding : KeyFoldingMode = KeyFoldingMode::Off, flatten_depth : Int32? = nil)
    normalized_value = Normalizer.normalize_value(input)
    options = resolve_options(
      indent: indent,
      delimiter: delimiter,
      key_folding: key_folding,
      flatten_depth: flatten_depth
    )
    Encoders.encode_value(normalized_value, options)
  end

  # Decode TOON-formatted string to a Crystal value
  #
  # @param input : TOON-formatted string
  # @param indent : Number of spaces per indentation level (default: 2)
  # @param strict : Enable strict validations (indentation, no tabs, no blank lines inside arrays, exact counts) (default: true)
  # @param expand_paths : Path expansion mode (ExpandPathsMode::Off | ExpandPathsMode::Safe), default: Off
  # @return : Decoded Crystal value
  def decode(input : String, indent : Int32 = 2, strict : Bool = true, expand_paths : ExpandPathsMode = ExpandPathsMode::Off)
    Decoders.decode_value(input, indent, strict, expand_paths)
  end

  private def resolve_options(indent : Int32, delimiter : String | Char, key_folding : KeyFoldingMode, flatten_depth : Int32?)
    {
      indent:           indent,
      delimiter:        delimiter.to_s,
      key_folding_mode: key_folding,
      flatten_depth:    flatten_depth,
      flatten_limit:    flatten_depth ? flatten_depth : Int32::MAX,
    }
  end
end

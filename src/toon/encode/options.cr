require "../constants"

module Toon
  struct EncodeOptions
    getter indent : Int32
    getter delimiter : String
    getter key_folding_mode : KeyFoldingMode
    getter flatten_depth : Int32?
    getter flatten_limit : Int32

    def initialize(@indent : Int32, @delimiter : String, @key_folding_mode : KeyFoldingMode, @flatten_depth : Int32?)
      @flatten_limit = @flatten_depth || Int32::MAX
    end
  end
end

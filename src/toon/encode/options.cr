require "../constants"

module Toon
  struct EncodeOptions
    getter indent : Int32
    getter delimiter : String

    def initialize(@indent : Int32, @delimiter : String)
    end
  end
end

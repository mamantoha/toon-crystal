require "../constants"
require "time"

module Toon
  module Normalizer
    extend self

    # Normalization (unknown → JSON-compatible value)
    def normalize_value(value)
      case value
      when Nil
        nil
      when String
        value
      when Bool
        value
      when Int32, Int64
        value
      when Float32, Float64
        # -0.0 becomes 0
        return 0 if value == 0.0 && (1.0 / value) < 0

        # NaN and Infinity become nil
        return nil unless value.finite?

        value
      when Symbol
        value.to_s
      when Time
        value.to_utc.to_s("%Y-%m-%dT%H:%M:%SZ")
      when Array
        normalize_array(value)
      when Hash
        normalize_hash(value)
      else
        # Fallback: anything else becomes nil (functions, etc.)
      end
    end

    private def normalize_array(array : Array)
      result = [] of typeof(normalize_value(array[0]? || 0))

      array.each { |v| result << normalize_value(v) }

      result
    end

    private def normalize_hash(hash : Hash)
      result = {} of String => typeof(normalize_value(hash.values.first? || 0))

      hash.each { |k, v| result[k.to_s] = normalize_value(v) }

      result
    end

    # Type guards
    def json_primitive?(value)
      value.nil? ||
        value.is_a?(String) ||
        value.is_a?(Number) ||
        value.is_a?(Bool)
    end

    def json_array?(value)
      value.is_a?(Array)
    end

    def json_object?(value)
      value.is_a?(Hash)
    end

    # Array type detection
    def array_of_primitives?(value)
      return false unless value.is_a?(Array)

      value.all? { |item| json_primitive?(item) }
    end

    def array_of_arrays?(value)
      return false unless value.is_a?(Array)

      value.all? { |item| json_array?(item) }
    end

    def array_of_objects?(value)
      return false unless value.is_a?(Array)

      value.all? { |item| json_object?(item) }
    end
  end
end

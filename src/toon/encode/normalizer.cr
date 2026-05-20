require "../constants"
require "../decode/decoders"
require "time"

module Toon
  module Normalizer
    extend self

    # Normalization (unknown → JSON-compatible value)
    def normalize_value(value)
      # Handle JsonValue types first (before Array/Hash checks)
      if value.is_a?(JsonValue)
        if value.is_a?(Array)
          return normalize_array(value.as(Array))
        elsif value.is_a?(Hash)
          return normalize_hash(value.as(Hash))
        else
          # Primitive JsonValue, return as-is but ensure correct types
          case value
          when Int32
            return value.to_i64.as(JsonValue)
          when Float32
            return value.to_f64.as(JsonValue)
          else
            return value.as(JsonValue)
          end
        end
      end

      # Normal normalization for non-JsonValue types
      case value
      when Nil
        nil
      when String
        value
      when Bool
        value
      when Int32
        value.to_i64
      when Int64
        value
      when Float32
        # -0.0 becomes 0
        return 0_i64 if value == 0.0 && (1.0 / value) < 0
        # NaN and Infinity become nil
        return unless value.finite?
        value.to_f64
      when Float64
        # -0.0 becomes 0
        return 0_i64 if value == 0.0 && (1.0 / value) < 0
        # NaN and Infinity become nil
        return unless value.finite?
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
        nil
      end
    end

    private def normalize_array(array : Array) : JsonValue
      result = [] of JsonValue
      array.each do |v|
        normalized = normalize_value(v)
        case normalized
        when JsonValue
          result << normalized
        when Int32
          result << normalized.to_i64
        when Float32
          result << normalized.to_f64
        when Array
          result << normalize_array(normalized).as(JsonValue)
        when Hash
          result << normalize_hash(normalized).as(JsonValue)
        else
          result << normalized.as(JsonValue)
        end
      end
      result.as(JsonValue)
    end

    private def normalize_hash(hash : Hash) : JsonValue
      result = {} of String => JsonValue
      hash.each do |k, v|
        normalized = normalize_value(v)
        case normalized
        when JsonValue
          result[k.to_s] = normalized
        when Int32
          result[k.to_s] = normalized.to_i64
        when Float32
          result[k.to_s] = normalized.to_f64
        when Array
          result[k.to_s] = normalize_array(normalized).as(JsonValue)
        when Hash
          result[k.to_s] = normalize_hash(normalized).as(JsonValue)
        else
          result[k.to_s] = normalized.as(JsonValue)
        end
      end
      result.as(JsonValue)
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

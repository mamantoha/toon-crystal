require "../constants"
require "../decode/decoders"
require "time"

module Toon
  module Normalizer
    extend self

    # Normalization (unknown → JSON-compatible value)
    def normalize_value(value)
      # Handle JsonValue types first (before Array/Hash checks)
      if value.is_a?(Decoders::JsonValue)
        if value.is_a?(Array)
          return normalize_array(value.as(Array))
        elsif value.is_a?(Hash)
          return normalize_hash(value.as(Hash))
        else
          # Primitive JsonValue, return as-is but ensure correct types
          case value
          when Int32
            return value.to_i64.as(Decoders::JsonValue)
          when Float32
            return value.to_f64.as(Decoders::JsonValue)
          else
            return value.as(Decoders::JsonValue)
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
        return nil unless value.finite?
        value.to_f64
      when Float64
        # -0.0 becomes 0
        return 0_i64 if value == 0.0 && (1.0 / value) < 0
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
        nil
      end
    end

    private def normalize_array(array : Array) : Decoders::JsonValue
      # Handle JsonValue arrays explicitly
      if array.is_a?(Array(Decoders::JsonValue))
        result = [] of Decoders::JsonValue
        array.each do |v|
          normalized = normalize_value(v)
          # Convert to JsonValue-compatible type
          case normalized
          when Decoders::JsonValue
            result << normalized
          when Int32
            result << normalized.to_i64
          when Float32
            result << normalized.to_f64
          when Array
            result << normalize_array(normalized).as(Decoders::JsonValue)
          when Hash
            result << normalize_hash(normalized).as(Decoders::JsonValue)
          else
            result << normalized.as(Decoders::JsonValue)
          end
        end
        return result.as(Decoders::JsonValue)
      end

      # For other arrays, normalize and cast to JsonValue
      result = [] of Decoders::JsonValue
      array.each do |v|
        normalized = normalize_value(v)
        case normalized
        when Decoders::JsonValue
          result << normalized
        when Int32
          result << normalized.to_i64
        when Float32
          result << normalized.to_f64
        when Array
          result << normalize_array(normalized).as(Decoders::JsonValue)
        when Hash
          result << normalize_hash(normalized).as(Decoders::JsonValue)
        else
          result << normalized.as(Decoders::JsonValue)
        end
      end
      result.as(Decoders::JsonValue)
    end

    private def normalize_hash(hash : Hash) : Decoders::JsonValue
      # Handle JsonValue hashes explicitly
      if hash.is_a?(Hash(String, Decoders::JsonValue))
        result = {} of String => Decoders::JsonValue
        hash.each do |k, v|
          normalized = normalize_value(v)
          # Convert to JsonValue-compatible type
          case normalized
          when Decoders::JsonValue
            result[k.to_s] = normalized
          when Int32
            result[k.to_s] = normalized.to_i64
          when Float32
            result[k.to_s] = normalized.to_f64
          when Array
            result[k.to_s] = normalize_array(normalized).as(Decoders::JsonValue)
          when Hash
            result[k.to_s] = normalize_hash(normalized).as(Decoders::JsonValue)
          else
            result[k.to_s] = normalized.as(Decoders::JsonValue)
          end
        end
        return result.as(Decoders::JsonValue)
      end

      # For other hashes, normalize and cast to JsonValue
      result = {} of String => Decoders::JsonValue
      hash.each do |k, v|
        normalized = normalize_value(v)
        case normalized
        when Decoders::JsonValue
          result[k.to_s] = normalized
        when Int32
          result[k.to_s] = normalized.to_i64
        when Float32
          result[k.to_s] = normalized.to_f64
        when Array
          result[k.to_s] = normalize_array(normalized).as(Decoders::JsonValue)
        when Hash
          result[k.to_s] = normalize_hash(normalized).as(Decoders::JsonValue)
        else
          result[k.to_s] = normalized.as(Decoders::JsonValue)
        end
      end
      result.as(Decoders::JsonValue)
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

require "json"
require "../src/toon"
require "./spec_helper"

module FixtureHelper
  extend self

  FIXTURES_DIR = File.join(__DIR__, "..", "ext", "spec", "tests", "fixtures")

  # List all fixture files in a category directory
  def list_fixture_files(category : String) : Array(String)
    dir = File.join(FIXTURES_DIR, category)
    return [] of String unless Dir.exists?(dir)

    Dir.children(dir)
      .select(&.ends_with?(".json"))
      .sort!
  end

  # Load a fixture file and return parsed JSON
  def load_fixture(category : String, filename : String) : JSON::Any
    path = File.join(FIXTURES_DIR, category, filename)
    content = File.read(path)

    # Pre-process JSON to handle very large integers (beyond Int64::MAX)
    # Convert them to float notation so Crystal's JSON parser can handle them
    processed_content = content.gsub(/:\s*(\d{19,})/, ": \\1.0")

    JSON.parse(processed_content)
  end

  # Convert JSON::Any to Crystal value (for encode input)
  def json_to_crystal(json : JSON::Any) : Toon::Decoders::JsonValue
    case json.raw
    when Nil
      nil
    when Bool
      json.as_bool
    when Int64, Int32
      json.as_i64
    when Float64, Float32
      json.as_f.to_f64
    when String
      json.as_s
    when Array(JSON::Any)
      json.as_a.map { |item| json_to_crystal(item) }
    when Hash(String, JSON::Any)
      result = {} of String => Toon::Decoders::JsonValue
      json.as_h.each do |k, v|
        result[k] = json_to_crystal(v)
      end
      result
    else
      # Handle large integers that might be stored as strings in JSON
      # (Crystal's JSON parser may fail on very large integers)
      if json.to_s.to_i64?
        json.to_s.to_i64
      elsif json.to_s.to_f64?
        json.to_s.to_f64
      else
        raise "Unexpected JSON type: #{json.raw.class} (#{json})"
      end
    end
  rescue JSON::ParseException
    # If JSON parsing failed due to large integer, try parsing as string then converting
    str = json.to_s
    if str.to_i64?
      str.to_i64
    elsif str.to_f64?
      str.to_f64
    else
      raise "Failed to parse JSON value: #{json}"
    end
  end

  # Compare two JSON values for equality
  def json_equal?(actual : Toon::Decoders::JsonValue, expected : JSON::Any) : Bool
    case expected.raw
    when Nil
      actual.nil?
    when Bool
      actual.is_a?(Bool) && actual == expected.as_bool
    when Int64, Int32
      actual.is_a?(Int64) && actual == expected.as_i64
    when Float64, Float32
      expected_f = expected.as_f.to_f64
      if actual.is_a?(Float64)
        (actual - expected_f).abs < 0.000000000000001
      elsif actual.is_a?(Int64) && expected_f.to_i64 == actual
        true
      else
        false
      end
    when String
      actual.is_a?(String) && actual == expected.as_s
    when Array(JSON::Any)
      return false unless actual.is_a?(Array)
      actual_arr = actual.as(Array(Toon::Decoders::JsonValue))
      expected_arr = expected.as_a
      return false unless actual_arr.size == expected_arr.size
      actual_arr.each_with_index do |item, i|
        return false unless json_equal?(item, expected_arr[i])
      end
      true
    when Hash(String, JSON::Any)
      return false unless actual.is_a?(Hash)
      actual_hash = actual.as(Hash(String, Toon::Decoders::JsonValue))
      expected_hash = expected.as_h
      return false unless actual_hash.size == expected_hash.size
      expected_hash.each do |k, v|
        return false unless actual_hash.has_key?(k)
        return false unless json_equal?(actual_hash[k], v)
      end
      true
    else
      false
    end
  end

  # Convert JSON::Any to Crystal value for Toon.encode input (can be primitive, hash, or array)
  def json_to_encode_input(json : JSON::Any) : Toon::Decoders::JsonValue
    json_to_crystal(json)
  end

  # Get options from JSON test case
  def extract_options(test_case : JSON::Any) : Hash(String, JSON::Any)
    if test_case.as_h.has_key?("options")
      test_case["options"].as_h
    else
      {} of String => JSON::Any
    end
  end

  # Get delimiter from options
  def get_delimiter(options : Hash(String, JSON::Any)) : String
    if options.has_key?("delimiter")
      delimiter = options["delimiter"].as_s
      delimiter == "\t" ? "\t" : delimiter
    else
      ","
    end
  end

  # Get indent from options
  def get_indent(options : Hash(String, JSON::Any)) : Int32
    if options.has_key?("indent")
      options["indent"].as_i64.to_i32
    else
      2
    end
  end

  # Get strict from options
  def get_strict(options : Hash(String, JSON::Any)) : Bool
    if options.has_key?("strict")
      options["strict"].as_bool
    else
      true
    end
  end

  # Get length_marker from options
  def get_length_marker(options : Hash(String, JSON::Any)) : String | Bool
    if options.has_key?("lengthMarker")
      marker = options["lengthMarker"].as_s
      marker.empty? ? false : marker
    else
      false
    end
  end

  # Normalize TOON string (handle \n in expected strings)
  def normalize_toon_string(str : String) : String
    str.gsub("\\n", "\n")
  end
end

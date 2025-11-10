require "./spec_helper"

describe "TOON Encoding Fixtures" do
  fixture_files = FixtureHelper.list_fixture_files("encode")

  fixture_files.each do |filename|
    describe filename do
      fixture = FixtureHelper.load_fixture("encode", filename)
      category = fixture["category"].as_s
      description = fixture["description"].as_s
      tests = fixture["tests"].as_a

      describe description do
        tests.each do |test_case|
          it test_case["name"].as_s do
            name = test_case["name"].as_s
            input = test_case["input"]
            expected = test_case["expected"].as_s
            should_error = test_case.as_h.fetch("shouldError", JSON::Any.new(false)).as_bool
            options = FixtureHelper.extract_options(test_case)

            # Extract options
            delimiter = FixtureHelper.get_delimiter(options)
            indent = FixtureHelper.get_indent(options)
            length_marker = FixtureHelper.get_length_marker(options)
            key_folding = FixtureHelper.get_key_folding(options)
            flatten_depth = FixtureHelper.get_flatten_depth(options)

            # Convert input to Crystal value (can be primitive, hash, array)
            input_value = FixtureHelper.json_to_encode_input(input)

            # Run encode
            if should_error
              expect_raises(Exception) do
                Toon.encode(
                  input_value,
                  indent: indent,
                  delimiter: delimiter,
                  length_marker: length_marker,
                  key_folding: key_folding,
                  flatten_depth: flatten_depth
                )
              end
            else
              result = Toon.encode(
                input_value,
                indent: indent,
                delimiter: delimiter,
                length_marker: length_marker,
                key_folding: key_folding,
                flatten_depth: flatten_depth
              )
              result.should eq(expected), "Category: #{category}\nDescription: #{description}\nTest: #{name}\nExpected: #{expected}\nGot: #{result}"
            end
          end
        end
      end
    end
  end
end

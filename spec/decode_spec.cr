require "./spec_helper"

describe "TOON Decoding Fixtures" do
  fixture_files = FixtureHelper.list_fixture_files("decode")

  fixture_files.each do |filename|
    describe filename do
      fixture = FixtureHelper.load_fixture("decode", filename)
      category = fixture["category"].as_s
      description = fixture["description"].as_s
      tests = fixture["tests"].as_a

      describe description do
        tests.each do |test_case|
          it test_case["name"].as_s do
            name = test_case["name"].as_s
            input = test_case["input"].as_s
            expected = test_case["expected"]
            should_error = test_case.as_h.fetch("shouldError", JSON::Any.new(false)).as_bool
            options = FixtureHelper.extract_options(test_case)

            # Extract options
            indent = FixtureHelper.get_indent(options)
            strict = FixtureHelper.get_strict(options)

            # Run decode
            if should_error
              expect_raises(Toon::DecodeError) do
                Toon.decode(input, indent: indent, strict: strict)
              end
            else
              result = Toon.decode(input, indent: indent, strict: strict)
              FixtureHelper.json_equal?(result, expected).should be_true, "Category: #{category}\nDescription: #{description}\nTest: #{name}\nExpected: #{expected}\nGot: #{result}"
            end
          end
        end
      end
    end
  end
end

require "./spec_helper"
require "../src/toon"

describe Toon do
  describe "primitives" do
    it "decodes safe unquoted strings" do
      Toon.decode("hello").should eq("hello")
      Toon.decode("Ada_99").should eq("Ada_99")
    end

    it "decodes quoted strings and unescapes control characters" do
      Toon.decode("\"\"").should eq("")
      Toon.decode("\"line1\\nline2\"").should eq("line1\nline2")
      Toon.decode("\"tab\\there\"").should eq("tab\there")
      Toon.decode("\"return\\rcarriage\"").should eq("return\rcarriage")
      Toon.decode("\"C:\\\\Users\\\\path\"").should eq("C:\\Users\\path")
      Toon.decode("\"say \\\"hello\\\"\"").should eq("say \"hello\"")
    end

    it "decodes unicode and emoji" do
      Toon.decode("café").should eq("café")
      Toon.decode("你好").should eq("你好")
      Toon.decode("🚀").should eq("🚀")
      Toon.decode("hello 👋 world").should eq("hello 👋 world")
    end

    it "decodes numbers, booleans and null" do
      Toon.decode("42").should eq(42_i64)
      Toon.decode("3.14").should eq(3.14)
      Toon.decode("-7").should eq(-7_i64)
      Toon.decode("true").should be_true
      Toon.decode("false").should be_false
      Toon.decode("null").should be_nil
    end

    it "treats unquoted invalid numeric formats as strings" do
      Toon.decode("05").should eq("05")
      Toon.decode("007").should eq("007")
      Toon.decode("0123").should eq("0123")
      Toon.decode("a: 05").should eq({"a" => "05"})
      Toon.decode("nums[3]: 05,007,0123").should eq({"nums" => ["05", "007", "0123"]})
    end

    it "respects ambiguity quoting (quoted primitives remain strings)" do
      Toon.decode("\"true\"").should eq("true")
      Toon.decode("\"false\"").should eq("false")
      Toon.decode("\"null\"").should eq("null")
      Toon.decode("\"42\"").should eq("42")
      Toon.decode("\"-3.14\"").should eq("-3.14")
      Toon.decode("\"1e-6\"").should eq("1e-6")
      Toon.decode("\"05\"").should eq("05")
    end
  end

  describe "objects (simple)" do
    it "parses objects with primitive values" do
      toon = "id: 123\nname: Ada\nactive: true"
      Toon.decode(toon).should eq({"id" => 123_i64, "name" => "Ada", "active" => true})
    end

    it "parses null values in objects" do
      toon = "id: 123\nvalue: null"
      Toon.decode(toon).should eq({"id" => 123_i64, "value" => nil})
    end

    it "parses empty nested object header" do
      Toon.decode("user:").should eq({"user" => {} of String => Toon::Decoders::JsonValue})
    end

    it "parses quoted object values with special characters and escapes" do
      Toon.decode("note: \"a:b\"").should eq({"note" => "a:b"})
      Toon.decode("note: \"a,b\"").should eq({"note" => "a,b"})
      Toon.decode("text: \"line1\\nline2\"").should eq({"text" => "line1\nline2"})
      Toon.decode("text: \"say \\\"hello\\\"\"").should eq({"text" => "say \"hello\""})
      Toon.decode("text: \" padded \"").should eq({"text" => " padded "})
      Toon.decode("text: \"  \"").should eq({"text" => "  "})
      Toon.decode("v: \"true\"").should eq({"v" => "true"})
      Toon.decode("v: \"42\"").should eq({"v" => "42"})
      Toon.decode("v: \"-7.5\"").should eq({"v" => "-7.5"})
    end
  end

  describe "objects (keys)" do
    it "parses quoted keys with special characters and escapes" do
      Toon.decode("\"order:id\": 7").should eq({"order:id" => 7_i64})
      Toon.decode("\"[index]\": 5").should eq({"[index]" => 5_i64})
      Toon.decode("\"{key}\": 5").should eq({"{key}" => 5_i64})
      Toon.decode("\"a,b\": 1").should eq({"a,b" => 1_i64})
      Toon.decode("\"full name\": Ada").should eq({"full name" => "Ada"})
      Toon.decode("\"-lead\": 1").should eq({"-lead" => 1_i64})
      Toon.decode("\" a \": 1").should eq({" a " => 1_i64})
      Toon.decode("\"123\": x").should eq({"123" => "x"})
      Toon.decode("\"\": 1").should eq({"" => 1_i64})
    end

    it "parses dotted keys as identifiers" do
      Toon.decode("user.name: Ada").should eq({"user.name" => "Ada"})
      Toon.decode("_private: 1").should eq({"_private" => 1_i64})
      Toon.decode("user_name: 1").should eq({"user_name" => 1_i64})
    end

    it "unescapes control characters and quotes in keys" do
      Toon.decode("\"line\\nbreak\": 1").should eq({"line\nbreak" => 1_i64})
      Toon.decode("\"tab\\there\": 2").should eq({"tab\there" => 2_i64})
      Toon.decode("\"he said \\\"hi\\\"\": 1").should eq({"he said \"hi\"" => 1_i64})
    end
  end

  describe "nested objects" do
    it "parses deeply nested objects with indentation" do
      toon = "a:\n  b:\n    c: deep"
      Toon.decode(toon).should eq({"a" => {"b" => {"c" => "deep"}}})
    end
  end

  describe "arrays of primitives" do
    it "parses string arrays inline" do
      toon = "tags[3]: reading,gaming,coding"
      Toon.decode(toon).should eq({"tags" => ["reading", "gaming", "coding"]})
    end

    it "parses number arrays inline" do
      toon = "nums[3]: 1,2,3"
      Toon.decode(toon).should eq({"nums" => [1_i64, 2_i64, 3_i64]})
    end

    it "parses mixed primitive arrays inline" do
      toon = "data[4]: x,y,true,10"
      Toon.decode(toon).should eq({"data" => ["x", "y", true, 10_i64]})
    end

    it "parses empty arrays" do
      Toon.decode("items[0]:").should eq({"items" => [] of Toon::Decoders::JsonValue})
    end

    it "parses quoted strings in arrays including empty and whitespace-only" do
      Toon.decode("items[1]: \"\"").should eq({"items" => [""]})
      Toon.decode("items[3]: a,\"\",b").should eq({"items" => ["a", "", "b"]})
      Toon.decode("items[2]: \" \",\"  \"").should eq({"items" => [" ", "  "]})
    end

    it "parses strings with delimiters and structural tokens in arrays" do
      Toon.decode("items[3]: a,\"b,c\",\"d:e\"").should eq({"items" => ["a", "b,c", "d:e"]})
      Toon.decode("items[4]: x,\"true\",\"42\",\"-3.14\"").should eq({"items" => ["x", "true", "42", "-3.14"]})
      Toon.decode("items[3]: \"[5]\",\"- item\",\"{key}\"").should eq({"items" => ["[5]", "- item", "{key}"]})
    end
  end

  describe "arrays of objects (tabular and list items)" do
    it "parses tabular arrays of uniform objects" do
      toon = "items[2]{sku,qty,price}:\n  A1,2,9.99\n  B2,1,14.5"
      Toon.decode(toon).should eq({
        "items" => [
          {"sku" => "A1", "qty" => 2_i64, "price" => 9.99},
          {"sku" => "B2", "qty" => 1_i64, "price" => 14.5},
        ],
      })
    end

    it "parses nulls and quoted values in tabular rows" do
      toon = "items[2]{id,value}:\n  1,null\n  2,\"test\""
      Toon.decode(toon).should eq({
        "items" => [
          {"id" => 1_i64, "value" => nil},
          {"id" => 2_i64, "value" => "test"},
        ],
      })
    end

    it "parses quoted header keys in tabular arrays" do
      toon = "items[2]{\"order:id\",\"full name\"}:\n  1,Ada\n  2,Bob"
      Toon.decode(toon).should eq({
        "items" => [
          {"order:id" => 1_i64, "full name" => "Ada"},
          {"order:id" => 2_i64, "full name" => "Bob"},
        ],
      })
    end

    it "parses list arrays for non-uniform objects" do
      toon = "items[2]:\n  - id: 1\n    name: First\n  - id: 2\n    name: Second\n    extra: true"
      Toon.decode(toon).should eq({
        "items" => [
          {"id" => 1_i64, "name" => "First"},
          {"id" => 2_i64, "name" => "Second", "extra" => true},
        ],
      })
    end

    it "parses objects with nested values inside list items" do
      toon = "items[1]:\n  - id: 1\n    nested:\n      x: 1"
      Toon.decode(toon).should eq({"items" => [{"id" => 1_i64, "nested" => {"x" => 1_i64}}]})
    end

    it "parses nested tabular arrays as first field on hyphen line" do
      toon = "items[1]:\n  - users[2]{id,name}:\n    1,Ada\n    2,Bob\n    status: active"
      Toon.decode(toon).should eq({
        "items" => [{
          "users" => [
            {"id" => 1_i64, "name" => "Ada"},
            {"id" => 2_i64, "name" => "Bob"},
          ],
          "status" => "active",
        }],
      })
    end

    it "parses objects containing arrays (including empty arrays) in list format" do
      toon = "items[1]:\n  - name: test\n    data[0]:"
      Toon.decode(toon).should eq({"items" => [{"name" => "test", "data" => [] of Toon::Decoders::JsonValue}]})
    end

    it "parses arrays of arrays within objects" do
      toon = "items[1]:\n  - matrix[2]:\n    - [2]: 1,2\n    - [2]: 3,4\n    name: grid"
      Toon.decode(toon).should eq({"items" => [{"matrix" => [[1_i64, 2_i64], [3_i64, 4_i64]], "name" => "grid"}]})
    end
  end

  describe "arrays of arrays (primitives only)" do
    it "parses nested arrays of primitives" do
      toon = "pairs[2]:\n  - [2]: a,b\n  - [2]: c,d"
      Toon.decode(toon).should eq({"pairs" => [["a", "b"], ["c", "d"]]})
    end

    it "parses quoted strings and mixed lengths in nested arrays" do
      toon = "pairs[2]:\n  - [2]: a,b\n  - [3]: \"c,d\",\"e:f\",\"true\""
      Toon.decode(toon).should eq({"pairs" => [["a", "b"], ["c,d", "e:f", "true"]]})
    end

    it "parses empty inner arrays" do
      toon = "pairs[2]:\n  - [0]:\n  - [0]:"
      Toon.decode(toon).should eq({"pairs" => [([] of Toon::Decoders::JsonValue), ([] of Toon::Decoders::JsonValue)]})
    end

    it "parses mixed-length inner arrays" do
      toon = "pairs[2]:\n  - [1]: 1\n  - [2]: 2,3"
      Toon.decode(toon).should eq({"pairs" => [[1_i64], [2_i64, 3_i64]]})
    end
  end

  describe "root arrays" do
    it "parses root arrays of primitives (inline)" do
      toon = "[5]: x,y,\"true\",true,10"
      Toon.decode(toon).should eq(["x", "y", "true", true, 10_i64])
    end

    it "parses root arrays of uniform objects in tabular format" do
      toon = "[2]{id}:\n  1\n  2"
      Toon.decode(toon).should eq([{"id" => 1_i64}, {"id" => 2_i64}])
    end

    it "parses root arrays of non-uniform objects in list format" do
      toon = "[2]:\n  - id: 1\n  - id: 2\n    name: Ada"
      Toon.decode(toon).should eq([{"id" => 1_i64}, {"id" => 2_i64, "name" => "Ada"}])
    end

    it "parses empty root arrays" do
      Toon.decode("[0]:").should eq([] of Toon::Decoders::JsonValue)
    end

    it "parses root arrays of arrays" do
      toon = "[2]:\n  - [2]: 1,2\n  - [0]:"
      Toon.decode(toon).should eq([[1_i64, 2_i64], [] of Toon::Decoders::JsonValue])
    end
  end

  describe "complex structures" do
    it "parses mixed objects with arrays and nested objects" do
      toon = "user:\n  id: 123\n  name: Ada\n  tags[2]: reading,gaming\n  active: true\n  prefs[0]:"
      Toon.decode(toon).should eq({
        "user" => {
          "id"     => 123_i64,
          "name"   => "Ada",
          "tags"   => ["reading", "gaming"],
          "active" => true,
          "prefs"  => [] of Toon::Decoders::JsonValue,
        },
      })
    end
  end

  describe "mixed arrays" do
    it "parses arrays mixing primitives, objects and strings (list format)" do
      toon = "items[3]:\n  - 1\n  - a: 1\n  - text"
      Toon.decode(toon).should eq({"items" => [1_i64, {"a" => 1_i64}, "text"]})
    end

    it "parses arrays mixing objects and arrays" do
      toon = "items[2]:\n  - a: 1\n  - [2]: 1,2"
      Toon.decode(toon).should eq({"items" => [{"a" => 1_i64}, [1_i64, 2_i64]]})
    end
  end

  describe "delimiter options" do
    describe "basic delimiter usage" do
      it "parses primitive arrays with tab delimiter" do
        toon = "tags[3\t]: reading\tgaming\tcoding"
        Toon.decode(toon).should eq({"tags" => ["reading", "gaming", "coding"]})
      end

      it "parses primitive arrays with pipe delimiter" do
        toon = "tags[3|]: reading|gaming|coding"
        Toon.decode(toon).should eq({"tags" => ["reading", "gaming", "coding"]})
      end

      it "parses primitive arrays with comma delimiter" do
        toon = "tags[3]: reading,gaming,coding"
        Toon.decode(toon).should eq({"tags" => ["reading", "gaming", "coding"]})
      end

      it "parses tabular arrays with tab delimiter" do
        toon = "items[2\t]{sku\tqty\tprice}:\n  A1\t2\t9.99\n  B2\t1\t14.5"
        Toon.decode(toon).should eq({
          "items" => [
            {"sku" => "A1", "qty" => 2_i64, "price" => 9.99},
            {"sku" => "B2", "qty" => 1_i64, "price" => 14.5},
          ],
        })
      end

      it "parses tabular arrays with pipe delimiter" do
        toon = "items[2|]{sku|qty|price}:\n  A1|2|9.99\n  B2|1|14.5"
        Toon.decode(toon).should eq({
          "items" => [
            {"sku" => "A1", "qty" => 2_i64, "price" => 9.99},
            {"sku" => "B2", "qty" => 1_i64, "price" => 14.5},
          ],
        })
      end

      it "parses nested arrays with custom delimiters (tab)" do
        toon = "pairs[2\t]:\n  - [2\t]: a\tb\n  - [2\t]: c\td"
        Toon.decode(toon).should eq({"pairs" => [["a", "b"], ["c", "d"]]})
      end

      it "parses nested arrays with custom delimiters (pipe)" do
        toon = "pairs[2|]:\n  - [2|]: a|b\n  - [2|]: c|d"
        Toon.decode(toon).should eq({"pairs" => [["a", "b"], ["c", "d"]]})
      end

      it "nested arrays inside list items default to comma delimiter (tab parent)" do
        toon = "items[1\t]:\n  - tags[3]: a,b,c"
        Toon.decode(toon).should eq({"items" => [{"tags" => ["a", "b", "c"]}]})
      end

      it "nested arrays inside list items default to comma delimiter (pipe parent)" do
        toon = "items[1|]:\n  - tags[3]: a,b,c"
        Toon.decode(toon).should eq({"items" => [{"tags" => ["a", "b", "c"]}]})
      end

      it "parses root arrays of primitives with custom delimiters" do
        Toon.decode("[3\t]: x\ty\tz").should eq(["x", "y", "z"])
        Toon.decode("[3|]: x|y|z").should eq(["x", "y", "z"])
      end

      it "parses root arrays of objects with custom delimiters" do
        Toon.decode("[2\t]{id}:\n  1\n  2").should eq([{"id" => 1_i64}, {"id" => 2_i64}])
        Toon.decode("[2|]{id}:\n  1\n  2").should eq([{"id" => 1_i64}, {"id" => 2_i64}])
      end
    end

    describe "delimiter-aware quoting" do
      it "parses values containing the active delimiter when quoted" do
        Toon.decode("items[3\t]: a\t\"b\\tc\"\td").should eq({"items" => ["a", "b\tc", "d"]})
        Toon.decode("items[3|]: a|\"b|c\"|d").should eq({"items" => ["a", "b|c", "d"]})
      end

      it "does not split on commas when using non-comma delimiter" do
        Toon.decode("items[2\t]: a,b\tc,d").should eq({"items" => ["a,b", "c,d"]})
        Toon.decode("items[2|]: a,b|c,d").should eq({"items" => ["a,b", "c,d"]})
      end

      it "parses tabular values containing the active delimiter correctly" do
        comma = "items[2]{id,note}:\n  1,\"a,b\"\n  2,\"c,d\""
        Toon.decode(comma).should eq({"items" => [{"id" => 1_i64, "note" => "a,b"}, {"id" => 2_i64, "note" => "c,d"}]})

        tab = "items[2\t]{id\tnote}:\n  1\ta,b\n  2\tc,d"
        Toon.decode(tab).should eq({"items" => [{"id" => 1_i64, "note" => "a,b"}, {"id" => 2_i64, "note" => "c,d"}]})
      end

      it "does not require quoting commas in object values when using non-comma delimiter elsewhere" do
        Toon.decode("note: a,b").should eq({"note" => "a,b"})
      end

      it "parses nested array values containing the active delimiter" do
        Toon.decode("pairs[1|]:\n  - [2|]: a|\"b|c\"").should eq({"pairs" => [["a", "b|c"]]})
        Toon.decode("pairs[1\t]:\n  - [2\t]: a\t\"b\\tc\"").should eq({"pairs" => [["a", "b\tc"]]})
      end
    end

    describe "delimiter-independent quoting rules" do
      it "preserves quoted ambiguity regardless of delimiter" do
        Toon.decode("items[3|]: \"true\"|\"42\"|\"-3.14\"").should eq({"items" => ["true", "42", "-3.14"]})
        Toon.decode("items[3\t]: \"true\"\t\"42\"\t\"-3.14\"").should eq({"items" => ["true", "42", "-3.14"]})
      end

      it "parses structural-looking strings when quoted" do
        Toon.decode("items[3|]: \"[5]\"|\"{key}\"|\"- item\"").should eq({"items" => ["[5]", "{key}", "- item"]})
        Toon.decode("items[3\t]: \"[5]\"\t\"{key}\"\t\"- item\"").should eq({"items" => ["[5]", "{key}", "- item"]})
      end

      it "parses tabular headers with keys containing the active delimiter" do
        toon = "items[2|]{\"a|b\"}:\n  1\n  2"
        Toon.decode(toon).should eq({"items" => [{"a|b" => 1_i64}, {"a|b" => 2_i64}]})
      end
    end
  end

  describe "length marker option" do
    it "accepts length marker on primitive arrays" do
      Toon.decode("tags[#3]: reading,gaming,coding").should eq({"tags" => ["reading", "gaming", "coding"]})
    end

    it "accepts length marker on empty arrays" do
      Toon.decode("items[#0]:").should eq({"items" => [] of Toon::Decoders::JsonValue})
    end

    it "accepts length marker on tabular arrays" do
      toon = "items[#2]{sku,qty,price}:\n  A1,2,9.99\n  B2,1,14.5"
      Toon.decode(toon).should eq({
        "items" => [
          {"sku" => "A1", "qty" => 2_i64, "price" => 9.99},
          {"sku" => "B2", "qty" => 1_i64, "price" => 14.5},
        ],
      })
    end

    it "accepts length marker on nested arrays" do
      toon = "pairs[#2]:\n  - [#2]: a,b\n  - [#2]: c,d"
      Toon.decode(toon).should eq({"pairs" => [["a", "b"], ["c", "d"]]})
    end

    it "works with custom delimiters and length marker" do
      Toon.decode("tags[#3|]: reading|gaming|coding").should eq({"tags" => ["reading", "gaming", "coding"]})
    end
  end

  describe "validation and error handling" do
    describe "length and structure errors" do
      it "throws on array length mismatch (inline primitives)" do
        toon = "tags[2]: a,b,c"
        expect_raises(Exception) { Toon.decode(toon) }
      end

      it "throws on array length mismatch (list format)" do
        toon = "items[1]:\n  - 1\n  - 2"
        expect_raises(Exception) { Toon.decode(toon) }
      end

      it "throws when tabular row value count does not match header field count" do
        toon = "items[2]{id,name}:\n  1,Ada\n  2"
        expect_raises(Exception) { Toon.decode(toon) }
      end

      it "throws when tabular row count does not match header length" do
        toon = "[1]{id}:\n  1\n  2"
        expect_raises(Exception) { Toon.decode(toon) }
      end

      it "throws on invalid escape sequences" do
        expect_raises(Exception) { Toon.decode("\"a\\x\"") }
        expect_raises(Exception) { Toon.decode("\"unterminated") }
      end

      it "throws on missing colon in key-value context" do
        expect_raises(Exception) { Toon.decode("a:\n  user") }
      end

      it "throws on delimiter mismatch" do
        toon = "items[2\t]{a\tb}:\n  1,2\n  3,4"
        expect_raises(Exception) { Toon.decode(toon) }
      end
    end

    describe "strict mode: indentation validation" do
      describe "non-multiple indentation errors" do
        it "throws when object field has non-multiple indentation" do
          toon = "a:\n   b: 1"
          expect_raises(Exception) { Toon.decode(toon, 2, true) }
        end

        it "throws when list item has non-multiple indentation" do
          toon = "items[2]:\n   - id: 1\n   - id: 2"
          expect_raises(Exception) { Toon.decode(toon, 2, true) }
        end

        it "throws with custom indent size when non-multiple" do
          toon = "a:\n   b: 1"
          expect_raises(Exception) { Toon.decode(toon, 4, true) }
        end

        it "accepts correct indentation with custom indent size" do
          toon = "a:\n    b: 1"
          Toon.decode(toon, 4, true).should eq({"a" => {"b" => 1_i64}})
        end
      end

      describe "tab character errors" do
        it "throws when tab character used in indentation" do
          toon = "a:\n\tb: 1"
          expect_raises(Exception) { Toon.decode(toon, 2, true) }
        end

        it "throws when mixed tabs and spaces in indentation" do
          toon = "a:\n \tb: 1"
          expect_raises(Exception) { Toon.decode(toon, 2, true) }
        end

        it "throws when tab at start of line" do
          toon = "\ta: 1"
          expect_raises(Exception) { Toon.decode(toon, 2, true) }
        end
      end

      describe "tabs in quoted strings are allowed" do
        it "accepts tabs in quoted string values" do
          toon = "text: \"hello\tworld\""
          Toon.decode(toon, 2, true).should eq({"text" => "hello\tworld"})
        end

        it "accepts tabs in quoted keys" do
          toon = "\"key\ttab\": value"
          Toon.decode(toon, 2, true).should eq({"key\ttab" => "value"})
        end

        it "accepts tabs in quoted array elements" do
          toon = "items[2]: \"a\tb\",\"c\td\""
          Toon.decode(toon, 2, true).should eq({"items" => ["a\tb", "c\td"]})
        end
      end

      describe "non-strict mode" do
        it "accepts non-multiple indentation when strict=false" do
          toon = "a:\n   b: 1"
          Toon.decode(toon, 2, false).should eq({"a" => {"b" => 1_i64}})
        end

        it "accepts tab indentation when strict=false" do
          toon = "a:\n\tb: 1"
          Toon.decode(toon, 2, false).should eq({"a" => {} of String => Toon::Decoders::JsonValue, "b" => 1_i64})
        end

        it "accepts deeply nested non-multiples when strict=false" do
          toon = "a:\n   b:\n     c: 1"
          Toon.decode(toon, 2, false).should eq({"a" => {"b" => {"c" => 1_i64}}})
        end
      end

      describe "edge cases" do
        it "empty lines do not trigger validation errors" do
          toon = "a: 1\n\nb: 2"
          Toon.decode(toon, 2, true).should eq({"a" => 1_i64, "b" => 2_i64})
        end

        it "root-level content (0 indentation) is always valid" do
          toon = "a: 1\nb: 2\nc: 3"
          Toon.decode(toon, 2, true).should eq({"a" => 1_i64, "b" => 2_i64, "c" => 3_i64})
        end

        it "lines with only spaces are not validated if empty" do
          toon = "a: 1\n   \nb: 2"
          Toon.decode(toon, 2, true).should eq({"a" => 1_i64, "b" => 2_i64})
        end
      end
    end

    describe "strict mode: blank lines in arrays" do
      describe "errors on blank lines inside arrays" do
        it "throws on blank line inside list array" do
          teon = "items[3]:\n  - a\n\n  - b\n  - c"
          expect_raises(Exception) { Toon.decode(teon, 2, true) }
        end

        it "throws on blank line inside tabular array" do
          teon = "items[2]{id}:\n  1\n\n  2"
          expect_raises(Exception) { Toon.decode(teon, 2, true) }
        end

        it "throws on multiple blank lines inside array" do
          teon = "items[2]:\n  - a\n\n\n  - b"
          expect_raises(Exception) { Toon.decode(teon, 2, true) }
        end

        it "throws on blank line with spaces inside array" do
          teon = "items[2]:\n  - a\n  \n  - b"
          expect_raises(Exception) { Toon.decode(teon, 2, true) }
        end

        it "throws on blank line in nested list array" do
          teon = "outer[2]:\n  - inner[2]:\n    - a\n\n    - b\n  - x"
          expect_raises(Exception) { Toon.decode(teon, 2, true) }
        end
      end

      describe "accepts blank lines outside arrays" do
        it "accepts blank line between root-level fields" do
          teon = "a: 1\n\nb: 2"
          Toon.decode(teon, 2, true).should eq({"a" => 1_i64, "b" => 2_i64})
        end

        it "accepts trailing newline at end of file" do
          teon = "a: 1\n"
          Toon.decode(teon, 2, true).should eq({"a" => 1_i64})
        end

        it "accepts multiple trailing newlines" do
          teon = "a: 1\n\n\n"
          Toon.decode(teon, 2, true).should eq({"a" => 1_i64})
        end

        it "accepts blank line after array ends" do
          teon = "items[1]:\n  - a\n\nb: 2"
          Toon.decode(teon, 2, true).should eq({"items" => ["a"], "b" => 2_i64})
        end

        it "accepts blank line between nested object fields" do
          teon = "a:\n  b: 1\n\n  c: 2"
          Toon.decode(teon, 2, true).should eq({"a" => {"b" => 1_i64, "c" => 2_i64}})
        end
      end

      describe "non-strict mode: ignores blank lines" do
        it "ignores blank lines inside list array" do
          teon = "items[3]:\n  - a\n\n  - b\n  - c"
          Toon.decode(teon, 2, false).should eq({"items" => ["a", "b", "c"]})
        end

        it "ignores blank lines inside tabular array" do
          teon = "items[2]{id,name}:\n  1,Alice\n\n  2,Bob"
          Toon.decode(teon, 2, false).should eq({"items" => [{"id" => 1_i64, "name" => "Alice"}, {"id" => 2_i64, "name" => "Bob"}]})
        end

        it "ignores multiple blank lines in arrays" do
          teon = "items[2]:\n  - a\n\n\n  - b"
          Toon.decode(teon, 2, false).should eq({"items" => ["a", "b"]})
        end
      end
    end
  end

  describe "DecodeError type" do
    it "raises Toon::DecodeError on invalid escape sequence" do
      expect_raises(Toon::DecodeError) { Toon.decode("\"a\\x\"") }
    end

    it "raises Toon::DecodeError on missing colon after key" do
      expect_raises(Toon::DecodeError) { Toon.decode("a:\n  user") }
    end

    it "raises Toon::DecodeError on array length mismatch" do
      expect_raises(Toon::DecodeError) { Toon.decode("tags[2]: a,b,c") }
    end
  end
end

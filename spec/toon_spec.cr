require "./spec_helper"
require "../src/toon"

describe Toon do
  describe "primitives" do
    it "encodes safe strings without quotes" do
      Toon.encode("hello").should eq("hello")
      Toon.encode("Ada_99").should eq("Ada_99")
    end

    it "quotes empty string" do
      Toon.encode("").should eq("\"\"")
    end

    it "quotes strings that look like booleans or numbers" do
      Toon.encode("true").should eq("\"true\"")
      Toon.encode("false").should eq("\"false\"")
      Toon.encode("null").should eq("\"null\"")
      Toon.encode("42").should eq("\"42\"")
      Toon.encode("-3.14").should eq("\"-3.14\"")
      Toon.encode("1e-6").should eq("\"1e-6\"")
      Toon.encode("05").should eq("\"05\"")
    end

    it "escapes control characters in strings" do
      Toon.encode("line1\nline2").should eq("\"line1\\nline2\"")
      Toon.encode("tab\there").should eq("\"tab\\there\"")
      Toon.encode("return\rcarriage").should eq("\"return\\rcarriage\"")
      Toon.encode("C:\\Users\\path").should eq("\"C:\\\\Users\\\\path\"")
    end

    it "quotes strings with structural characters" do
      Toon.encode("[3]: x,y").should eq("\"[3]: x,y\"")
      Toon.encode("- item").should eq("\"- item\"")
      Toon.encode("[test]").should eq("\"[test]\"")
      Toon.encode("{key}").should eq("\"{key}\"")
    end

    it "handles Unicode and emoji" do
      Toon.encode("café").should eq("café")
      Toon.encode("你好").should eq("你好")
      Toon.encode("🚀").should eq("🚀")
      Toon.encode("hello 👋 world").should eq("hello 👋 world")
    end

    it "encodes numbers" do
      Toon.encode(42).should eq("42")
      Toon.encode(3.14).should eq("3.14")
      Toon.encode(-7).should eq("-7")
      Toon.encode(0).should eq("0")
    end

    it "handles special numeric values" do
      Toon.encode(-0.0).should eq("0")
      Toon.encode(1e6).should eq("1000000.0")
      Toon.encode(1e-6).should eq("1.0e-06")
    end

    it "encodes booleans" do
      Toon.encode(true).should eq("true")
      Toon.encode(false).should eq("false")
    end

    it "encodes null" do
      Toon.encode(nil).should eq("null")
    end
  end

  describe "objects (simple)" do
    it "preserves key order in objects" do
      obj = {
        "id"     => 123,
        "name"   => "Ada",
        "active" => true,
      }
      Toon.encode(obj).should eq(<<-TXT)
        id: 123
        name: Ada
        active: true
        TXT
    end

    it "encodes null values in objects" do
      obj = {"id" => 123, "value" => nil}
      Toon.encode(obj).should eq(<<-TXT)
        id: 123
        value: null
        TXT
    end

    it "encodes empty objects as empty string" do
      Toon.encode({} of String => Int32).should eq("")
    end

    it "quotes string values with special characters" do
      Toon.encode({"note" => "a:b"}).should eq("note: \"a:b\"")
      Toon.encode({"note" => "a,b"}).should eq("note: \"a,b\"")
      Toon.encode({"text" => "line1\nline2"}).should eq("text: \"line1\\nline2\"")
      Toon.encode({"text" => "say \"hello\""}).should eq("text: \"say \\\"hello\\\"\"")
    end

    it "quotes string values with leading/trailing spaces" do
      Toon.encode({"text" => " padded "}).should eq("text: \" padded \"")
      Toon.encode({"text" => "  "}).should eq("text: \"  \"")
    end

    it "quotes string values that look like booleans/numbers" do
      Toon.encode({"v" => "true"}).should eq("v: \"true\"")
      Toon.encode({"v" => "42"}).should eq("v: \"42\"")
      Toon.encode({"v" => "-7.5"}).should eq("v: \"-7.5\"")
    end
  end

  describe "objects (keys)" do
    it "quotes keys with special characters" do
      Toon.encode({"order:id" => 7}).should eq("\"order:id\": 7")
      Toon.encode({"[index]" => 5}).should eq("\"[index]\": 5")
      Toon.encode({"{key}" => 5}).should eq("\"{key}\": 5")
      Toon.encode({"a,b" => 1}).should eq("\"a,b\": 1")
    end

    it "quotes keys with spaces or leading hyphens" do
      Toon.encode({"full name" => "Ada"}).should eq("\"full name\": Ada")
      Toon.encode({"-lead" => 1}).should eq("\"-lead\": 1")
      Toon.encode({" a " => 1}).should eq("\" a \": 1")
    end

    it "quotes numeric keys" do
      Toon.encode({"123" => "x"}).should eq("\"123\": x")
    end

    it "quotes empty string key" do
      Toon.encode({"" => 1}).should eq("\"\": 1")
    end

    it "escapes control characters in keys" do
      Toon.encode({"line\nbreak" => 1}).should eq("\"line\\nbreak\": 1")
      Toon.encode({"tab\there" => 2}).should eq("\"tab\\there\": 2")
    end

    it "escapes quotes in keys" do
      Toon.encode({"he said \"hi\"" => 1}).should eq("\"he said \\\"hi\\\"\": 1")
    end
  end

  describe "nested objects" do
    it "encodes deeply nested objects" do
      obj = {
        "a" => {
          "b" => {
            "c" => "deep",
          },
        },
      }
      Toon.encode(obj).should eq(<<-TXT)
        a:
          b:
            c: deep
        TXT
    end

    it "encodes empty nested object" do
      Toon.encode({"user" => {} of String => Int32}).should eq("user:")
    end
  end

  describe "arrays of primitives" do
    it "encodes string arrays inline" do
      obj = {"tags" => ["reading", "gaming"]}
      Toon.encode(obj).should eq("tags[2]: reading,gaming")
    end

    it "encodes number arrays inline" do
      obj = {"nums" => [1, 2, 3]}
      Toon.encode(obj).should eq("nums[3]: 1,2,3")
    end

    it "encodes mixed primitive arrays inline" do
      obj = {"data" => ["x", "y", true, 10]}
      Toon.encode(obj).should eq("data[4]: x,y,true,10")
    end

    it "encodes empty arrays" do
      obj = {"items" => [] of String}
      Toon.encode(obj).should eq("items[0]:")
    end

    it "handles empty string in arrays" do
      obj = {"items" => [""]}
      Toon.encode(obj).should eq("items[1]: \"\"")
      obj2 = {"items" => ["a", "", "b"]}
      Toon.encode(obj2).should eq("items[3]: a,\"\",b")
    end

    it "handles whitespace-only strings in arrays" do
      obj = {"items" => [" ", "  "]}
      Toon.encode(obj).should eq("items[2]: \" \",\"  \"")
    end

    it "quotes array strings with special characters" do
      obj = {"items" => ["a", "b,c", "d:e"]}
      Toon.encode(obj).should eq("items[3]: a,\"b,c\",\"d:e\"")
    end

    it "quotes strings that look like booleans/numbers in arrays" do
      obj = {"items" => ["x", "true", "42", "-3.14"]}
      Toon.encode(obj).should eq("items[4]: x,\"true\",\"42\",\"-3.14\"")
    end

    it "quotes strings with structural meanings in arrays" do
      obj = {"items" => ["[5]", "- item", "{key}"]}
      Toon.encode(obj).should eq("items[3]: \"[5]\",\"- item\",\"{key}\"")
    end
  end

  describe "arrays of objects (tabular and list items)" do
    it "encodes arrays of similar objects in tabular format" do
      obj = {
        "items" => [
          {"sku" => "A1", "qty" => 2, "price" => 9.99},
          {"sku" => "B2", "qty" => 1, "price" => 14.5},
        ],
      }
      Toon.encode(obj).should eq(<<-TXT)
        items[2]{sku,qty,price}:
          A1,2,9.99
          B2,1,14.5
        TXT
    end

    it "handles null values in tabular format" do
      obj = {
        "items" => [
          {"id" => 1, "value" => nil},
          {"id" => 2, "value" => "test"},
        ],
      }
      Toon.encode(obj).should eq(<<-TXT)
        items[2]{id,value}:
          1,null
          2,test
        TXT
    end

    it "quotes strings containing delimiters in tabular rows" do
      obj = {
        "items" => [
          {"sku" => "A,1", "desc" => "cool", "qty" => 2},
          {"sku" => "B2", "desc" => "wip: test", "qty" => 1},
        ],
      }
      Toon.encode(obj).should eq(<<-TXT)
        items[2]{sku,desc,qty}:
          "A,1",cool,2
          B2,"wip: test",1
        TXT
    end

    it "quotes ambiguous strings in tabular rows" do
      obj = {
        "items" => [
          {"id" => 1, "status" => "true"},
          {"id" => 2, "status" => "false"},
        ],
      }
      Toon.encode(obj).should eq(<<-TXT)
        items[2]{id,status}:
          1,"true"
          2,"false"
        TXT
    end

    it "handles tabular arrays with keys needing quotes" do
      obj = {
        "items" => [
          {"order:id" => 1, "full name" => "Ada"},
          {"order:id" => 2, "full name" => "Bob"},
        ],
      }
      Toon.encode(obj).should eq(<<-TXT)
        items[2]{"order:id","full name"}:
          1,Ada
          2,Bob
        TXT
    end

    it "uses list format for objects with different fields" do
      obj = {
        "items" => [
          {"id" => 1, "name" => "First"},
          {"id" => 2, "name" => "Second", "extra" => true},
        ],
      }
      Toon.encode(obj).should eq(<<-TXT)
        items[2]:
          - id: 1
            name: First
          - id: 2
            name: Second
            extra: true
        TXT
    end

    it "uses list format for objects with nested values" do
      obj = {
        "items" => [
          {"id" => 1, "nested" => {"x" => 1}},
        ],
      }
      Toon.encode(obj).should eq(<<-TXT)
        items[1]:
          - id: 1
            nested:
              x: 1
        TXT
    end

    it "preserves field order in list items" do
      obj = {"items" => [{"nums" => [1, 2, 3], "name" => "test"}]}
      Toon.encode(obj).should eq(<<-TXT)
        items[1]:
          - nums[3]: 1,2,3
            name: test
        TXT
    end

    it "preserves field order when primitive appears first" do
      obj = {"items" => [{"name" => "test", "nums" => [1, 2, 3]}]}
      Toon.encode(obj).should eq(<<-TXT)
        items[1]:
          - name: test
            nums[3]: 1,2,3
        TXT
    end

    it "uses list format for objects containing arrays of arrays" do
      obj = {
        "items" => [
          {"matrix" => [[1, 2], [3, 4]], "name" => "grid"},
        ],
      }
      Toon.encode(obj).should eq(<<-TXT)
        items[1]:
          - matrix[2]:
            - [2]: 1,2
            - [2]: 3,4
            name: grid
        TXT
    end

    it "uses tabular format for nested uniform object arrays" do
      obj = {
        "items" => [
          {"users" => [{"id" => 1, "name" => "Ada"}, {"id" => 2, "name" => "Bob"}], "status" => "active"},
        ],
      }
      Toon.encode(obj).should eq(<<-TXT)
        items[1]:
          - users[2]{id,name}:
            1,Ada
            2,Bob
            status: active
        TXT
    end

    it "uses list format for nested object arrays with mismatched keys" do
      obj = {
        "items" => [
          {"users" => [{"id" => 1, "name" => "Ada"}, {"id" => 2}], "status" => "active"},
        ],
      }
      Toon.encode(obj).should eq(<<-TXT)
        items[1]:
          - users[2]:
            - id: 1
              name: Ada
            - id: 2
            status: active
        TXT
    end

    it "uses list format for objects with multiple array fields" do
      obj = {"items" => [{"nums" => [1, 2], "tags" => ["a", "b"], "name" => "test"}]}
      Toon.encode(obj).should eq(<<-TXT)
        items[1]:
          - nums[2]: 1,2
            tags[2]: a,b
            name: test
        TXT
    end

    it "uses list format for objects with only array fields" do
      obj = {"items" => [{"nums" => [1, 2, 3], "tags" => ["a", "b"]}]}
      Toon.encode(obj).should eq(<<-TXT)
        items[1]:
          - nums[3]: 1,2,3
            tags[2]: a,b
        TXT
    end

    it "handles objects with empty arrays in list format" do
      obj = {
        "items" => [
          {"name" => "test", "data" => [] of String},
        ],
      }
      Toon.encode(obj).should eq(<<-TXT)
        items[1]:
          - name: test
            data[0]:
        TXT
    end

    it "places first field of nested tabular arrays on hyphen line" do
      obj = {"items" => [{"users" => [{"id" => 1}, {"id" => 2}], "note" => "x"}]}
      Toon.encode(obj).should eq(<<-TXT)
        items[1]:
          - users[2]{id}:
            1
            2
            note: x
        TXT
    end

    it "places empty arrays on hyphen line when first" do
      obj = {"items" => [{"data" => [] of String, "name" => "x"}]}
      Toon.encode(obj).should eq(<<-TXT)
        items[1]:
          - data[0]:
            name: x
        TXT
    end

    it "uses field order from first object for tabular headers" do
      obj = {
        "items" => [
          {"a" => 1, "b" => 2, "c" => 3},
          {"c" => 30, "b" => 20, "a" => 10},
        ],
      }
      Toon.encode(obj).should eq(<<-TXT)
        items[2]{a,b,c}:
          1,2,3
          10,20,30
        TXT
    end

    it "uses list format for one object with nested column" do
      obj = {
        "items" => [
          {"id" => 1, "data" => "string"},
          {"id" => 2, "data" => {"nested" => true}},
        ],
      }
      Toon.encode(obj).should eq(<<-TXT)
        items[2]:
          - id: 1
            data: string
          - id: 2
            data:
              nested: true
        TXT
    end
  end

  describe "arrays of arrays (primitives only)" do
    it "encodes nested arrays of primitives" do
      obj = {
        "pairs" => [["a", "b"], ["c", "d"]],
      }
      Toon.encode(obj).should eq(<<-TXT)
        pairs[2]:
          - [2]: a,b
          - [2]: c,d
        TXT
    end

    it "quotes strings containing delimiters in nested arrays" do
      obj = {
        "pairs" => [["a", "b"], ["c,d", "e:f", "true"]],
      }
      Toon.encode(obj).should eq(<<-TXT)
        pairs[2]:
          - [2]: a,b
          - [3]: "c,d","e:f","true"
        TXT
    end

    it "handles empty inner arrays" do
      obj = {
        "pairs" => [[] of String, [] of String],
      }
      Toon.encode(obj).should eq(<<-TXT)
        pairs[2]:
          - [0]:
          - [0]:
        TXT
    end

    it "handles mixed-length inner arrays" do
      obj = {
        "pairs" => [[1], [2, 3]],
      }
      Toon.encode(obj).should eq(<<-TXT)
        pairs[2]:
          - [1]: 1
          - [2]: 2,3
        TXT
    end
  end

  describe "root arrays" do
    it "encodes arrays of primitives at root level" do
      arr = ["x", "y", "true", true, 10]
      Toon.encode(arr).should eq(<<-TXT)
        [5]: x,y,"true",true,10
        TXT
    end

    it "encodes arrays of similar objects in tabular format" do
      arr = [{"id" => 1}, {"id" => 2}]
      Toon.encode(arr).should eq(<<-TXT)
        [2]{id}:
          1
          2
        TXT
    end

    it "encodes arrays of different objects in list format" do
      arr = [{"id" => 1}, {"id" => 2, "name" => "Ada"}]
      Toon.encode(arr).should eq(<<-TXT)
        [2]:
          - id: 1
          - id: 2
            name: Ada
        TXT
    end

    it "encodes empty arrays at root level" do
      Toon.encode([] of String).should eq("[0]:")
    end

    it "encodes arrays of arrays at root level" do
      arr = [[1, 2], [] of Int32]
      Toon.encode(arr).should eq(<<-TXT)
        [2]:
          - [2]: 1,2
          - [0]:
        TXT
    end
  end

  describe "complex structures" do
    it "encodes objects with mixed arrays and nested objects" do
      obj = {
        "user" => {
          "id"     => 123,
          "name"   => "Ada",
          "tags"   => ["reading", "gaming"],
          "active" => true,
          "prefs"  => [] of String,
        },
      }
      Toon.encode(obj).should eq(<<-TXT)
        user:
          id: 123
          name: Ada
          tags[2]: reading,gaming
          active: true
          prefs[0]:
        TXT
    end
  end

  describe "mixed arrays" do
    it "uses list format for arrays mixing primitives and objects" do
      obj = {
        "items" => [1, {"a" => 1}, "text"],
      }
      Toon.encode(obj).should eq(<<-TXT)
        items[3]:
          - 1
          - a: 1
          - text
        TXT
    end

    it "uses list format for arrays mixing objects and arrays" do
      obj = {
        "items" => [{"a" => 1}, [1, 2]],
      }
      Toon.encode(obj).should eq(<<-TXT)
        items[2]:
          - a: 1
          - [2]: 1,2
        TXT
    end
  end

  describe "whitespace and formatting invariants" do
    it "produces no trailing spaces at end of lines" do
      obj = {
        "user" => {
          "id"   => 123,
          "name" => "Ada",
        },
        "items" => ["a", "b"],
      }
      result = Toon.encode(obj)
      lines = result.split("\n")
      lines.each do |line|
        line.should_not match(/ $/)
      end
    end

    it "produces no trailing newline at end of output" do
      obj = {"id" => 123}
      result = Toon.encode(obj)
      result.should_not match(/\n$/)
    end
  end

  describe "non-JSON-serializable values" do
    it "converts Symbol to string" do
      Toon.encode(:hello).should eq("hello")
      # In Crystal, hash with symbol keys needs explicit typing
      obj = {"id" => 456}
      Toon.encode(obj).should eq("id: 456")
    end

    it "converts Time to ISO string" do
      time = Time.utc(2025, 1, 1, 0, 0, 0)
      Toon.encode(time).should eq("\"2025-01-01T00:00:00Z\"")
      Toon.encode({"created" => time}).should eq("created: \"2025-01-01T00:00:00Z\"")
    end

    it "converts non-finite numbers to null" do
      Toon.encode(Float32::INFINITY).should eq("null")
      Toon.encode(-Float32::INFINITY).should eq("null")
      Toon.encode(Float32::NAN).should eq("null")
    end
  end

  describe "delimiter options" do
    describe "basic delimiter usage" do
      it "encodes primitive arrays with tab" do
        obj = {"tags" => ["reading", "gaming", "coding"]}
        Toon.encode(obj, delimiter: '\t').should eq("tags[3\t]: reading\tgaming\tcoding")
      end

      it "encodes primitive arrays with pipe" do
        obj = {"tags" => ["reading", "gaming", "coding"]}
        Toon.encode(obj, delimiter: '|').should eq("tags[3|]: reading|gaming|coding")
      end

      it "encodes tabular arrays with tab" do
        obj = {
          "items" => [
            {"sku" => "A1", "qty" => 2, "price" => 9.99},
            {"sku" => "B2", "qty" => 1, "price" => 14.5},
          ],
        }
        expected = "items[2\t]{sku\tqty\tprice}:\n  A1\t2\t9.99\n  B2\t1\t14.5"
        Toon.encode(obj, delimiter: '\t').should eq(expected)
      end

      it "encodes tabular arrays with pipe" do
        obj = {
          "items" => [
            {"sku" => "A1", "qty" => 2, "price" => 9.99},
            {"sku" => "B2", "qty" => 1, "price" => 14.5},
          ],
        }
        expected = "items[2|]{sku|qty|price}:\n  A1|2|9.99\n  B2|1|14.5"
        Toon.encode(obj, delimiter: '|').should eq(expected)
      end

      it "encodes root arrays with tab" do
        arr = ["x", "y", "z"]
        Toon.encode(arr, delimiter: '\t').should eq("[3\t]: x\ty\tz")
      end

      it "encodes root arrays with pipe" do
        arr = ["x", "y", "z"]
        Toon.encode(arr, delimiter: '|').should eq("[3|]: x|y|z")
      end
    end

    describe "delimiter-aware quoting" do
      it "quotes strings containing tab" do
        Toon.encode({"items" => ["a", "b\tc", "d"]}, delimiter: '\t').should eq("items[3\t]: a\t\"b\\tc\"\td")
      end

      it "quotes strings containing pipe" do
        Toon.encode({"items" => ["a", "b|c", "d"]}, delimiter: '|').should eq("items[3|]: a|\"b|c\"|d")
      end

      it "does not quote commas with tab delimiter" do
        Toon.encode({"items" => ["a,b", "c,d"]}, delimiter: '\t').should eq("items[2\t]: a,b\tc,d")
      end

      it "does not quote commas with pipe delimiter" do
        Toon.encode({"items" => ["a,b", "c,d"]}, delimiter: '|').should eq("items[2|]: a,b|c,d")
      end

      it "quotes tabular values containing the delimiter" do
        obj = {
          "items" => [
            {"id" => 1, "note" => "a,b"},
            {"id" => 2, "note" => "c,d"},
          ],
        }
        Toon.encode(obj, delimiter: ',').should eq("items[2]{id,note}:\n  1,\"a,b\"\n  2,\"c,d\"")
        Toon.encode(obj, delimiter: '\t').should eq("items[2\t]{id\tnote}:\n  1\ta,b\n  2\tc,d")
      end

      it "does not quote commas in object values with non-comma delimiter" do
        Toon.encode({"note" => "a,b"}, delimiter: '|').should eq("note: a,b")
        Toon.encode({"note" => "a,b"}, delimiter: '\t').should eq("note: a,b")
      end

      it "quotes nested array values containing the delimiter" do
        Toon.encode({"pairs" => [["a", "b|c"]]}, delimiter: '|').should eq("pairs[1|]:\n  - [2|]: a|\"b|c\"")
        Toon.encode({"pairs" => [["a", "b\tc"]]}, delimiter: '\t').should eq("pairs[1\t]:\n  - [2\t]: a\t\"b\\tc\"")
      end
    end

    describe "delimiter-independent quoting rules" do
      it "preserves ambiguity quoting regardless of delimiter" do
        obj = {"items" => ["true", "42", "-3.14"]}
        Toon.encode(obj, delimiter: '|').should eq("items[3|]: \"true\"|\"42\"|\"-3.14\"")
        Toon.encode(obj, delimiter: '\t').should eq("items[3\t]: \"true\"\t\"42\"\t\"-3.14\"")
      end

      it "preserves structural quoting regardless of delimiter" do
        obj = {"items" => ["[5]", "{key}", "- item"]}
        Toon.encode(obj, delimiter: '|').should eq("items[3|]: \"[5]\"|\"{key}\"|\"- item\"")
        Toon.encode(obj, delimiter: '\t').should eq("items[3\t]: \"[5]\"\t\"{key}\"\t\"- item\"")
      end

      it "quotes keys containing the delimiter" do
        Toon.encode({"a|b" => 1}, delimiter: '|').should eq("\"a|b\": 1")
        Toon.encode({"a\tb" => 1}, delimiter: '\t').should eq("\"a\\tb\": 1")
      end

      it "quotes tabular headers containing the delimiter" do
        obj = {"items" => [{"a|b" => 1}, {"a|b" => 2}]}
        Toon.encode(obj, delimiter: '|').should eq("items[2|]{\"a|b\"}:\n  1\n  2")
      end

      it "header uses the active delimiter" do
        obj = {"items" => [{"a" => 1, "b" => 2}, {"a" => 3, "b" => 4}]}
        Toon.encode(obj, delimiter: '|').should eq("items[2|]{a|b}:\n  1|2\n  3|4")
        Toon.encode(obj, delimiter: '\t').should eq("items[2\t]{a\tb}:\n  1\t2\n  3\t4")
      end
    end
  end

  describe "length marker option" do
    it "adds length marker to primitive arrays" do
      obj = {"tags" => ["reading", "gaming", "coding"]}
      Toon.encode(obj, length_marker: "#").should eq("tags[#3]: reading,gaming,coding")
    end

    it "handles empty arrays" do
      Toon.encode({"items" => [] of String}, length_marker: "#").should eq("items[#0]:")
    end

    it "adds length marker to tabular arrays" do
      obj = {
        "items" => [
          {"sku" => "A1", "qty" => 2, "price" => 9.99},
          {"sku" => "B2", "qty" => 1, "price" => 14.5},
        ],
      }
      expected = "items[#2]{sku,qty,price}:\n  A1,2,9.99\n  B2,1,14.5"
      Toon.encode(obj, length_marker: "#").should eq(expected)
    end

    it "adds length marker to nested arrays" do
      obj = {"pairs" => [["a", "b"], ["c", "d"]]}
      Toon.encode(obj, length_marker: "#").should eq("pairs[#2]:\n  - [#2]: a,b\n  - [#2]: c,d")
    end

    it "works with delimiter option" do
      obj = {"tags" => ["reading", "gaming", "coding"]}
      Toon.encode(obj, length_marker: "#", delimiter: '|').should eq("tags[#3|]: reading|gaming|coding")
    end

    it "default is false (no length marker)" do
      obj = {"tags" => ["reading", "gaming", "coding"]}
      Toon.encode(obj).should eq("tags[3]: reading,gaming,coding")
    end
  end
end

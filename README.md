# TOON for Crystal

[![Crystal CI](https://github.com/mamantoha/toon-crystal/actions/workflows/crystal.yml/badge.svg)](https://github.com/mamantoha/toon-crystal/actions/workflows/crystal.yml)
[![GitHub release](https://img.shields.io/github/release/mamantoha/toon-crystal.svg)](https://github.com/mamantoha/flag_emoji/releases)
[![License](https://img.shields.io/github/license/mamantoha/toon-crystal.svg)](https://github.com/mamantoha/toon-crystal/blob/main/LICENSE)

**Token-Oriented Object Notation** is a compact, human-readable serialization format designed for passing structured data to Large Language Models with significantly reduced token usage. It's intended for LLM input, not output.

This is a Crystal reference implementation of the [TOON format specification](https://github.com/toon-format/spec).

> **Note:** This implementation supports **TOON Format Specification Version 1.4** (2025-11-05).

## Installation

Add this to your `shard.yml`:

```yaml
dependencies:
  toon:
    github: mamantoha/toon-crystal
```

Then run:

```bash
shards install
```

## Quick Start

```crystal
require "toon"

data = {
  "user" => {
    "id" => 123,
    "name" => "Ada",
    "tags" => ["reading", "gaming"],
    "active" => true,
    "preferences" => [] of String
  }
}

puts Toon.encode(data)
```

Output:

```
user:
  id: 123
  name: Ada
  tags[2]: reading,gaming
  active: true
  preferences[0]:
```

You can also decode TOON back to Crystal values:

```crystal
toon = <<-TOON
  user:
    id: 123
    name: Ada
    tags[2]: reading,gaming
    active: true
    preferences[0]:
  TOON

value = Toon.decode(toon)
# => {"user" => {"id" => 123, "name" => "Ada", "tags" => ["reading", "gaming"], "active" => true, "preferences" => []}}
```

## API

### `Toon.encode(value, *, indent = 2, delimiter = ',', length_marker = false)`

Converts any value to TOON format.

**Parameters:**

- `value` – Any value to encode (Hash, Array, primitives, or nested structures)
- `indent` – Number of spaces per indentation level (default: `2`)
- `delimiter` – Delimiter for array values and tabular rows: `','`, `'\t'`, or `'|'` (default: `','`)
- `length_marker` – Optional marker to prefix array lengths: `'#'` or `false` (default: `false`)

**Returns:**

A TOON-formatted string with no trailing newline or spaces.

**Examples:**

```crystal
# Basic usage
Toon.encode({ "id" => 1, "name" => "Ada" })
# => "id: 1\nname: Ada"

# Tabular arrays
items = [
  { "sku" => "A1", "qty" => 2, "price" => 9.99 },
  { "sku" => "B2", "qty" => 1, "price" => 14.5 }
]
Toon.encode({ "items" => items })
# => "items[2]{sku,qty,price}:\n  A1,2,9.99\n  B2,1,14.5"

# Custom delimiter (tab)
Toon.encode({ "items" => items }, delimiter: '\t')
# => "items[2	]{sku	qty	price}:\n  A1\t2\t9.99\n  B2\t1\t14.5"

# Length marker
Toon.encode({ "tags" => ["a", "b", "c"] }, length_marker: '#')
# => "tags[#3]: a,b,c"
```

### `Toon.decode(input, *, indent = 2, strict = true)`

Parses a TOON-formatted string into native Crystal values.

**Parameters:**

- `input` – TOON-formatted string
- `indent` – Number of spaces per indentation level (default: `2`)
- `strict` – Enable validations for indentation, tabs, blank lines, and extra rows/items (default: `true`)

**Returns:**

A Crystal value (`Nil | Bool | Int64 | Float64 | String | Array | Hash(String, _)`).

**Examples:**

```crystal
Toon.decode("tags[3]: a,b,c")
# => {"tags" => ["a", "b", "c"]}

Toon.decode("[2]{id}:\n  1\n  2")
# => [{"id" => 1}, {"id" => 2}]

Toon.decode("items[2]:\n  - id: 1\n    name: First\n  - id: 2\n    name: Second")
# => {"items" => [{"id" => 1, "name" => "First"}, {"id" => 2, "name" => "Second"}]}
```

## Development

After checking out the repo, run:

```bash
shards install
```

### Updating the Spec Submodule

This project uses the [TOON specification repository](https://github.com/toon-format/spec) as a git submodule at `ext/spec`. This contains the language-agnostic test fixtures.

**Initial setup** (when cloning the repo):
```bash
git submodule update --init --recursive
```

**Update the spec submodule** to get the latest test fixtures:
```bash
git submodule update --remote ext/spec
```

This will pull the latest commits from the upstream spec repository and update the submodule reference.

### Running Tests

Run the test suite:

```bash
crystal spec
```

The test suite uses fixtures from `ext/spec/tests/fixtures/` and automatically discovers all fixture files in the encode and decode directories.

## Contributing

1. Fork it (<https://github.com/mamantoha/toon-crystal/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Anton Maminov](https://github.com/mamantoha) - creator and maintainer

## License

The project is available as open source under the terms of the [MIT License](LICENSE).

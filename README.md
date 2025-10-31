# TOON for Crystal

[![Crystal CI](https://github.com/mamantoha/toon-crystal/actions/workflows/crystal.yml/badge.svg)](https://github.com/mamantoha/toon-crystal/actions/workflows/crystal.yml)
[![GitHub release](https://img.shields.io/github/release/mamantoha/toon-crystal.svg)](https://github.com/mamantoha/flag_emoji/releases)
[![License](https://img.shields.io/github/license/mamantoha/toon-crystal.svg)](https://github.com/mamantoha/toon-crystal/blob/main/LICENSE)


**Token-Oriented Object Notation** is a compact, human-readable format designed for passing structured data to Large Language Models with significantly reduced token usage.

This is a Crystal port of the [TOON library](https://github.com/johannschopplich/toon) originally written in TypeScript, and ported from Ruby [library](https://github.com/andrepcg/toon-ruby).

TOON excels at **uniform complex objects** – multiple fields per row, same structure across items. It borrows YAML's indentation-based structure for nested objects and CSV's tabular format for uniform data rows, then optimizes both for token efficiency in LLM contexts.

## Why TOON?

AI is becoming cheaper and more accessible, but larger context windows allow for larger data inputs as well. **LLM tokens still cost money** – and standard JSON is verbose and token-expensive:

```json
{
  "users": [
    { "id": 1, "name": "Alice", "role": "admin" },
    { "id": 2, "name": "Bob", "role": "user" }
  ]
}
```

TOON conveys the same information with **fewer tokens**:

```
users[2]{id,name,role}:
  1,Alice,admin
  2,Bob,user
```

## Format Comparison

Format familiarity matters as much as token count.

- **CSV:** best for uniform tables.
- **JSON:** best for non-uniform data.
- **TOON:** best for uniform complex (but not deeply nested) objects.

TOON switches to list format for non-uniform arrays. In those cases, JSON can be cheaper at scale.

## Key Features

- 💸 **Token-efficient:** typically 30–60% fewer tokens than JSON
- 🤿 **LLM-friendly guardrails:** explicit lengths and field lists help models validate output
- 🍱 **Minimal syntax:** removes redundant punctuation (braces, brackets, most quotes)
- 📐 **Indentation-based structure:** replaces braces with whitespace for better readability
- 🧺 **Tabular arrays:** declare keys once, then stream rows without repetition

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

## Canonical Formatting Rules

TOON formatting is deterministic and minimal:

- **Indentation**: 2 spaces per nesting level.
- **Lines**:
  - `key: value` for primitives (single space after colon).
  - `key:` for nested/empty objects (no trailing space on that line).
- **Arrays**:
  - Delimiter encoding: Comma delimiters are implicit in array headers (e.g., `tags[3]:`, `items[2]{id,name}:`). Tab and pipe delimiters are explicitly shown in array headers (e.g., `tags[3|]:`, `items[2	]{id	name}:`).
  - Primitive arrays inline: `key[N]: v1,v2` (comma) or `key[N<delim>]: v1<delim>v2` (tab/pipe).
  - Tabular arrays: `key[N]{f1,f2}: …` (comma) or `key[N<delim>]{f1<delim>f2}: …` (tab/pipe).
  - List items: two spaces, hyphen, space (`"  - …"`).
- **Whitespace invariants**:
  - No trailing spaces at end of any line.
  - No trailing newline at end of output.

## Format Overview

### Objects

Simple objects with primitive values:

```crystal
Toon.encode({
  "id" => 123,
  "name" => "Ada",
  "active" => true
})
```

```
id: 123
name: Ada
active: true
```

Nested objects:

```crystal
Toon.encode({
  "user" => {
    "id" => 123,
    "name" => "Ada"
  }
})
```

```
user:
  id: 123
  name: Ada
```

### Arrays

> **Tip:** TOON includes the array length in brackets (e.g., `items[3]`). When using comma delimiters (default), the delimiter is implicit. When using tab or pipe delimiters, the delimiter is explicitly shown in the header (e.g., `tags[2|]` or `[2	]`). This encoding helps LLMs identify the delimiter and track the number of elements, reducing errors when generating or validating structured output.

#### Primitive Arrays (Inline)

```crystal
Toon.encode({ "tags" => ["admin", "ops", "dev"] })
```

```
tags[3]: admin,ops,dev
```

#### Arrays of Objects (Tabular)

When all objects share the same primitive fields, TOON uses an efficient **tabular format**:

```crystal
Toon.encode({
  "items" => [
    { "sku" => "A1", "qty" => 2, "price" => 9.99 },
    { "sku" => "B2", "qty" => 1, "price" => 14.5 }
  ]
})
```

```
items[2]{sku,qty,price}:
  A1,2,9.99
  B2,1,14.5
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

Run the test suite:

```bash
crystal spec
```

## Contributing

Bug reports and pull requests are welcome on GitHub at <https://github.com/mamantoha/toon-crystal>.

## License

The project is available as open source under the terms of the [MIT License](LICENSE).

## Credits

This is a Crystal port of the original [TOON library](https://github.com/johannschopplich/toon) by [Johann Schopplich](https://github.com/johannschopplich).

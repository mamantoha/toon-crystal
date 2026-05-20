# Refactoring TODO

All steps preserve public API and keep all specs passing.
Run `crystal spec` after each step to verify.

## Steps

- [x] **Step 1** — Centralise shared type alias and constant
  - Add `alias JsonValue` and `IDENTIFIER_SEGMENT_REGEX` to `src/toon/constants.cr`
  - In `Decoders`: replace `alias JsonValue` with `alias JsonValue = Toon::JsonValue`, remove `IDENTIFIER_SEGMENT_REGEX`
  - In `Encoders`: remove `IDENTIFIER_SEGMENT_REGEX` (resolves via outer `Toon` module)

- [x] **Step 2** — Introduce `EncodeOptions` struct
  - Create `src/toon/encode/options.cr` with typed `EncodeOptions` struct (`indent`, `delimiter`, `key_folding_mode`, `flatten_depth`, `flatten_limit`)
  - Update private `resolve_options` in `src/toon.cr` to return `EncodeOptions`
  - Replace all `options[:xxx].as(...)` accesses in `encoders.cr` with typed `options.xxx`
  - Remove `flatten_limit` and `folding_enabled?` helpers from `Encoders` (absorbed by the struct)

- [x] **Step 3** — Collapse duplicate normalization branches
  - In `src/toon/encode/normalizer.cr`, remove the `if array.is_a?(Array(JsonValue)) ... else ...` guard in `normalize_array` — keep one loop body
  - Same collapse for `normalize_hash`
  - Removes ~55 lines of duplicated code

- [ ] **Step 4** — Move `ParsedLine` and `LineCursor` to their own file
  - Create `src/toon/decode/line_cursor.cr` with `struct ParsedLine` and `class LineCursor`
  - Replace definitions in `decoders.cr` with `require "./line_cursor"`

- [ ] **Step 5** — Extract string/escape parsing to dedicated file
  - Create `src/toon/decode/string_parser.cr`
  - Move these methods from `decoders.cr`: `parse_string_literal`, `parse_primitive_token`, `parse_delimited_values`, `find_unquoted_colon_index`, `find_unquoted_char_index`, `key_value_line?`
  - Add `require "./string_parser"` to `decoders.cr`

- [ ] **Step 6** — Extract array header parsing to dedicated file
  - Create `src/toon/decode/array_header_parser.cr`
  - Move `struct KeyToken`, `struct ArrayHeader`, and `parse_array_header_line` from `decoders.cr`
  - Add `require "./array_header_parser"` to `decoders.cr`

- [ ] **Step 7** — Refactor `maybe_fold_key` in `encoders.cr`
  - Introduce private `struct FoldChain` with `segments`, `leaf_value`, `stop` (`:leaf | :branch | :limit | :unfoldable`)
  - Extract `walk_fold_chain(...)` → `FoldChain` (phase 1: walk the chain)
  - Extract `child_fold_options(chain, limit, enabled)` → `{Bool, Int32?}` (phase 2: decide options)
  - Reduce `maybe_fold_key` to a thin coordinator calling both

- [ ] **Step 8** — Add internal unit specs
  - Create `spec/internal/string_parser_spec.cr` — unit tests for `parse_primitive_token`, `parse_string_literal`
  - Create `spec/internal/array_header_parser_spec.cr` — unit tests for `parse_array_header_line`

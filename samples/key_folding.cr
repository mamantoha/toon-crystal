require "../src/toon"

# New in v1.5:
#
# Key Folding (encode) + Path Expansion (decode)
# - Key Folding: Collapse nested single-key objects into compact dotted paths
#   {"a": {"b": {"c": 1}}} → a.b.c: 1
#   Opt-in via keyFolding="safe" (flattenDepth defaults to Infinity)
# - Path Expansion: Expand dotted keys back to nested objects
#   a.b.c: 1 → {"a": {"b": {"c": 1}}}
#   Opt-in via expandPaths="safe" with deep-merge semantics

# --- Encode example (Key Folding) ---
input = {"a" => {"b" => {"c" => 1}}}

output = Toon.encode(
  input,
  key_folding: :safe,
  indent: 2
)

puts output # => a.b.c: 1

# --- Decode example (Path Expansion) ---
input_str = "a.b.c: 1"

decoded = Toon.decode(
  input_str,
  expand_paths: :safe,
  strict: true
)

puts decoded # => {"a" => {"b" => {"c" => 1}}}

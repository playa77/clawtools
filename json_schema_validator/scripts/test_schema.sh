#!/usr/bin/env bash
# json_schema_validator test suite
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA="$SCRIPT_DIR/schema.sh"
PASS=0
FAIL=0

pass() { ((PASS++)); echo "  ✅ $1"; }
fail() { ((FAIL++)); echo "  ❌ $1 — got: $2, expected: $3"; }

TMPDIR=$(mktemp -d)
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

echo "=== validate: type matching ==="

# String type
cat > "$TMPDIR/str-schema.json" <<'EOF'
{"type":"string"}
EOF
echo '"hello"' > "$TMPDIR/str-ok.json"
r=$($SCHEMA validate "$TMPDIR/str-schema.json" "$TMPDIR/str-ok.json")
[[ $(echo "$r" | jq -r '.valid') == "true" ]] && pass "string type match" || fail "string type match" "$(echo "$r" | jq -r '.valid')" "true"

echo '42' > "$TMPDIR/str-bad.json"
r=$($SCHEMA validate "$TMPDIR/str-schema.json" "$TMPDIR/str-bad.json")
[[ $(echo "$r" | jq -r '.valid') == "false" ]] && pass "string type mismatch" || fail "string type mismatch" "$(echo "$r" | jq -r '.valid')" "false"

# Number type
cat > "$TMPDIR/num-schema.json" <<'EOF'
{"type":"number"}
EOF
echo '42' > "$TMPDIR/num-ok.json"
r=$($SCHEMA validate "$TMPDIR/num-schema.json" "$TMPDIR/num-ok.json")
[[ $(echo "$r" | jq -r '.valid') == "true" ]] && pass "number type match" || fail "number type match" "$(echo "$r" | jq -r '.valid')" "true"

# Boolean type
cat > "$TMPDIR/bool-schema.json" <<'EOF'
{"type":"boolean"}
EOF
echo 'true' > "$TMPDIR/bool-ok.json"
r=$($SCHEMA validate "$TMPDIR/bool-schema.json" "$TMPDIR/bool-ok.json")
[[ $(echo "$r" | jq -r '.valid') == "true" ]] && pass "boolean type match" || fail "boolean type match" "$(echo "$r" | jq -r '.valid')" "true"

# Array type
cat > "$TMPDIR/arr-schema.json" <<'EOF'
{"type":"array"}
EOF
echo '[1,2,3]' > "$TMPDIR/arr-ok.json"
r=$($SCHEMA validate "$TMPDIR/arr-schema.json" "$TMPDIR/arr-ok.json")
[[ $(echo "$r" | jq -r '.valid') == "true" ]] && pass "array type match" || fail "array type match" "$(echo "$r" | jq -r '.valid')" "true"

# Object type
cat > "$TMPDIR/obj-schema.json" <<'EOF'
{"type":"object"}
EOF
echo '{"x":1}' > "$TMPDIR/obj-ok.json"
r=$($SCHEMA validate "$TMPDIR/obj-schema.json" "$TMPDIR/obj-ok.json")
[[ $(echo "$r" | jq -r '.valid') == "true" ]] && pass "object type match" || fail "object type match" "$(echo "$r" | jq -r '.valid')" "true"

# Null type
cat > "$TMPDIR/null-schema.json" <<'EOF'
{"type":"null"}
EOF
echo 'null' > "$TMPDIR/null-ok.json"
r=$($SCHEMA validate "$TMPDIR/null-schema.json" "$TMPDIR/null-ok.json")
[[ $(echo "$r" | jq -r '.valid') == "true" ]] && pass "null type match" || fail "null type match" "$(echo "$r" | jq -r '.valid')" "true"

echo ""

echo "=== validate: required properties ==="

cat > "$TMPDIR/req-schema.json" <<'EOF'
{"type":"object","required":["name","age"]}
EOF

echo '{"name":"Dan","age":30}' > "$TMPDIR/req-ok.json"
r=$($SCHEMA validate "$TMPDIR/req-schema.json" "$TMPDIR/req-ok.json")
[[ $(echo "$r" | jq -r '.valid') == "true" ]] && pass "required all present" || fail "required all present" "$(echo "$r" | jq -r '.valid')" "true"

echo '{"name":"Dan"}' > "$TMPDIR/req-miss.json"
r=$($SCHEMA validate "$TMPDIR/req-schema.json" "$TMPDIR/req-miss.json")
[[ $(echo "$r" | jq -r '.valid') == "false" ]] && pass "required missing property" || fail "required missing" "$(echo "$r" | jq -r '.valid')" "false"
has_age_error=$(echo "$r" | jq '.errors[] | select(.path == "age") | .message' 2>/dev/null)
[[ -n "$has_age_error" ]] && pass "required error mentions 'age'" || fail "required error message" "empty" "has age"

echo ""

echo "=== validate: enum ==="

cat > "$TMPDIR/enum-schema.json" <<'EOF'
{"type":"string","enum":["red","green","blue"]}
EOF

echo '"red"' > "$TMPDIR/enum-ok.json"
r=$($SCHEMA validate "$TMPDIR/enum-schema.json" "$TMPDIR/enum-ok.json")
[[ $(echo "$r" | jq -r '.valid') == "true" ]] && pass "enum valid value" || fail "enum valid" "$(echo "$r" | jq -r '.valid')" "true"

echo '"yellow"' > "$TMPDIR/enum-bad.json"
r=$($SCHEMA validate "$TMPDIR/enum-schema.json" "$TMPDIR/enum-bad.json")
[[ $(echo "$r" | jq -r '.valid') == "false" ]] && pass "enum invalid value" || fail "enum invalid" "$(echo "$r" | jq -r '.valid')" "false"

echo ""

echo "=== validate: minimum/maximum ==="

cat > "$TMPDIR/minmax-schema.json" <<'EOF'
{"type":"number","minimum":0,"maximum":100}
EOF

echo '50' > "$TMPDIR/minmax-ok.json"
r=$($SCHEMA validate "$TMPDIR/minmax-schema.json" "$TMPDIR/minmax-ok.json")
[[ $(echo "$r" | jq -r '.valid') == "true" ]] && pass "min/max in range" || fail "min/max in range" "$(echo "$r" | jq -r '.valid')" "true"

echo '150' > "$TMPDIR/minmax-high.json"
r=$($SCHEMA validate "$TMPDIR/minmax-schema.json" "$TMPDIR/minmax-high.json")
[[ $(echo "$r" | jq -r '.valid') == "false" ]] && pass "max exceeded" || fail "max exceeded" "$(echo "$r" | jq -r '.valid')" "false"

echo ''

echo "=== validate: minLength/maxLength ==="

cat > "$TMPDIR/strlen-schema.json" <<'EOF'
{"type":"string","minLength":2,"maxLength":10}
EOF

echo '"hi"' > "$TMPDIR/strlen-ok.json"
r=$($SCHEMA validate "$TMPDIR/strlen-schema.json" "$TMPDIR/strlen-ok.json")
[[ $(echo "$r" | jq -r '.valid') == "true" ]] && pass "string length in range" || fail "string length in range" "$(echo "$r" | jq -r '.valid')" "true"

echo '"a"' > "$TMPDIR/strlen-short.json"
r=$($SCHEMA validate "$TMPDIR/strlen-schema.json" "$TMPDIR/strlen-short.json")
[[ $(echo "$r" | jq -r '.valid') == "false" ]] && pass "string too short" || fail "string too short" "$(echo "$r" | jq -r '.valid')" "false"

echo ""

echo "=== validate: additionalProperties ==="

cat > "$TMPDIR/addprop-schema.json" <<'EOF'
{"type":"object","properties":{"name":{"type":"string"}},"additionalProperties":false}
EOF

echo '{"name":"test"}' > "$TMPDIR/addprop-ok.json"
r=$($SCHEMA validate "$TMPDIR/addprop-schema.json" "$TMPDIR/addprop-ok.json")
[[ $(echo "$r" | jq -r '.valid') == "true" ]] && pass "no additional props" || fail "no additional props" "$(echo "$r" | jq -r '.valid')" "true"

echo '{"name":"test","extra":true}' > "$TMPDIR/addprop-bad.json"
r=$($SCHEMA validate "$TMPDIR/addprop-schema.json" "$TMPDIR/addprop-bad.json")
[[ $(echo "$r" | jq -r '.valid') == "false" ]] && pass "additional prop rejected" || fail "additional prop rejected" "$(echo "$r" | jq -r '.valid')" "false"

echo ""

echo "=== validate: format ==="

cat > "$TMPDIR/email-schema.json" <<'EOF'
{"type":"string","format":"email"}
EOF

echo '"user@example.com"' > "$TMPDIR/email-ok.json"
r=$($SCHEMA validate "$TMPDIR/email-schema.json" "$TMPDIR/email-ok.json")
[[ $(echo "$r" | jq -r '.valid') == "true" ]] && pass "email format valid" || fail "email format valid" "$(echo "$r" | jq -r '.valid')" "true"

echo '"notanemail"' > "$TMPDIR/email-bad.json"
r=$($SCHEMA validate "$TMPDIR/email-schema.json" "$TMPDIR/email-bad.json")
[[ $(echo "$r" | jq -r '.valid') == "false" ]] && pass "email format invalid" || fail "email format invalid" "$(echo "$r" | jq -r '.valid')" "false"

echo ""

echo "=== validate: minItems/maxItems ==="

cat > "$TMPDIR/items-schema.json" <<'EOF'
{"type":"array","minItems":1,"maxItems":3}
EOF

echo '[1,2]' > "$TMPDIR/items-ok.json"
r=$($SCHEMA validate "$TMPDIR/items-schema.json" "$TMPDIR/items-ok.json")
[[ $(echo "$r" | jq -r '.valid') == "true" ]] && pass "array items in range" || fail "array items in range" "$(echo "$r" | jq -r '.valid')" "true"

echo '[]' > "$TMPDIR/items-empty.json"
r=$($SCHEMA validate "$TMPDIR/items-schema.json" "$TMPDIR/items-empty.json")
[[ $(echo "$r" | jq -r '.valid') == "false" ]] && pass "array too few items" || fail "array too few items" "$(echo "$r" | jq -r '.valid')" "false"

echo ""

echo "=== validate: full object schema ==="

cat > "$TMPDIR/full-schema.json" <<'EOF'
{
  "type": "object",
  "properties": {
    "name": {"type": "string", "minLength": 1},
    "age": {"type": "integer", "minimum": 0, "maximum": 150},
    "email": {"type": "string", "format": "email"},
    "tags": {"type": "array", "items": {"type": "string"}}
  },
  "required": ["name", "age"]
}
EOF

echo '{"name":"Daniel","age":30,"email":"d@example.com","tags":["dev"]}' > "$TMPDIR/full-ok.json"
r=$($SCHEMA validate "$TMPDIR/full-schema.json" "$TMPDIR/full-ok.json")
[[ $(echo "$r" | jq -r '.valid') == "true" ]] && pass "full schema valid" || fail "full schema valid" "$(echo "$r" | jq -r '.valid')" "true"

echo '{"name":"","age":-1}' > "$TMPDIR/full-bad.json"
r=$($SCHEMA validate "$TMPDIR/full-schema.json" "$TMPDIR/full-bad.json")
[[ $(echo "$r" | jq -r '.valid') == "false" ]] && pass "full schema invalid" || fail "full schema invalid" "$(echo "$r" | jq -r '.valid')" "false"
# Should have multiple errors (minLength for name, minimum for age, and possibly type for age)
error_count=$(echo "$r" | jq '.error_count')
[[ "$error_count" -ge 2 ]] && pass "full schema has 2+ errors ($error_count)" || fail "full schema error count" "$error_count" ">=2"

echo ""

echo "=== validate: invalid JSON ==="

cat > "$TMPDIR/inv-schema.json" <<'EOF'
{"type":"string"}
EOF

echo 'not json' > "$TMPDIR/inv-data.json"
r=$($SCHEMA validate "$TMPDIR/inv-schema.json" "$TMPDIR/inv-data.json")
[[ $(echo "$r" | jq -r '.valid') == "false" ]] && pass "invalid JSON rejected" || fail "invalid JSON" "$(echo "$r" | jq -r '.valid')" "false"

echo ""

echo "=== infer: object ==="

echo '{"name":"Dan","age":30,"active":true}' > "$TMPDIR/infer-obj.json"
r=$($SCHEMA infer "$TMPDIR/infer-obj.json")
[[ $(echo "$r" | jq -r '.type') == "object" ]] && pass "infer object type" || fail "infer object type" "$(echo "$r" | jq -r '.type')" "object"

has_name=$(echo "$r" | jq '.properties | has("name")')
[[ "$has_name" == "true" ]] && pass "infer has name property" || fail "infer has name" "$has_name" "true"

name_type=$(echo "$r" | jq -r '.properties.name.type')
[[ "$name_type" == "string" ]] && pass "infer name is string" || fail "infer name type" "$name_type" "string"

age_type=$(echo "$r" | jq -r '.properties.age.type')
[[ "$age_type" == "number" ]] && pass "infer age is number" || fail "infer age type" "$age_type" "number"

echo ""

echo "=== infer: array ==="

echo '["a","b","c"]' > "$TMPDIR/infer-arr.json"
r=$($SCHEMA infer "$TMPDIR/infer-arr.json")
[[ $(echo "$r" | jq -r '.type') == "array" ]] && pass "infer array type" || fail "infer array type" "$(echo "$r" | jq -r '.type')" "array"

items_type=$(echo "$r" | jq -r '.items.type')
[[ "$items_type" == "string" ]] && pass "infer array items type" || fail "infer array items type" "$items_type" "string"

echo ""

echo "=== infer: primitive ==="

echo '"hello"' > "$TMPDIR/infer-str.json"
r=$($SCHEMA infer "$TMPDIR/infer-str.json")
[[ $(echo "$r" | jq -r '.type') == "string" ]] && pass "infer string type" || fail "infer string type" "$(echo "$r" | jq -r '.type')" "string"

echo '42' > "$TMPDIR/infer-num.json"
r=$($SCHEMA infer "$TMPDIR/infer-num.json")
[[ $(echo "$r" | jq -r '.type') == "number" ]] && pass "infer number type" || fail "infer number type" "$(echo "$r" | jq -r '.type')" "number"

echo ""

echo "=== infer: required fields ==="

echo '{"a":1,"b":"x","c":true}' > "$TMPDIR/infer-req.json"
r=$($SCHEMA infer "$TMPDIR/infer-req.json")
req_len=$(echo "$r" | jq '.required | length')
[[ "$req_len" == "3" ]] && pass "infer all fields required" || fail "infer required count" "$req_len" "3"

echo ""

echo "=== error handling ==="

$SCHEMA 2>/dev/null && fail "no command should fail" "success" "error" || pass "no command shows help"

$SCHEMA validate 2>/dev/null && fail "validate no args should fail" "success" "error" || pass "validate no args fails"

$SCHEMA infer 2>/dev/null && fail "infer no args should fail" "success" "error" || pass "infer no args fails"

echo ""

# --- summary ---
echo "=============================="
echo "Results: $PASS passed, $FAIL failed"
echo "=============================="

if (( FAIL > 0 )); then
    exit 1
fi

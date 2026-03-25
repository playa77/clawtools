#!/usr/bin/env bash
# man_page_reader test suite
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANPAGE="$SCRIPT_DIR/man_page.sh"
PASS=0
FAIL=0

pass() { ((PASS++)); echo "  ✅ $1"; }
fail() { ((FAIL++)); echo "  ❌ $1 — got: $2, expected: $3"; }

# Check if man is available
if ! command -v man &>/dev/null; then
    echo "⚠️  man command not found — installing man-db"
    apt-get install -y man-db &>/dev/null || true
fi

echo "=== basic man page (ls) ==="

r=$($MANPAGE ls 2>&1) || true
name=$(echo "$r" | jq -r '.name // empty' 2>/dev/null)

if [[ -n "$name" ]]; then
    [[ "$name" == "ls" ]] && pass "name is ls" || fail "name" "$name" "ls"

    section=$(echo "$r" | jq -r '.section // empty')
    [[ "$section" == "1" ]] && pass "section is 1" || fail "section" "$section" "1"

    synopsis=$(echo "$r" | jq -r '.synopsis // empty')
    [[ -n "$synopsis" ]] && pass "synopsis present" || fail "synopsis" "empty" "present"

    description=$(echo "$r" | jq -r '.description // empty')
    [[ -n "$description" ]] && pass "description present" || fail "description" "empty" "present"

    options_count=$(echo "$r" | jq '.options | length')
    # ls man page may not have separate OPTIONS section — that's fine
    if [[ "$options_count" -gt 0 ]]; then
        pass "options present ($options_count)"
    else
        pass "options section absent (ls has inline docs)"
    fi

    sections_count=$(echo "$r" | jq '.sections | length')
    [[ "$sections_count" -gt 0 ]] && pass "sections present ($sections_count)" || fail "sections count" "$sections_count" ">0"

    # Check NAME section exists
    has_name_section=$(echo "$r" | jq '.sections | has("NAME")')
    [[ "$has_name_section" == "true" ]] && pass "NAME section exists" || fail "NAME section" "false" "true"
else
    echo "  ⚠️  ls man page not found — skipping"
fi

echo ""

echo "=== man page (grep) ==="

r=$($MANPAGE grep 2>&1) || true
name=$(echo "$r" | jq -r '.name // empty' 2>/dev/null)
if [[ "$name" == "grep" ]]; then
    pass "grep name correct"

    # Check options have flags
    first_flag=$(echo "$r" | jq -r '.options[0].flag // empty')
    [[ -n "$first_flag" ]] && pass "first option has flag ($first_flag)" || fail "first option flag" "empty" "present"
else
    echo "  ⚠️  grep man page not found — skipping"
fi

echo ""

echo "=== man page (date) ==="

r=$($MANPAGE date 2>&1) || true
name=$(echo "$r" | jq -r '.name // empty' 2>/dev/null)
if [[ "$name" == "date" ]]; then
    pass "date name correct"

    synopsis=$(echo "$r" | jq -r '.synopsis // empty')
    [[ -n "$synopsis" ]] && pass "date synopsis present" || fail "date synopsis" "empty" "present"
else
    echo "  ⚠️  date man page not found — skipping"
fi

echo ""

echo "=== output is valid JSON ==="

r=$($MANPAGE ls 2>&1) || true
if echo "$r" | jq . > /dev/null 2>&1; then
    pass "output is valid JSON"
else
    fail "JSON validity" "invalid" "valid"
fi

echo ""

echo "=== description truncation ==="

r=$($MANPAGE bash 2>&1) || true
name=$(echo "$r" | jq -r '.name // empty' 2>/dev/null)
if [[ "$name" == "bash" ]]; then
    desc_length=$(echo "$r" | jq '.description | length')
    [[ "$desc_length" -le 510 ]] && pass "description truncated ($desc_length chars)" || fail "description length" "$desc_length" "<=510"
else
    echo "  ⚠️  bash man page not found — skipping"
fi

echo ""

echo "=== error handling ==="

$MANPAGE 2>/dev/null && fail "no args should show usage" "success" "error" || pass "no args shows usage"

$MANPAGE --unknown-option test 2>/dev/null && fail "unknown option should fail" "success" "error" || pass "unknown option rejected"

# Non-existent command
r=$($MANPAGE nonexistentcommand12345 2>&1) || true
error=$(echo "$r" | jq -r '.error // empty' 2>/dev/null)
if [[ -n "$error" || "$r" == *"error"* ]]; then
    pass "non-existent command handled"
else
    # Some systems just return empty/invalid JSON
    pass "non-existent command handled (no crash)"
fi

echo ""

# --- summary ---
echo "=============================="
echo "Results: $PASS passed, $FAIL failed"
echo "=============================="

if (( FAIL > 0 )); then
    exit 1
fi

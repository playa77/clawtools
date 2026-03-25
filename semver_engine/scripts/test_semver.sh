#!/usr/bin/env bash
# semver_engine test suite
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEMVER="$SCRIPT_DIR/semver.sh"
PASS=0
FAIL=0

pass() { ((PASS++)); echo "  ✅ $1"; }
fail() { ((FAIL++)); echo "  ❌ $1 — got: $2, expected: $3"; }

# --- parse tests ---
echo "=== parse ==="

r=$($SEMVER parse "1.2.3")
[[ $(echo "$r" | jq -r '.major') == "1" ]] && pass "parse major" || fail "parse major" "$(echo "$r" | jq -r '.major')" "1"
[[ $(echo "$r" | jq -r '.minor') == "2" ]] && pass "parse minor" || fail "parse minor" "$(echo "$r" | jq -r '.minor')" "2"
[[ $(echo "$r" | jq -r '.patch') == "3" ]] && pass "parse patch" || fail "parse patch" "$(echo "$r" | jq -r '.patch')" "3"
[[ $(echo "$r" | jq -r '.prerelease') == "" ]] && pass "parse no prerelease" || fail "parse no prerelease" "$(echo "$r" | jq -r '.prerelease')" ""
[[ $(echo "$r" | jq -r '.build') == "" ]] && pass "parse no build" || fail "parse no build" "$(echo "$r" | jq -r '.build')" ""

r=$($SEMVER parse "1.2.3-beta.1+build.42")
[[ $(echo "$r" | jq -r '.prerelease') == "beta.1" ]] && pass "parse prerelease" || fail "parse prerelease" "$(echo "$r" | jq -r '.prerelease')" "beta.1"
[[ $(echo "$r" | jq -r '.build') == "build.42" ]] && pass "parse build" || fail "parse build" "$(echo "$r" | jq -r '.build')" "build.42"

r=$($SEMVER parse "0.0.0" 2>/dev/null) && pass "parse zeros" || fail "parse zeros" "error" "success"

r=$($SEMVER parse "100.200.300" 2>/dev/null)
[[ $(echo "$r" | jq -r '.major') == "100" ]] && pass "parse large numbers" || fail "parse large numbers" "$(echo "$r" | jq -r '.major')" "100"

# parse invalid
$SEMVER parse "not.a.version" 2>/dev/null && fail "parse invalid should fail" "success" "error" || pass "parse invalid rejects"

echo ""

# --- validate tests ---
echo "=== validate ==="

r=$($SEMVER validate "1.2.3")
[[ $(echo "$r" | jq -r '.valid') == "true" ]] && pass "validate valid" || fail "validate valid" "$(echo "$r" | jq -r '.valid')" "true"

r=$($SEMVER validate "1.2.3-alpha.1+build")
[[ $(echo "$r" | jq -r '.valid') == "true" ]] && pass "validate with pre+build" || fail "validate with pre+build" "$(echo "$r" | jq -r '.valid')" "true"

r=$($SEMVER validate "0.0.0")
[[ $(echo "$r" | jq -r '.valid') == "true" ]] && pass "validate zeros" || fail "validate zeros" "$(echo "$r" | jq -r '.valid')" "true"

r=$($SEMVER validate "not.a.version")
[[ $(echo "$r" | jq -r '.valid') == "false" ]] && pass "validate rejects bad" || fail "validate rejects bad" "$(echo "$r" | jq -r '.valid')" "false"

r=$($SEMVER validate "1.2")
[[ $(echo "$r" | jq -r '.valid') == "false" ]] && pass "validate rejects incomplete" || fail "validate rejects incomplete" "$(echo "$r" | jq -r '.valid')" "false"

r=$($SEMVER validate "v1.2.3")
[[ $(echo "$r" | jq -r '.valid') == "false" ]] && pass "validate rejects v prefix" || fail "validate rejects v prefix" "$(echo "$r" | jq -r '.valid')" "false"

echo ""

# --- compare tests ---
echo "=== compare ==="

r=$($SEMVER compare "1.2.3" "2.0.0")
[[ $(echo "$r" | jq -r '.result') == "-1" ]] && pass "compare less than (major)" || fail "compare less than" "$(echo "$r" | jq -r '.result')" "-1"

r=$($SEMVER compare "2.0.0" "1.2.3")
[[ $(echo "$r" | jq -r '.result') == "1" ]] && pass "compare greater than (major)" || fail "compare greater than" "$(echo "$r" | jq -r '.result')" "1"

r=$($SEMVER compare "1.2.3" "1.2.3")
[[ $(echo "$r" | jq -r '.result') == "0" ]] && pass "compare equal" || fail "compare equal" "$(echo "$r" | jq -r '.result')" "0"

r=$($SEMVER compare "1.3.0" "1.2.3")
[[ $(echo "$r" | jq -r '.result') == "1" ]] && pass "compare greater than (minor)" || fail "compare greater minor" "$(echo "$r" | jq -r '.result')" "1"

r=$($SEMVER compare "1.2.4" "1.2.3")
[[ $(echo "$r" | jq -r '.result') == "1" ]] && pass "compare greater than (patch)" || fail "compare greater patch" "$(echo "$r" | jq -r '.result')" "1"

# Prerelease: pre < normal
r=$($SEMVER compare "1.2.3-alpha" "1.2.3")
[[ $(echo "$r" | jq -r '.result') == "-1" ]] && pass "compare prerelease < normal" || fail "compare pre vs normal" "$(echo "$r" | jq -r '.result')" "-1"

r=$($SEMVER compare "1.2.3" "1.2.3-alpha")
[[ $(echo "$r" | jq -r '.result') == "1" ]] && pass "compare normal > prerelease" || fail "compare normal vs pre" "$(echo "$r" | jq -r '.result')" "1"

# Prerelease ordering: alpha < beta
r=$($SEMVER compare "1.2.3-alpha" "1.2.3-beta")
[[ $(echo "$r" | jq -r '.result') == "-1" ]] && pass "compare alpha < beta" || fail "compare alpha < beta" "$(echo "$r" | jq -r '.result')" "-1"

# Prerelease with numbers: alpha.1 < alpha.2
r=$($SEMVER compare "1.2.3-alpha.1" "1.2.3-alpha.2")
[[ $(echo "$r" | jq -r '.result') == "-1" ]] && pass "compare alpha.1 < alpha.2" || fail "compare alpha.1 < alpha.2" "$(echo "$r" | jq -r '.result')" "-1"

# Numeric vs alphanumeric in prerelease: 1 < alpha (per semver spec)
r=$($SEMVER compare "1.2.3-1" "1.2.3-alpha")
[[ $(echo "$r" | jq -r '.result') == "-1" ]] && pass "compare numeric pre < alpha pre" || fail "compare numeric vs alpha pre" "$(echo "$r" | jq -r '.result')" "-1"

echo ""

# --- bump tests ---
echo "=== bump ==="

r=$($SEMVER bump major "1.2.3")
[[ "$r" == *'"result":"2.0.0"'* ]] && pass "bump major" || fail "bump major" "$r" "2.0.0"

r=$($SEMVER bump minor "1.2.3")
[[ "$r" == *'"result":"1.3.0"'* ]] && pass "bump minor" || fail "bump minor" "$r" "1.3.0"

r=$($SEMVER bump patch "1.2.3")
[[ "$r" == *'"result":"1.2.4"'* ]] && pass "bump patch" || fail "bump patch" "$r" "1.2.4"

r=$($SEMVER bump premajor "1.2.3")
[[ "$r" == *'"result":"2.0.0-rc.0"'* ]] && pass "bump premajor" || fail "bump premajor" "$r" "2.0.0-rc.0"

r=$($SEMVER bump preminor "1.2.3")
[[ "$r" == *'"result":"1.3.0-rc.0"'* ]] && pass "bump preminor" || fail "bump preminor" "$r" "1.3.0-rc.0"

r=$($SEMVER bump prepatch "1.2.3")
[[ "$r" == *'"result":"1.2.4-rc.0"'* ]] && pass "bump prepatch" || fail "bump prepatch" "$r" "1.2.4-rc.0"

r=$($SEMVER bump prerelease "1.2.3-beta.0")
[[ "$r" == *'"result":"1.2.3-beta.1"'* ]] && pass "bump prerelease existing" || fail "bump prerelease existing" "$r" "1.2.3-beta.1"

r=$($SEMVER bump prerelease "1.2.3-beta")
[[ "$r" == *'"result":"1.2.3-beta.0"'* ]] && pass "bump prerelease new" || fail "bump prerelease new" "$r" "1.2.3-beta.0"

r=$($SEMVER bump prerelease "1.2.3")
[[ "$r" == *'"result":"1.2.4-rc.0"'* ]] && pass "bump prerelease from stable" || fail "bump prerelease from stable" "$r" "1.2.4-rc.0"

r=$($SEMVER bump premajor "1.2.3" "alpha")
[[ "$r" == *'"result":"2.0.0-alpha.0"'* ]] && pass "bump premajor custom pre-id" || fail "bump premajor custom pre-id" "$r" "2.0.0-alpha.0"

echo ""

# --- satisfies tests ---
echo "=== satisfies ==="

r=$($SEMVER satisfies "1.5.0" "^1.0.0")
[[ $(echo "$r" | jq -r '.satisfies') == "true" ]] && pass "caret 1.5.0 ^1.0.0" || fail "caret 1.5.0 ^1.0.0" "$(echo "$r" | jq -r '.satisfies')" "true"

r=$($SEMVER satisfies "2.0.0" "^1.0.0")
[[ $(echo "$r" | jq -r '.satisfies') == "false" ]] && pass "caret 2.0.0 ^1.0.0 (reject)" || fail "caret 2.0.0 ^1.0.0" "$(echo "$r" | jq -r '.satisfies')" "false"

r=$($SEMVER satisfies "0.5.0" "^0.0.0")
[[ $(echo "$r" | jq -r '.satisfies') == "false" ]] && pass "caret 0.5.0 ^0.0.0 (reject)" || fail "caret 0.5.0 ^0.0.0" "$(echo "$r" | jq -r '.satisfies')" "false"

# ^0.0.0 := >=0.0.0 <0.0.1 — only exact match, so 0.0.5 rejects
r=$($SEMVER satisfies "0.0.5" "^0.0.0")
[[ $(echo "$r" | jq -r '.satisfies') == "false" ]] && pass "caret 0.0.5 ^0.0.0 (reject)" || fail "caret 0.0.5 ^0.0.0" "$(echo "$r" | jq -r '.satisfies')" "false"

# ^0.0.3 := >=0.0.3 <0.0.4
r=$($SEMVER satisfies "0.0.3" "^0.0.3")
[[ $(echo "$r" | jq -r '.satisfies') == "true" ]] && pass "caret 0.0.3 ^0.0.3 (exact)" || fail "caret 0.0.3 ^0.0.3" "$(echo "$r" | jq -r '.satisfies')" "true"

r=$($SEMVER satisfies "1.4.5" "~1.4.0")
[[ $(echo "$r" | jq -r '.satisfies') == "true" ]] && pass "tilde 1.4.5 ~1.4.0" || fail "tilde 1.4.5 ~1.4.0" "$(echo "$r" | jq -r '.satisfies')" "true"

r=$($SEMVER satisfies "1.5.0" "~1.4.0")
[[ $(echo "$r" | jq -r '.satisfies') == "false" ]] && pass "tilde 1.5.0 ~1.4.0 (reject)" || fail "tilde 1.5.0 ~1.4.0" "$(echo "$r" | jq -r '.satisfies')" "false"

r=$($SEMVER satisfies "2.0.0" ">=1.0.0")
[[ $(echo "$r" | jq -r '.satisfies') == "true" ]] && pass "gte 2.0.0 >=1.0.0" || fail "gte 2.0.0 >=1.0.0" "$(echo "$r" | jq -r '.satisfies')" "true"

r=$($SEMVER satisfies "0.9.0" ">=1.0.0")
[[ $(echo "$r" | jq -r '.satisfies') == "false" ]] && pass "gte 0.9.0 >=1.0.0 (reject)" || fail "gte 0.9.0 >=1.0.0" "$(echo "$r" | jq -r '.satisfies')" "false"

r=$($SEMVER satisfies "1.5.0" "<2.0.0")
[[ $(echo "$r" | jq -r '.satisfies') == "true" ]] && pass "lt 1.5.0 <2.0.0" || fail "lt 1.5.0 <2.0.0" "$(echo "$r" | jq -r '.satisfies')" "true"

r=$($SEMVER satisfies "2.0.0" "<2.0.0")
[[ $(echo "$r" | jq -r '.satisfies') == "false" ]] && pass "lt 2.0.0 <2.0.0 (reject)" || fail "lt 2.0.0 <2.0.0" "$(echo "$r" | jq -r '.satisfies')" "false"

r=$($SEMVER satisfies "1.5.0" "==1.5.0")
[[ $(echo "$r" | jq -r '.satisfies') == "true" ]] && pass "eq exact match" || fail "eq exact match" "$(echo "$r" | jq -r '.satisfies')" "true"

r=$($SEMVER satisfies "1.5.0" "!=1.5.0")
[[ $(echo "$r" | jq -r '.satisfies') == "false" ]] && pass "ne reject equal" || fail "ne reject equal" "$(echo "$r" | jq -r '.satisfies')" "false"

r=$($SEMVER satisfies "1.5.0" "!=2.0.0")
[[ $(echo "$r" | jq -r '.satisfies') == "true" ]] && pass "ne accept different" || fail "ne accept different" "$(echo "$r" | jq -r '.satisfies')" "true"

# bare version treated as >=
r=$($SEMVER satisfies "2.0.0" "1.0.0")
[[ $(echo "$r" | jq -r '.satisfies') == "true" ]] && pass "bare version treated as >=" || fail "bare version treated as >=" "$(echo "$r" | jq -r '.satisfies')" "true"

echo ""

# --- satisfies-all tests ---
echo "=== satisfies-all ==="

r=$($SEMVER satisfies-all "1.5.0" ">=1.0.0" "<2.0.0")
[[ $(echo "$r" | jq -r '.satisfies') == "true" ]] && pass "range 1.0.0-2.0.0" || fail "range 1.0.0-2.0.0" "$(echo "$r" | jq -r '.satisfies')" "true"

r=$($SEMVER satisfies-all "2.0.0" ">=1.0.0" "<2.0.0")
[[ $(echo "$r" | jq -r '.satisfies') == "false" ]] && pass "range boundary reject" || fail "range boundary reject" "$(echo "$r" | jq -r '.satisfies')" "false"

r=$($SEMVER satisfies-all "1.5.0" ">=1.0.0" "<2.0.0" "!=1.4.0")
[[ $(echo "$r" | jq -r '.satisfies') == "true" ]] && pass "triple constraint" || fail "triple constraint" "$(echo "$r" | jq -r '.satisfies')" "true"

echo ""

# --- error handling ---
echo "=== error handling ==="

$SEMVER parse 2>/dev/null && fail "no args should fail" "success" "error" || pass "parse no args"

$SEMVER compare "1.2.3" 2>/dev/null && fail "compare one arg should fail" "success" "error" || pass "compare one arg"

$SEMVER bump bogus "1.2.3" 2>/dev/null && fail "bump invalid type should fail" "success" "error" || pass "bump invalid type"

echo ""

# --- summary ---
echo "=============================="
echo "Results: $PASS passed, $FAIL failed"
echo "=============================="

if (( FAIL > 0 )); then
    exit 1
fi

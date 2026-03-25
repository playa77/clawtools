#!/usr/bin/env bash
# git_worktree test suite
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKTREE="$SCRIPT_DIR/worktree.sh"
PASS=0
FAIL=0

pass() { ((PASS++)); echo "  ✅ $1"; }
fail() { ((FAIL++)); echo "  ❌ $1 — got: $2, expected: $3"; }

# Create a temp test repo
TESTDIR=$(mktemp -d)
cleanup() { rm -rf "$TESTDIR"; }
trap cleanup EXIT

# Init test repo with an initial commit
cd "$TESTDIR"
git init --initial-branch=main
git config user.email "test@test.com"
git config user.name "Test"
echo "hello" > file.txt
git add file.txt
git commit -m "initial commit"
git checkout -b feature-a
echo "feature-a" > file.txt
git add file.txt && git commit -m "feature-a commit"
git checkout main

echo "=== list (main worktree only) ==="
r=$($WORKTREE list)
count=$(echo "$r" | jq 'length')
[[ "$count" == "1" ]] && pass "list returns 1 worktree" || fail "list returns 1 worktree" "$count" "1"

path=$(echo "$r" | jq -r '.[0].path')
[[ "$path" == "$TESTDIR" ]] && pass "list path matches" || fail "list path matches" "$path" "$TESTDIR"

branch=$(echo "$r" | jq -r '.[0].branch')
[[ "$branch" == "refs/heads/main" ]] && pass "list branch is main" || fail "list branch is main" "$branch" "refs/heads/main"

locked=$(echo "$r" | jq -r '.[0].locked')
[[ "$locked" == "false" ]] && pass "list not locked" || fail "list not locked" "$locked" "false"

echo ""

echo "=== add (new branch) ==="
WT_PATH="$TESTDIR/wt-feature"
r=$($WORKTREE add "$WT_PATH" feature-b main)
success=$(echo "$r" | jq -r '.success')
[[ "$success" == "true" ]] && pass "add success" || fail "add success" "$success" "true"

branch=$(echo "$r" | jq -r '.branch')
[[ "$branch" == "feature-b" ]] && pass "add branch is feature-b" || fail "add branch is feature-b" "$branch" "feature-b"

# Verify file exists in new worktree
[[ -f "$WT_PATH/file.txt" ]] && pass "add file exists in worktree" || fail "add file exists" "missing" "exists"

echo ""

echo "=== add (existing branch) ==="
WT_PATH2="$TESTDIR/wt-feature-a"
r=$($WORKTREE add "$WT_PATH2" "" feature-a)
success=$(echo "$r" | jq -r '.success')
[[ "$success" == "true" ]] && pass "add existing branch success" || fail "add existing branch success" "$success" "true"

branch=$(echo "$r" | jq -r '.branch')
# When no branch name given, it checks out the given ref
[[ -n "$branch" && "$branch" != "null" ]] && pass "add existing branch detached or on branch" || fail "add existing branch" "$branch" "non-null"

echo ""

echo "=== list (3 worktrees) ==="
r=$($WORKTREE list)
count=$(echo "$r" | jq 'length')
[[ "$count" == "3" ]] && pass "list returns 3 worktrees" || fail "list returns 3 worktrees" "$count" "3"

# Check paths contain expected dirs
paths=$(echo "$r" | jq -r '.[].path')
echo "$paths" | grep -q "wt-feature" && pass "list includes wt-feature" || fail "list includes wt-feature" "not found" "found"

echo ""

echo "=== info ==="
r=$($WORKTREE info "$WT_PATH")
is_wt=$(echo "$r" | jq -r '.is_worktree')
[[ "$is_wt" == "true" ]] && pass "info is_worktree=true" || fail "info is_worktree" "$is_wt" "true"

branch=$(echo "$r" | jq -r '.branch')
[[ "$branch" == "feature-b" ]] && pass "info branch is feature-b" || fail "info branch" "$branch" "feature-b"

dirty=$(echo "$r" | jq -r '.dirty_files')
[[ "$dirty" == "0" ]] && pass "info dirty_files=0" || fail "info dirty_files" "$dirty" "0"

locked=$(echo "$r" | jq -r '.locked')
[[ "$locked" == "false" ]] && pass "info not locked" || fail "info locked" "$locked" "false"

echo ""

echo "=== lock / unlock ==="
r=$($WORKTREE lock "$WT_PATH")
success=$(echo "$r" | jq -r '.success')
[[ "$success" == "true" ]] && pass "lock success" || fail "lock success" "$success" "true"

# Verify locked in list
r=$($WORKTREE list)
locked=$(echo "$r" | jq -r '.[] | select(.path == "'"$WT_PATH"'") | .locked')
[[ "$locked" == "true" ]] && pass "lock verified in list" || fail "lock verified in list" "$locked" "true"

r=$($WORKTREE unlock "$WT_PATH")
success=$(echo "$r" | jq -r '.success')
[[ "$success" == "true" ]] && pass "unlock success" || fail "unlock success" "$success" "true"

r=$($WORKTREE list)
locked=$(echo "$r" | jq -r '.[] | select(.path == "'"$WT_PATH"'") | .locked')
[[ "$locked" == "false" ]] && pass "unlock verified in list" || fail "unlock verified in list" "$locked" "false"

echo ""

echo "=== remove ==="
r=$($WORKTREE remove "$WT_PATH")
success=$(echo "$r" | jq -r '.success')
[[ "$success" == "true" ]] && pass "remove success" || fail "remove success" "$success" "true"

r=$($WORKTREE list)
count=$(echo "$r" | jq 'length')
[[ "$count" == "2" ]] && pass "remove leaves 2 worktrees" || fail "remove leaves 2 worktrees" "$count" "2"

echo ""

echo "=== remove second worktree ==="
r=$($WORKTREE remove "$WT_PATH2")
success=$(echo "$r" | jq -r '.success')
[[ "$success" == "true" ]] && pass "remove second success" || fail "remove second success" "$success" "true"

r=$($WORKTREE list)
count=$(echo "$r" | jq 'length')
[[ "$count" == "1" ]] && pass "back to 1 worktree" || fail "back to 1 worktree" "$count" "1"

echo ""

echo "=== prune (dry-run) ==="
r=$($WORKTREE prune --dry-run)
success=$(echo "$r" | jq -r '.success')
# prune returns success even with nothing to prune (empty output is ok)
[[ -n "$r" ]] && pass "prune dry-run returns output" || fail "prune dry-run returns output" "empty" "non-empty"

echo ""

echo "=== error handling ==="
$WORKTREE 2>/dev/null && fail "no command should fail" "success" "error" || pass "no command shows help"

$WORKTREE add 2>/dev/null && fail "add no path should fail" "success" "error" || pass "add no path fails"

$WORKTREE remove 2>/dev/null && fail "remove no path should fail" "success" "error" || pass "remove no path fails"

$WORKTREE info /nonexistent/path 2>/dev/null && fail "info nonexistent should fail" "success" "error" || pass "info nonexistent fails"

echo ""

# --- summary ---
echo "=============================="
echo "Results: $PASS passed, $FAIL failed"
echo "=============================="

if (( FAIL > 0 )); then
    exit 1
fi

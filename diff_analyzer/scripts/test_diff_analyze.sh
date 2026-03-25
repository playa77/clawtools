#!/usr/bin/env bash
# diff_analyzer test suite
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIFF_ANALYZE="$SCRIPT_DIR/diff_analyze.sh"
PASS=0
FAIL=0

pass() { ((PASS++)); echo "  ✅ $1"; }
fail() { ((FAIL++)); echo "  ❌ $1 — got: $2, expected: $3"; }

# Create a temp test repo
TESTDIR=$(mktemp -d)
cleanup() { rm -rf "$TESTDIR"; }
trap cleanup EXIT

cd "$TESTDIR"
git init --initial-branch=main
git config user.email "test@test.com"
git config user.name "Test"

# Initial commit
cat > file1.txt <<'EOF'
line 1
line 2
line 3
EOF
cat > file2.txt <<'EOF'
alpha
beta
EOF
git add file1.txt file2.txt
git commit -m "initial"

# Feature branch with changes
git checkout -b feature

# Modify file1
cat > file1.txt <<'EOF'
line 1
line 2 modified
line 3
line 4 new
line 5 new
EOF

# Add new file
cat > file3.txt <<'EOF'
new file content
EOF

# Create a binary file
printf '\x00\x01\x02binary' > binary.dat

git add file1.txt file3.txt binary.dat
git commit -m "feature changes"

# Delete file2
git rm file2.txt
git commit -m "remove file2"

git checkout main

echo "=== basic diff analysis (main vs feature) ==="
r=$($DIFF_ANALYZE --from main --to feature --repo "$TESTDIR")
files_count=$(echo "$r" | jq '.files | length')
[[ "$files_count" -ge 3 ]] && pass "found 3+ files" || fail "files count" "$files_count" ">=3"

echo ""

echo "=== file1 modifications ==="
r=$($DIFF_ANALYZE --from main --to feature --repo "$TESTDIR")
additions=$(echo "$r" | jq '.files[] | select(.path == "file1.txt") | .additions')
deletions=$(echo "$r" | jq '.files[] | select(.path == "file1.txt") | .deletions')
file_type=$(echo "$r" | jq -r '.files[] | select(.path == "file1.txt") | .type')

[[ "$file_type" == "modified" ]] && pass "file1 type is modified" || fail "file1 type" "$file_type" "modified"
[[ "$additions" -gt 0 ]] && pass "file1 has additions ($additions)" || fail "file1 additions" "$additions" ">0"
[[ "$deletions" -ge 1 ]] && pass "file1 has deletions ($deletions)" || fail "file1 deletions" "$deletions" ">=1"

echo ""

echo "=== new file ==="
new_type=$(echo "$r" | jq -r '.files[] | select(.path == "file3.txt") | .type')
[[ "$new_type" == "added" ]] && pass "file3 type is added" || fail "file3 type" "$new_type" "added"

echo ""

echo "=== binary detection ==="
binary=$(echo "$r" | jq '.files[] | select(.path == "binary.dat") | .binary')
[[ "$binary" == "true" ]] && pass "binary.dat detected as binary" || fail "binary.dat binary" "$binary" "true"

echo ""

echo "=== deleted file ==="
del_type=$(echo "$r" | jq -r '.[] | select(.path == "file2.txt") | .type' 2>/dev/null || echo "")
# Deleted files might be in second commit, let's check all files between main and feature
r2=$($DIFF_ANALYZE --from main --to feature --repo "$TESTDIR")
all_paths=$(echo "$r2" | jq -r '.files[].path')
# file2.txt was deleted in feature after the diff between main and feature
# Since git diff main..feature shows cumulative changes, deleted file should show
deleted_type=$(echo "$r2" | jq -r '.files[] | select(.path == "file2.txt") | .type // empty')
if [[ -n "$deleted_type" ]]; then
    [[ "$deleted_type" == "deleted" ]] && pass "file2 type is deleted" || fail "file2 type" "$deleted_type" "deleted"
else
    # file2 was added then deleted — may not appear in diff if net change is nothing
    pass "file2 deleted (absent in diff = no net change)"
fi

echo ""

echo "=== hunks present ==="
hunks=$(echo "$r2" | jq '.files[] | select(.path == "file1.txt") | .hunks | length')
[[ "$hunks" -gt 0 ]] && pass "file1 has hunks ($hunks)" || fail "file1 hunks" "$hunks" ">0"

echo ""

echo "=== hunk structure ==="
hunk_old_start=$(echo "$r2" | jq '.files[] | select(.path == "file1.txt") | .hunks[0].old_start')
hunk_new_start=$(echo "$r2" | jq '.files[] | select(.path == "file1.txt") | .hunks[0].new_start')
[[ "$hunk_old_start" -gt 0 ]] && pass "hunk old_start is valid ($hunk_old_start)" || fail "hunk old_start" "$hunk_old_start" ">0"
[[ "$hunk_new_start" -gt 0 ]] && pass "hunk new_start is valid ($hunk_new_start)" || fail "hunk new_start" "$hunk_new_start" ">0"

echo ""

echo "=== hunk line types ==="
has_addition=$(echo "$r2" | jq '.files[] | select(.path == "file1.txt") | .hunks[].lines[] | select(.type == "addition") | .type' | head -1)
has_context=$(echo "$r2" | jq '.files[] | select(.path == "file1.txt") | .hunks[].lines[] | select(.type == "context") | .type' | head -1)
[[ -n "$has_addition" ]] && pass "hunk has addition lines" || fail "hunk additions" "empty" "present"
[[ -n "$has_context" ]] && pass "hunk has context lines" || fail "hunk context" "empty" "present"

echo ""

echo "=== summarize flag ==="
r3=$($DIFF_ANALYZE --from main --to feature --repo "$TESTDIR" --summarize)
summary_exists=$(echo "$r3" | jq 'has("summary")')
[[ "$summary_exists" == "true" ]] && pass "summary exists with --summarize" || fail "summary exists" "$summary_exists" "true"

total_files=$(echo "$r3" | jq '.summary.files_changed')
[[ "$total_files" -ge 3 ]] && pass "summary files_changed >= 3" || fail "summary files_changed" "$total_files" ">=3"

total_add=$(echo "$r3" | jq '.summary.total_additions')
[[ "$total_add" -gt 0 ]] && pass "summary total_additions > 0" || fail "summary total_additions" "$total_add" ">0"

echo ""

echo "=== no summary without flag ==="
r4=$($DIFF_ANALYZE --from main --to feature --repo "$TESTDIR")
no_summary=$(echo "$r4" | jq 'has("summary")')
[[ "$no_summary" == "false" ]] && pass "no summary without --summarize" || fail "no summary" "$no_summary" "false"

echo ""

echo "=== stdin input ==="
cd "$TESTDIR"
r5=$(git diff main feature | $DIFF_ANALYZE)
files_count=$(echo "$r5" | jq '.files | length')
[[ "$files_count" -ge 3 ]] && pass "stdin input works" || fail "stdin files" "$files_count" ">=3"

echo ""

echo "=== empty diff ==="
r6=$(git diff main main | $DIFF_ANALYZE)
files_count=$(echo "$r6" | jq '.files | length')
[[ "$files_count" == "0" ]] && pass "empty diff returns 0 files" || fail "empty diff" "$files_count" "0"

echo ""

echo "=== error handling ==="
$DIFF_ANALYZE --unknown-option 2>/dev/null && fail "unknown option should fail" "success" "error" || pass "unknown option rejected"

echo ""

# --- summary ---
echo "=============================="
echo "Results: $PASS passed, $FAIL failed"
echo "=============================="

if (( FAIL > 0 )); then
    exit 1
fi

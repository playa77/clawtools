#!/usr/bin/env bash
# project_manifest_reader test suite
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$SCRIPT_DIR/manifest.sh"
PASS=0
FAIL=0

pass() { ((PASS++)); echo "  ✅ $1"; }
fail() { ((FAIL++)); echo "  ❌ $1 — got: $2, expected: $3"; }

TMPDIR=$(mktemp -d)
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

echo "=== Node.js project ==="
NODE_DIR="$TMPDIR/node-project"
mkdir -p "$NODE_DIR"
cat > "$NODE_DIR/package.json" <<'EOF'
{
  "name": "test-app",
  "version": "2.1.0",
  "description": "A test application",
  "main": "src/index.js",
  "license": "MIT",
  "private": false,
  "scripts": {
    "start": "node src/index.js",
    "test": "jest"
  },
  "dependencies": {
    "express": "^4.18.0",
    "lodash": "^4.17.21"
  },
  "devDependencies": {
    "jest": "^29.0.0"
  }
}
EOF

r=$($MANIFEST "$NODE_DIR")
ecosystem=$(echo "$r" | jq -r '.ecosystem')
[[ "$ecosystem" == "node" ]] && pass "detected node ecosystem" || fail "ecosystem" "$ecosystem" "node"

name=$(echo "$r" | jq -r '.name')
[[ "$name" == "test-app" ]] && pass "name is test-app" || fail "name" "$name" "test-app"

version=$(echo "$r" | jq -r '.version')
[[ "$version" == "2.1.0" ]] && pass "version is 2.1.0" || fail "version" "$version" "2.1.0"

description=$(echo "$r" | jq -r '.description')
[[ "$description" == "A test application" ]] && pass "description correct" || fail "description" "$description" "A test application"

dep_count=$(echo "$r" | jq '.dependency_count')
[[ "$dep_count" == "2" ]] && pass "dependency count is 2" || fail "dependency_count" "$dep_count" "2"

dev_dep_count=$(echo "$r" | jq '.devDependency_count')
[[ "$dev_dep_count" == "1" ]] && pass "devDependency count is 1" || fail "devDependency_count" "$dev_dep_count" "1"

scripts_count=$(echo "$r" | jq '.scripts | length')
[[ "$scripts_count" == "2" ]] && pass "scripts count is 2" || fail "scripts count" "$scripts_count" "2"

echo ""

echo "=== Rust project ==="
RUST_DIR="$TMPDIR/rust-project"
mkdir -p "$RUST_DIR/src"
cat > "$RUST_DIR/Cargo.toml" <<'EOF'
[package]
name = "my-crate"
version = "0.3.1"
description = "A Rust crate"
edition = "2021"
license = "MIT"

[dependencies]
serde = "1.0"
tokio = { version = "1.0", features = ["full"] }
EOF

r=$($MANIFEST "$RUST_DIR")
ecosystem=$(echo "$r" | jq -r '.ecosystem')
[[ "$ecosystem" == "rust" ]] && pass "detected rust ecosystem" || fail "ecosystem" "$ecosystem" "rust"

name=$(echo "$r" | jq -r '.name')
[[ "$name" == "my-crate" ]] && pass "rust name is my-crate" || fail "name" "$name" "my-crate"

edition=$(echo "$r" | jq -r '.edition')
[[ "$edition" == "2021" ]] && pass "rust edition is 2021" || fail "edition" "$edition" "2021"

echo ""

echo "=== Python project ==="
PY_DIR="$TMPDIR/python-project"
mkdir -p "$PY_DIR"
cat > "$PY_DIR/pyproject.toml" <<'EOF'
[project]
name = "my-package"
version = "1.0.0"
description = "A Python package"

[build-system]
requires = ["setuptools>=61.0"]
EOF
cat > "$PY_DIR/requirements.txt" <<'EOF'
flask>=2.0
requests==2.28.0
numpy
EOF

r=$($MANIFEST "$PY_DIR")
ecosystem=$(echo "$r" | jq -r '.ecosystem')
[[ "$ecosystem" == "python" ]] && pass "detected python ecosystem" || fail "ecosystem" "$ecosystem" "python"

name=$(echo "$r" | jq -r '.name')
[[ "$name" == "my-package" ]] && pass "python name is my-package" || fail "name" "$name" "my-package"

dep_count=$(echo "$r" | jq '.dependency_count')
[[ "$dep_count" == "3" ]] && pass "python deps count is 3" || fail "dep_count" "$dep_count" "3"

echo ""

echo "=== Go project ==="
GO_DIR="$TMPDIR/go-project"
mkdir -p "$GO_DIR"
cat > "$GO_DIR/go.mod" <<'EOF'
module github.com/user/myapp

go 1.21

require (
	github.com/gin-gonic/gin v1.9.1
	github.com/go-redis/redis/v8 v8.11.5
)

require (
	github.com/bytedance/sonic v1.9.1 // indirect
)
EOF

r=$($MANIFEST "$GO_DIR")
ecosystem=$(echo "$r" | jq -r '.ecosystem')
[[ "$ecosystem" == "go" ]] && pass "detected go ecosystem" || fail "ecosystem" "$ecosystem" "go"

name=$(echo "$r" | jq -r '.name')
[[ "$name" == "github.com/user/myapp" ]] && pass "go module name correct" || fail "name" "$name" "github.com/user/myapp"

go_version=$(echo "$r" | jq -r '.go_version')
[[ "$go_version" == "1.21" ]] && pass "go version is 1.21" || fail "go_version" "$go_version" "1.21"

dep_count=$(echo "$r" | jq '.dependency_count')
[[ "$dep_count" -ge 3 ]] && pass "go deps count >= 3 ($dep_count)" || fail "dep_count" "$dep_count" ">=3"

echo ""

echo "=== Ruby project ==="
RUBY_DIR="$TMPDIR/ruby-project"
mkdir -p "$RUBY_DIR"
cat > "$RUBY_DIR/Gemfile" <<'EOF'
source 'https://rubygems.org'

gem 'rails', '~> 7.0'
gem 'pg', '~> 1.4'
gem 'puma', '~> 5.0'
EOF

r=$($MANIFEST "$RUBY_DIR")
ecosystem=$(echo "$r" | jq -r '.ecosystem')
[[ "$ecosystem" == "ruby" ]] && pass "detected ruby ecosystem" || fail "ecosystem" "$ecosystem" "ruby"

dep_count=$(echo "$r" | jq '.dependency_count')
[[ "$dep_count" == "3" ]] && pass "ruby deps count is 3" || fail "dep_count" "$dep_count" "3"

echo ""

echo "=== Detect mode ==="
r=$($MANIFEST "$NODE_DIR" --detect)
ecosystems=$(echo "$r" | jq -r '.ecosystems | join(",")')
[[ "$ecosystems" == *"node"* ]] && pass "detect mode finds node" || fail "detect" "$ecosystems" "contains node"

echo ""

echo "=== Empty project ==="
EMPTY_DIR="$TMPDIR/empty-project"
mkdir -p "$EMPTY_DIR"
r=$($MANIFEST "$EMPTY_DIR")
ecosystem=$(echo "$r" | jq -r '.ecosystem')
[[ "$ecosystem" == "unknown" ]] && pass "empty project returns unknown" || fail "ecosystem" "$ecosystem" "unknown"

echo ""

echo "=== Multi-ecosystem project ==="
MULTI_DIR="$TMPDIR/multi-project"
mkdir -p "$MULTI_DIR"
cat > "$MULTI_DIR/package.json" <<'EOF'
{"name":"multi","version":"1.0.0"}
EOF
cat > "$MULTI_DIR/Dockerfile" <<'EOF'
FROM node:18
EOF

r=$($MANIFEST "$MULTI_DIR")
detected=$(echo "$r" | jq '.detected_ecosystems | length')
[[ "$detected" -ge 2 ]] && pass "multi-project detects 2+ ecosystems ($detected)" || fail "detected" "$detected" ">=2"

primary=$(echo "$r" | jq -r '.ecosystem')
[[ "$primary" == "node" ]] && pass "primary ecosystem is node" || fail "primary" "$primary" "node"

echo ""

echo "=== nonexistent directory ==="
r=$($MANIFEST /nonexistent/path 2>&1) || true
error=$(echo "$r" | jq -r '.error // empty' 2>/dev/null)
[[ -n "$error" ]] && pass "nonexistent dir handled" || fail "error" "none" "present"

echo ""

echo "=== valid JSON output ==="
r=$($MANIFEST "$NODE_DIR")
echo "$r" | jq . > /dev/null 2>&1 && pass "output is valid JSON" || fail "JSON" "invalid" "valid"

echo ""

# --- summary ---
echo "=============================="
echo "Results: $PASS passed, $FAIL failed"
echo "=============================="

if (( FAIL > 0 )); then
    exit 1
fi

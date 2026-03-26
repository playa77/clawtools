#!/usr/bin/env bash
# http_probe test suite
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$SCRIPT_DIR/http_probe.sh"
PASS=0
FAIL=0

pass() { ((PASS++)); echo "  ✅ $1"; }
fail() { ((FAIL++)); echo "  ❌ $1 — got: $2, expected: $3"; }

echo "=== basic probe (httpbin.org) ==="

# Test against a known public endpoint
r=$($PROBE --no-tls --timeout 15 https://httpbin.org/status/200 2>&1) || true
status=$(echo "$r" | jq -r '.status_code // empty' 2>/dev/null)

if [[ "$status" == "200" ]]; then
    pass "status code 200"

    # Check response time is a number
    resp_time=$(echo "$r" | jq '.response_time_ms // 0')
    [[ "$resp_time" -gt 0 ]] && pass "response_time_ms > 0 ($resp_time ms)" || fail "response_time_ms" "$resp_time" ">0"

    # Check url field
    url=$(echo "$r" | jq -r '.url')
    [[ "$url" == "https://httpbin.org/status/200" ]] && pass "url matches" || fail "url" "$url" "https://httpbin.org/status/200"

    # Check final_url
    final_url=$(echo "$r" | jq -r '.final_url // empty')
    [[ -n "$final_url" ]] && pass "final_url present" || fail "final_url" "empty" "present"

    # Check status_text
    status_text=$(echo "$r" | jq -r '.status_text // empty')
    [[ -n "$status_text" ]] && pass "status_text present ($status_text)" || fail "status_text" "empty" "present"

    # Check error is null
    error=$(echo "$r" | jq -r '.error // "null"')
    [[ "$error" == "null" ]] && pass "error is null" || fail "error" "$error" "null"
else
    echo "  ⚠️  httpbin.org unreachable — skipping live tests"
fi

echo ""

echo "=== 404 status ==="
r=$($PROBE --no-tls --timeout 15 https://httpbin.org/status/404 2>&1) || true
status=$(echo "$r" | jq -r '.status_code // empty' 2>/dev/null)
if [[ "$status" == "404" ]]; then
    pass "status code 404"
    status_text=$(echo "$r" | jq -r '.status_text')
    [[ "$status_text" == "Not Found" ]] && pass "404 status_text is 'Not Found'" || fail "404 status_text" "$status_text" "Not Found"
else
    echo "  ⚠️  httpbin.org unreachable — skipping"
fi

echo ""

echo "=== HEAD request ==="
r=$($PROBE --head --no-tls --timeout 15 https://httpbin.org/get 2>&1) || true
status=$(echo "$r" | jq -r '.status_code // empty' 2>/dev/null)
if [[ "$status" == "200" ]]; then
    pass "HEAD request returns 200"
else
    echo "  ⚠️  httpbin.org unreachable — skipping"
fi

echo ""

echo "=== redirect ==="
r=$($PROBE --no-tls --timeout 15 https://httpbin.org/redirect-to?url=https://httpbin.org/get 2>&1) || true
status=$(echo "$r" | jq -r '.status_code // empty' 2>/dev/null)
if [[ "$status" == "200" ]]; then
    pass "redirect follows to 200"
else
    echo "  ⚠️  httpbin.org unreachable — skipping"
fi

echo ""

echo "=== headers present ==="
r=$($PROBE --no-tls --timeout 15 https://httpbin.org/get 2>&1) || true
if echo "$r" | jq -e '.headers' > /dev/null 2>&1; then
    headers_count=$(echo "$r" | jq '.headers | length')
    [[ "$headers_count" -gt 0 ]] && pass "headers present ($headers_count)" || fail "headers count" "$headers_count" ">0"
else
    echo "  ⚠️  httpbin.org unreachable — skipping"
fi

echo ""

echo "=== TLS probe (google.com) ==="
r=$($PROBE --timeout 15 https://www.google.com 2>&1) || true
status=$(echo "$r" | jq -r '.status_code // empty' 2>/dev/null)
if [[ "$status" == "200" ]]; then
    tls=$(echo "$r" | jq '.tls // null')
    if [[ "$tls" != "null" ]]; then
        tls_protocol=$(echo "$r" | jq -r '.tls.protocol // empty')
        [[ -n "$tls_protocol" ]] && pass "TLS protocol detected ($tls_protocol)" || fail "TLS protocol" "empty" "present"

        tls_cert_valid=$(echo "$r" | jq -r '.tls.cert_valid // false')
        [[ "$tls_cert_valid" == "true" ]] && pass "TLS cert valid" || fail "TLS cert valid" "$tls_cert_valid" "true"

        tls_ssl_verify=$(echo "$r" | jq -r '.tls.ssl_verify // false')
        [[ "$tls_ssl_verify" == "true" ]] && pass "TLS SSL verify ok" || fail "TLS SSL verify" "$tls_ssl_verify" "true"
    else
        echo "  ⚠️  TLS info not available (openssl may not be installed)"
    fi
else
    echo "  ⚠️  google.com unreachable — skipping TLS tests"
fi

echo ""

echo "=== custom header ==="
r=$($PROBE --no-tls --timeout 15 --header "X-Test: hello" https://httpbin.org/headers 2>&1) || true
status=$(echo "$r" | jq -r '.status_code // empty' 2>/dev/null)
if [[ "$status" == "200" ]]; then
    pass "custom header request returns 200"
else
    echo "  ⚠️  httpbin.org unreachable — skipping"
fi

echo ""

echo "=== unreachable host ==="
r=$($PROBE --no-tls --timeout 3 http://192.0.2.1:9999/ 2>&1) || true
status=$(echo "$r" | jq -r '.status_code // 0' 2>/dev/null)
# Should fail with 000 or have an error
error=$(echo "$r" | jq -r '.error // "null"' 2>/dev/null)
if [[ "$status" == "000" || "$error" != "null" ]]; then
    pass "unreachable host handled gracefully"
else
    fail "unreachable host" "status=$status error=$error" "000 or error"
fi

echo ""

echo "=== SSRF protection ==="
# Block localhost by default
r=$($PROBE --no-tls --timeout 3 http://127.0.0.1:8080/ 2>&1) || true
error=$(echo "$r" | jq -r '.error // empty' 2>/dev/null)
[[ "$error" == *"SSRF"* ]] && pass "localhost blocked by SSRF check" || fail "SSRF localhost" "$error" "contains SSRF"

# Block 169.254.169.254 (cloud metadata)
r=$($PROBE --no-tls --timeout 3 http://169.254.169.254/latest/meta-data/ 2>&1) || true
error=$(echo "$r" | jq -r '.error // empty' 2>/dev/null)
[[ "$error" == *"SSRF"* ]] && pass "cloud metadata endpoint blocked" || fail "SSRF metadata" "$error" "contains SSRF"

# Block 10.x.x.x private range
r=$($PROBE --no-tls --timeout 3 http://10.0.0.1:8080/ 2>&1) || true
error=$(echo "$r" | jq -r '.error // empty' 2>/dev/null)
[[ "$error" == *"SSRF"* ]] && pass "10.x private range blocked" || fail "SSRF 10.x" "$error" "contains SSRF"

# Block 192.168.x.x private range
r=$($PROBE --no-tls --timeout 3 http://192.168.1.1:8080/ 2>&1) || true
error=$(echo "$r" | jq -r '.error // empty' 2>/dev/null)
[[ "$error" == *"SSRF"* ]] && pass "192.168.x private range blocked" || fail "SSRF 192.168" "$error" "contains SSRF"

# --allow-private bypasses the check (still fails to connect, but not blocked)
r=$($PROBE --no-tls --allow-private --timeout 3 http://127.0.0.1:9999/ 2>&1) || true
error=$(echo "$r" | jq -r '.error // empty' 2>/dev/null)
[[ "$error" != *"SSRF"* ]] && pass "--allow-private bypasses SSRF check" || fail "--allow-private" "$error" "no SSRF"

echo ""

echo "=== error handling ==="
$PROBE 2>/dev/null && fail "no args should show usage" "success" "error" || pass "no args shows usage"

$PROBE --unknown-option http://example.com 2>/dev/null && fail "unknown option should fail" "success" "error" || pass "unknown option rejected"

echo ""

# --- summary ---
echo "=============================="
echo "Results: $PASS passed, $FAIL failed"
echo "=============================="

if (( FAIL > 0 )); then
    exit 1
fi

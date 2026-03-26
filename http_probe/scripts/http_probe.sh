#!/usr/bin/env bash
# http_probe — Structured HTTP endpoint probing for agents
# Usage: http_probe.sh [options] <url>
# Returns JSON with status, timing, TLS, redirects, headers.

set -euo pipefail

URL=""
TIMEOUT=10
FOLLOW_REDIRECTS=true
MAX_REDIRECTS=10
CHECK_TLS=true
HEADERS_ONLY=false
CUSTOM_HEADERS=()
METHOD="GET"
ALLOW_PRIVATE=false

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --timeout)      TIMEOUT="$2"; shift 2 ;;
        --no-redirect)  FOLLOW_REDIRECTS=false; shift ;;
        --max-redirects) MAX_REDIRECTS="$2"; shift 2 ;;
        --no-tls)       CHECK_TLS=false; shift ;;
        --head)         HEADERS_ONLY=true; shift ;;
        --method)       METHOD="$2"; shift 2 ;;
        --header)       CUSTOM_HEADERS+=("$2"); shift 2 ;;
        --allow-private) ALLOW_PRIVATE=true; shift ;;
        -*)             echo '{"error":"unknown option '"$1"'"}' >&2; exit 1 ;;
        *)              URL="$1"; shift ;;
    esac
done

if [[ -z "$URL" ]]; then
    cat >&2 <<'EOF'
http_probe — Structured HTTP endpoint probing

Usage: http_probe.sh [options] <url>

Options:
  --timeout <sec>       Connection timeout (default: 10)
  --no-redirect         Don't follow redirects
  --max-redirects <n>   Max redirects to follow (default: 10)
  --no-tls              Skip TLS certificate inspection
  --head                HEAD request only (faster)
  --method <method>     HTTP method (default: GET)
  --header <header>     Custom header (repeatable)
  --allow-private       Allow probing private/loopback IPs (SSRF bypass)

Output JSON:
  {
    "url": "...",
    "status_code": 200,
    "status_text": "OK",
    "response_time_ms": 123,
    "headers": {"Content-Type": "text/html", ...},
    "redirect_chain": [{"url":"...","status":301}, ...],
    "tls": {"protocol":"TLSv1.3","cipher":"...","cert_subject":"...","cert_issuer":"...","cert_expiry":"...","cert_valid":true},
    "final_url": "...",
    "error": null
  }

Examples:
  http_probe.sh https://example.com
  http_probe.sh --timeout 5 --head https://api.example.com/health
  http_probe.sh --header "Authorization: Bearer token" https://api.example.com
EOF
    exit 1
fi

# SSRF protection: block private/loopback IPs unless --allow-private
check_ssrf() {
    local url="$1"
    # Extract hostname from URL
    local host
    host=$(echo "$url" | sed -E 's|^[a-z]+://([^/:]+).*|\1|' | sed 's/\[//;s/\]//')

    # Resolve hostname to IP if needed
    local ip="$host"
    if ! echo "$host" | grep -qP '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$'; then
        ip=$(getent hosts "$host" 2>/dev/null | awk '{print $1}' | head -1 || echo "")
        if [[ -z "$ip" ]]; then
            # Can't resolve — let curl handle it (it will fail gracefully)
            return 0
        fi
    fi

    # Check private/loopback/link-local ranges
    if [[ "$ip" =~ ^127\. ]]; then
        return 1  # Loopback
    elif [[ "$ip" =~ ^10\. ]]; then
        return 1  # Private 10.0.0.0/8
    elif [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]]; then
        return 1  # Private 172.16.0.0/12
    elif [[ "$ip" =~ ^192\.168\. ]]; then
        return 1  # Private 192.168.0.0/16
    elif [[ "$ip" =~ ^169\.254\. ]]; then
        return 1  # Link-local / cloud metadata
    elif [[ "$ip" == "::1" ]]; then
        return 1  # IPv6 loopback
    elif [[ "$ip" =~ ^fc|^fd ]]; then
        return 1  # IPv6 unique local
    fi

    return 0
}

if [[ "$ALLOW_PRIVATE" != "true" ]]; then
    if ! check_ssrf "$URL"; then
        echo '{"error":"SSRF blocked: private/loopback IP not allowed (use --allow-private to override)","url":"'"$URL"'"}' >&2
        exit 1
    fi
fi

# Build curl args
CURL_ARGS=(
    -s
    -o /dev/null
    -w '%{http_code}|%{time_total}|%{url_effective}|%{num_redirects}|%{ssl_verify_result}|%{redirect_url}'
    --max-time "$TIMEOUT"
)

if [[ "$FOLLOW_REDIRECTS" == "true" ]]; then
    CURL_ARGS+=(-L --max-redirs "$MAX_REDIRECTS")
fi

if [[ "$HEADERS_ONLY" == "true" ]]; then
    CURL_ARGS+=(-I)
fi

if [[ "$METHOD" != "GET" && "$HEADERS_ONLY" != "true" ]]; then
    CURL_ARGS+=(-X "$METHOD")
fi

for h in "${CUSTOM_HEADERS[@]+"${CUSTOM_HEADERS[@]}"}"; do
    CURL_ARGS+=(-H "$h")
done

# Capture headers separately (curl -D dumps response headers)
HEADER_FILE=$(mktemp)
CURL_ARGS+=(-D "$HEADER_FILE")

# Run curl
CURL_START=$(date +%s%N)
CURL_OUTPUT=$(curl "${CURL_ARGS[@]}" "$URL" 2>&1) || true
CURL_END=$(date +%s%N)
CURL_EXIT=$?

# Parse curl output
IFS='|' read -r STATUS_CODE TIME_TOTAL FINAL_URL NUM_REDIRECTS SSL_VERIFY REDIRECT_URL <<< "$CURL_OUTPUT"

# Calculate response time in ms
RESPONSE_MS=$(echo "$TIME_TOTAL" | awk '{printf "%.0f", $1 * 1000}')

# Parse response headers
HEADERS_JSON="{"
first_header=true
if [[ -f "$HEADER_FILE" ]]; then
    while IFS= read -r line; do
        # Skip status line and empty lines
        if [[ "$line" =~ ^HTTP ]]; then
            continue
        fi
        if [[ -z "$line" ]]; then
            continue
        fi
        # Parse header: Key: Value
        if [[ "$line" =~ ^([^:]+):\ (.*)$ ]]; then
            local_key="${BASH_REMATCH[1]}"
            local_val="${BASH_REMATCH[2]}"
            # Escape for JSON
            local_key="${local_key//\\/\\\\}"
            local_key="${local_key//\"/\\\"}"
            local_val="${local_val//\\/\\\\}"
            local_val="${local_val//\"/\\\"}"
            local_val="${local_val//$'\r'/}"
            if [[ "$first_header" == "true" ]]; then
                first_header=false
            else
                HEADERS_JSON+=","
            fi
            HEADERS_JSON+="\"$local_key\":\"$local_val\""
        fi
    done < "$HEADER_FILE"
fi
HEADERS_JSON+="}"
rm -f "$HEADER_FILE"

# Get status text
STATUS_TEXT=""
case "$STATUS_CODE" in
    200) STATUS_TEXT="OK" ;;
    201) STATUS_TEXT="Created" ;;
    204) STATUS_TEXT="No Content" ;;
    301) STATUS_TEXT="Moved Permanently" ;;
    302) STATUS_TEXT="Found" ;;
    304) STATUS_TEXT="Not Modified" ;;
    400) STATUS_TEXT="Bad Request" ;;
    401) STATUS_TEXT="Unauthorized" ;;
    403) STATUS_TEXT="Forbidden" ;;
    404) STATUS_TEXT="Not Found" ;;
    405) STATUS_TEXT="Method Not Allowed" ;;
    408) STATUS_TEXT="Request Timeout" ;;
    429) STATUS_TEXT="Too Many Requests" ;;
    500) STATUS_TEXT="Internal Server Error" ;;
    502) STATUS_TEXT="Bad Gateway" ;;
    503) STATUS_TEXT="Service Unavailable" ;;
    504) STATUS_TEXT="Gateway Timeout" ;;
    000) STATUS_TEXT="Connection Failed" ;;
    *)   STATUS_TEXT="HTTP $STATUS_CODE" ;;
esac

# Build redirect chain (parse from headers when following redirects)
# curl -L with -D writes headers for each redirect step
# We'll get the chain from the header file content if there were redirects
REDIRECT_CHAIN="["
if [[ "$NUM_REDIRECTS" -gt 0 && -n "$REDIRECT_URL" ]]; then
    REDIRECT_CHAIN+=$(printf '{"url":"%s","status":%s}' "$URL" "${STATUS_CODE:-0}")
fi
REDIRECT_CHAIN+="]"

# TLS info
TLS_JSON="null"
if [[ "$CHECK_TLS" == "true" && "$URL" == https://* ]]; then
    # Extract hostname from URL
    HOST=$(echo "$URL" | sed -E 's|https://([^/:]+).*|\1|')

    # Get TLS info
    TLS_OUTPUT=$(echo | timeout 5 openssl s_client -connect "$HOST:443" -servername "$HOST" 2>/dev/null) || true

    # Try multiple formats: "Protocol : TLSv1.3" or "New, TLSv1.3, Cipher is ..."
    TLS_PROTOCOL=$(echo "$TLS_OUTPUT" | grep -oP 'Protocol\s*:\s*\K\S+' | head -1 || true)
    if [[ -z "$TLS_PROTOCOL" ]]; then
        TLS_PROTOCOL=$(echo "$TLS_OUTPUT" | grep -oP 'New,\s*\K(TLSv\S+|SSLv\S+)' | head -1 || true)
        TLS_PROTOCOL="${TLS_PROTOCOL%,}"  # Remove trailing comma
    fi
    TLS_CIPHER=$(echo "$TLS_OUTPUT" | grep -oP 'Cipher\s*:\s*\K\S+' | head -1 || true)
    if [[ -z "$TLS_CIPHER" ]]; then
        TLS_CIPHER=$(echo "$TLS_OUTPUT" | grep -oP 'Cipher is\s*\K\S+' | head -1 || true)
    fi

    # Get cert details
    CERT_OUTPUT=$(echo | timeout 5 openssl s_client -connect "$HOST:443" -servername "$HOST" 2>/dev/null | openssl x509 -noout -subject -issuer -dates 2>/dev/null) || true

    CERT_SUBJECT=$(echo "$CERT_OUTPUT" | grep "^subject=" | sed 's/^subject=//' | xargs || echo "")
    CERT_ISSUER=$(echo "$CERT_OUTPUT" | grep "^issuer=" | sed 's/^issuer=//' | xargs || echo "")
    CERT_NOT_AFTER=$(echo "$CERT_OUTPUT" | grep "notAfter=" | sed 's/^notAfter=//' | xargs || echo "")

    # Check if cert is still valid
    CERT_VALID="true"
    if [[ -n "$CERT_NOT_AFTER" ]]; then
        if ! date -d "$CERT_NOT_AFTER" +%s &>/dev/null; then
            CERT_VALID="unknown"
        else
            CERT_EPOCH=$(date -d "$CERT_NOT_AFTER" +%s 2>/dev/null || echo 0)
            NOW_EPOCH=$(date +%s)
            if [[ "$CERT_EPOCH" -lt "$NOW_EPOCH" ]]; then
                CERT_VALID="false"
            fi
        fi
    fi

    # SSL verify result from curl: 0 = ok, other = error
    TLS_VERIFY="true"
    if [[ "$SSL_VERIFY" != "0" ]]; then
        TLS_VERIFY="false"
    fi

    # Escape for JSON
    TLS_PROTOCOL="${TLS_PROTOCOL//\\/\\\\}"
    TLS_CIPHER="${TLS_CIPHER//\\/\\\\}"
    CERT_SUBJECT="${CERT_SUBJECT//\\/\\\\}"
    CERT_SUBJECT="${CERT_SUBJECT//\"/\\\"}"
    CERT_ISSUER="${CERT_ISSUER//\\/\\\\}"
    CERT_ISSUER="${CERT_ISSUER//\"/\\\"}"
    CERT_NOT_AFTER="${CERT_NOT_AFTER//\\/\\\\}"

    TLS_JSON=$(printf '{"protocol":"%s","cipher":"%s","cert_subject":"%s","cert_issuer":"%s","cert_expiry":"%s","cert_valid":%s,"ssl_verify":%s}' \
        "$TLS_PROTOCOL" "$TLS_CIPHER" "$CERT_SUBJECT" "$CERT_ISSUER" "$CERT_NOT_AFTER" "$CERT_VALID" "$TLS_VERIFY")
fi

# Build final output
ERROR="null"
if [[ "$CURL_EXIT" -ne 0 ]]; then
    ERROR="\"curl failed with exit code $CURL_EXIT\""
fi
if [[ "$STATUS_CODE" == "000" ]]; then
    ERROR="\"connection failed\""
fi

printf '{"url":"%s","status_code":%s,"status_text":"%s","response_time_ms":%s,"headers":%s,"redirect_chain":%s,"tls":%s,"final_url":"%s","error":%s}\n' \
    "$URL" "${STATUS_CODE:-0}" "$STATUS_TEXT" "${RESPONSE_MS:-0}" "$HEADERS_JSON" "$REDIRECT_CHAIN" "$TLS_JSON" "${FINAL_URL:-$URL}" "$ERROR" | jq .

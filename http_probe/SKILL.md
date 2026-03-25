---
name: http_probe
description: "Structured HTTP endpoint probing for agents. Returns JSON with status code, response time, headers, TLS cert info, redirect chain. Use when: (1) checking if an endpoint is alive, (2) inspecting response headers, (3) verifying TLS certificates, (4) measuring response times, (5) debugging redirect chains. NOT for: API testing with assertions (use curl/httpie directly), scraping (use web_fetch), load testing (use ab/wrk)."
metadata:
  {
    "openclaw":
      {
        "emoji": "🔍",
        "requires": { "bins": ["bash", "curl", "jq"] },
      },
  }
---

# http_probe

Structured HTTP endpoint probing for agents. Returns JSON for every request.

## When to Use

✅ **USE this skill when:**
- Checking if an endpoint is alive and responding
- Inspecting response headers and status codes
- Verifying TLS certificates (expiry, issuer, protocol)
- Measuring response times
- Debugging redirect chains
- Health-checking endpoints programmatically

## When NOT to Use

❌ **DON'T use this skill when:**
- Making authenticated API calls with complex payloads (use `curl` directly)
- Web scraping (use `web_fetch`)
- Load testing (use `ab`, `wrk`, `k6`)

## Usage

### Basic probe
```bash
./scripts/http_probe.sh https://example.com
```

### HEAD request (faster, no body download)
```bash
./scripts/http_probe.sh --head https://example.com
```

### Custom timeout and headers
```bash
./scripts/http_probe.sh --timeout 5 --header "Authorization: Bearer token" https://api.example.com
```

### Skip TLS inspection
```bash
./scripts/http_probe.sh --no-tls https://internal-service.local
```

### POST request
```bash
./scripts/http_probe.sh --method POST --header "Content-Type: application/json" https://api.example.com
```

## Output Format

```json
{
  "url": "https://example.com",
  "status_code": 200,
  "status_text": "OK",
  "response_time_ms": 123,
  "headers": {
    "Content-Type": "text/html; charset=UTF-8",
    "Server": "ECS",
    ...
  },
  "redirect_chain": [
    {"url": "http://example.com", "status": 301}
  ],
  "tls": {
    "protocol": "TLSv1.3",
    "cipher": "TLS_AES_256_GCM_SHA384",
    "cert_subject": "CN=example.com",
    "cert_issuer": "CN=R3, O=Let's Encrypt",
    "cert_expiry": "Dec 31 23:59:59 2026 GMT",
    "cert_valid": true,
    "ssl_verify": true
  },
  "final_url": "https://example.com/",
  "error": null
}
```

## Options

| Option | Default | Description |
|--------|---------|-------------|
| `--timeout <sec>` | 10 | Connection timeout in seconds |
| `--no-redirect` | false | Don't follow redirects |
| `--max-redirects <n>` | 10 | Maximum redirects to follow |
| `--no-tls` | false | Skip TLS certificate inspection |
| `--head` | false | Use HEAD method (faster) |
| `--method <method>` | GET | HTTP method |
| `--header <header>` | (none) | Custom header (repeatable) |

## Requirements

- bash 4+
- curl
- jq
- openssl (for TLS inspection)

---
name: json_schema_validator
description: "Validate JSON against JSON Schema and infer schemas from data. Returns structured JSON with error details. Use when: (1) validating API responses, (2) checking config files, (3) inferring schemas from samples, (4) verifying data structures. NOT for: JSON formatting (use jq), JSON-to-CSV conversion (use existing skills), schema documentation generation."
metadata:
  {
    "openclaw":
      {
        "emoji": "✅",
        "requires": { "bins": ["bash", "jq"] },
      },
  }
---

# json_schema_validator

Validate JSON against JSON Schema and infer schemas from data samples.

## When to Use

✅ **USE this skill when:**
- Validating JSON data against a schema
- Checking API responses or config files
- Inferring a JSON Schema from a sample
- Verifying data structure correctness

## When NOT to Use

❌ **DON'T use this skill when:**
- Pretty-printing JSON (use `jq`)
- Converting JSON formats (use existing conversion skills)
- Generating schema documentation

## Commands

### validate
Validate JSON data against a JSON Schema.
```bash
./scripts/schema.sh validate schema.json data.json
echo '{"name":"test"}' | ./scripts/schema.sh validate schema.json -
```

Output (valid):
```json
{"valid":true,"errors":[],"error_count":0,"schema":"my-schema"}
```

Output (invalid):
```json
{"valid":false,"errors":[{"path":"name","message":"required property name is missing"}],"error_count":1,"schema":"my-schema"}
```

### infer
Infer a JSON Schema from a sample data file.
```bash
./scripts/schema.sh infer sample.json
echo '{"x":1,"y":"hello"}' | ./scripts/schema.sh infer -
```

Output:
```json
{"type":"object","properties":{"x":{"type":"number"},"y":{"type":"string"}},"required":["x","y"]}
```

## Supported Schema Features

| Feature | Example |
|---------|---------|
| `type` | `{"type":"string"}`, `{"type":["string","null"]}` |
| `properties` | `{"properties":{"name":{"type":"string"}}}` |
| `required` | `{"required":["name","age"]}` |
| `additionalProperties` | `{"additionalProperties":false}` |
| `enum` | `{"enum":["red","green","blue"]}` |
| `const` | `{"const":42}` |
| `minimum`/`maximum` | `{"type":"number","minimum":0,"maximum":100}` |
| `minLength`/`maxLength` | `{"type":"string","minLength":1,"maxLength":255}` |
| `minItems`/`maxItems` | `{"type":"array","minItems":1,"maxItems":10}` |
| `minProperties`/`maxProperties` | `{"type":"object","minProperties":1}` |
| `pattern` | `{"type":"string","pattern":"^[a-z]+$"}` |
| `format` | `{"type":"string","format":"email"}` (email, uri, date, date-time, ipv4) |
| `items` | `{"type":"array","items":{"type":"string"}}` |

## Requirements

- bash 4+
- jq
- grep with PCRE support (for pattern validation)

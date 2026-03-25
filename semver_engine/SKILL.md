---
name: semver_engine
description: "Deterministic semver parse/compare/bump/validate/constraint-check tool. Returns structured JSON. Use when: (1) parsing or validating semver strings, (2) comparing versions, (3) bumping versions, (4) checking version constraints (^, ~, >=, <=, etc). NOT for: npm/yarn/cargo version management (use ecosystem CLIs), changelog generation (use changelog skills)."
metadata:
  {
    "openclaw":
      {
        "emoji": "🔢",
        "requires": { "bins": ["bash", "jq"] },
      },
  }
---

# semver_engine

Deterministic semver operations for agents. Returns structured JSON for every command.

## When to Use

✅ **USE this skill when:**
- Parsing semver strings into structured components
- Comparing two versions (deterministic -1/0/1 result)
- Bumping versions (major, minor, patch, prerelease)
- Validating semver format
- Checking if a version satisfies constraints (>=, <=, ^, ~, ==, !=)

## When NOT to Use

❌ **DON'T use this skill when:**
- Managing package.json/Cargo.toml versions directly (use npm/cargo)
- Generating changelogs (use changelog skills)
- Git tag operations (use git directly)

## Commands

### parse
Parse a semver string into structured JSON.
```bash
./scripts/semver.sh parse 1.2.3-beta.1+build.42
# {"major":1,"minor":2,"patch":3,"prerelease":"beta.1","build":"build.42"}
```

### validate
Validate a semver string.
```bash
./scripts/semver.sh validate 1.2.3
# {"valid":true,"input":"1.2.3"}

./scripts/semver.sh validate "not.a.version"
# {"valid":false,"input":"not.a.version"}
```

### compare
Compare two versions. Returns -1 (a < b), 0 (equal), 1 (a > b). Respects prerelease precedence.
```bash
./scripts/semver.sh compare 1.2.3 2.0.0
# {"a":"1.2.3","b":"2.0.0","result":-1}

./scripts/semver.sh compare 1.2.3-alpha 1.2.3
# {"a":"1.2.3-alpha","b":"1.2.3","result":-1}
```

### bump
Bump a version. Types: major, minor, patch, premajor, preminor, prepatch, prerelease.
```bash
./scripts/semver.sh bump minor 1.2.3
# {"input":"1.2.3","bump":"minor","result":"1.3.0"}

./scripts/semver.sh bump prerelease 1.2.3-beta.0
# {"input":"1.2.3-beta.0","bump":"prerelease","result":"1.2.3-beta.1"}
```

### satisfies
Check if a version satisfies a constraint.
```bash
./scripts/semver.sh satisfies 1.5.0 "^1.0.0"
# {"satisfies":true,"version":"1.5.0","constraint":"^1.0.0"}

./scripts/semver.sh satisfies 1.5.0 "~1.4.0"
# {"satisfies":false,"version":"1.5.0","constraint":"~1.4.0"}
```

### satisfies-all
Check version against multiple space-separated constraints (AND logic).
```bash
./scripts/semver.sh satisfies-all 1.5.0 ">=1.0.0" "<2.0.0"
# {"satisfies":true,"version":"1.5.0","constraints":">=1.0.0 <2.0.0"}
```

## Constraint Operators

| Operator | Meaning |
|----------|---------|
| `==` | Exact match |
| `!=` | Not equal |
| `>` | Greater than |
| `<` | Less than |
| `>=` | Greater or equal |
| `<=` | Less or equal |
| `^` | Caret: compatible with (>=v, <next major, or <next minor if major=0, or <next patch if major=minor=0) |
| `~` | Tilde: approximately (>=v, <next minor) |
| bare | A bare version like `1.2.3` is treated as `>=1.2.3` |

## Requirements

- bash 4+
- jq (for JSON construction)

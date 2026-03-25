---
name: project_manifest_reader
description: "Cross-ecosystem project manifest reader. Auto-detects Node, Rust, Python, Go, Java, Ruby ecosystems and returns normalized metadata as JSON. Use when: (1) exploring unfamiliar project structures, (2) getting project name/version/description, (3) listing dependencies, (4) finding build scripts, (5) detecting project ecosystem. NOT for: editing manifests (use ecosystem tools), installing dependencies (use npm/cargo/pip)."
metadata:
  {
    "openclaw":
      {
        "emoji": "📦",
        "requires": { "bins": ["bash", "jq"] },
      },
  }
---

# project_manifest_reader

Cross-ecosystem project manifest reader. Auto-detects ecosystem and returns normalized JSON.

## When to Use

✅ **USE this skill when:**
- Exploring an unfamiliar project's structure
- Getting project name, version, description
- Listing dependencies and their counts
- Finding build scripts and entry points
- Detecting what ecosystem a project uses

## When NOT to Use

❌ **DON'T use this skill when:**
- Editing package manifests (use npm/cargo/pip/etc.)
- Installing dependencies
- Resolving dependency conflicts

## Supported Ecosystems

| Ecosystem | Manifest Files |
|-----------|---------------|
| **Node.js** | `package.json` |
| **Rust** | `Cargo.toml` |
| **Python** | `pyproject.toml`, `setup.py`, `setup.cfg`, `Pipfile`, `requirements.txt` |
| **Go** | `go.mod` |
| **Java** | `build.gradle`, `build.gradle.kts`, `pom.xml` |
| **Ruby** | `Gemfile` |

## Usage

### Read project manifest
```bash
./scripts/manifest.sh /path/to/project
```

### Detect ecosystem only
```bash
./scripts/manifest.sh /path/to/project --detect
```

### Filter specific fields
```bash
./scripts/manifest.sh /path/to/project --fields name,version,dependencies
```

## Output Format (Node.js example)

```json
{
  "ecosystem": "node",
  "name": "my-app",
  "version": "1.2.3",
  "description": "A great application",
  "language": "javascript",
  "entry": "index.js",
  "license": "MIT",
  "author": "Daniel",
  "private": false,
  "module_type": "commonjs",
  "scripts": {
    "start": "node index.js",
    "test": "jest"
  },
  "dependencies": [
    {"name": "express", "version": "^4.18.0"}
  ],
  "devDependencies": [
    {"name": "jest", "version": "^29.0.0"}
  ],
  "dependency_count": 1,
  "devDependency_count": 1,
  "project_root": "/path/to/project",
  "detected_ecosystems": ["node", "docker"]
}
```

## Requirements

- bash 4+
- jq

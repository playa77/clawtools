---
name: diff_analyzer
description: "Structured diff analysis for agents. Returns JSON with files changed, additions/deletions per file, hunk details with context, binary detection, rename tracking. Use when: (1) analyzing git diffs programmatically, (2) summarizing code changes, (3) detecting binary files or renames, (4) feeding structured diff data into other workflows. NOT for: applying patches (use git apply), visual diff display (use git diff directly)."
metadata:
  {
    "openclaw":
      {
        "emoji": "📊",
        "requires": { "bins": ["bash", "jq", "git"] },
      },
  }
---

# diff_analyzer

Structured diff analysis for agents. Returns JSON with file-level and hunk-level detail.

## When to Use

✅ **USE this skill when:**
- Analyzing git diffs programmatically
- Summarizing what changed between commits/branches
- Detecting binary files, renames, additions, deletions
- Feeding structured diff metadata into other workflows
- Code review preprocessing

## When NOT to Use

❌ **DON'T use this skill when:**
- Applying patches (use `git apply`)
- Visual diff display (use `git diff` directly)
- Resolving merge conflicts (use `git mergetool`)

## Usage

### From git diff (between refs)
```bash
./scripts/diff_analyze.sh --from main --to feature --repo /path/to/repo --summarize
```

### Staged changes
```bash
./scripts/diff_analyze.sh --staged --repo /path/to/repo
```

### Single file
```bash
./scripts/diff_analyze.sh --from HEAD~1 --file src/main.py
```

### From stdin
```bash
git diff | ./scripts/diff_analyze.sh --summarize
```

### From file
```bash
./scripts/diff_analyze.sh changes.diff --summarize
```

## Output Format

```json
{
  "files": [
    {
      "path": "src/main.py",
      "type": "modified",
      "binary": false,
      "additions": 15,
      "deletions": 3,
      "hunks": [
        {
          "old_start": 10,
          "old_count": 5,
          "new_start": 10,
          "new_count": 17,
          "context": "def process_data():",
          "lines": [
            {"type": "context", "content": "    existing code"},
            {"type": "addition", "content": "+   new code"},
            {"type": "deletion", "content": "-   old code"}
          ]
        }
      ]
    }
  ],
  "summary": {                    // only with --summarize
    "files_changed": 3,
    "total_additions": 42,
    "total_deletions": 10,
    "total_lines": 52
  }
}
```

### File types

| Type | Meaning |
|------|---------|
| `modified` | Existing file changed |
| `added` | New file |
| `deleted` | File removed |
| `renamed` | File renamed (includes `renamed_from` field) |

### Line types

| Type | Meaning |
|------|---------|
| `context` | Unchanged line |
| `addition` | Added line (starts with +) |
| `deletion` | Removed line (starts with -) |

## Requirements

- bash 4+
- jq
- git (for git-mode operations)

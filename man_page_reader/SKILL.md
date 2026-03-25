---
name: man_page_reader
description: "Parse man pages into structured, agent-friendly JSON summaries. Extracts name, synopsis, description, options/flags, and all sections. Use when: (1) looking up command usage, (2) understanding CLI options, (3) extracting specific man page sections, (4) getting condensed command references. NOT for: full man page dumps (use `man` directly), online documentation lookup (use web_fetch)."
metadata:
  {
    "openclaw":
      {
        "emoji": "📖",
        "requires": { "bins": ["bash", "man", "jq"] },
      },
  }
---

# man_page_reader

Parse man pages into structured JSON for agents. No more dumping entire man pages into context.

## When to Use

✅ **USE this skill when:**
- Looking up command syntax or options
- Understanding what a CLI tool does
- Extracting specific sections from man pages
- Getting condensed command references for agent context

## When NOT to Use

❌ **DON'T use this skill when:**
- You need the full raw man page (use `man` directly)
- Looking for online documentation (use `web_fetch`)
- The command has no man page (check `--help` instead)

## Usage

### Parse a command's man page
```bash
./scripts/man_page.sh ls
./scripts/man_page.sh git
./scripts/man_page.sh ssh
```

### Parse a specific section
```bash
./scripts/man_page.sh 5 passwd     # Section 5: file formats
./scripts/man_page.sh 7 signal     # Section 7: overview
```

### Parse from file
```bash
./scripts/man_page.sh --file /usr/share/man/man1/ls.1.gz
```

## Output Format

```json
{
  "name": "ls",
  "section": "1",
  "synopsis": "ls [OPTION]... [FILE]...",
  "description": "List information about the FILEs (the current directory by default)...",
  "options": [
    {"flag": "-a", "description": "do not ignore entries starting with ."},
    {"flag": "-l", "description": "use a long listing format"}
  ],
  "sections": {
    "NAME": "ls - list directory contents",
    "SYNOPSIS": "ls [OPTION]... [FILE]...",
    "DESCRIPTION": "...",
    "OPTIONS": "..."
  },
  "see_also": ["dir(1)", "vdir(1)", "dircolors(1)"]
}
```

### Key fields

| Field | Description |
|-------|-------------|
| `name` | Command name |
| `section` | Man section number (1-9) |
| `synopsis` | Usage syntax |
| `description` | Truncated description (max 500 chars) |
| `options` | Parsed flags with descriptions |
| `sections` | All named sections with truncated content |
| `see_also` | Related commands |

## Requirements

- bash 4+
- man command installed
- jq

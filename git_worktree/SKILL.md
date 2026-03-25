---
name: git_worktree
description: "Git worktree management for agents. List, add, remove, prune, lock, unlock worktrees with structured JSON output. Use when: (1) working on multiple branches simultaneously, (2) running parallel builds/tests on different branches, (3) exploring a repo without disturbing the main working tree. NOT for: basic git operations (use git directly), branch management (use git branch/checkout)."
metadata:
  {
    "openclaw":
      {
        "emoji": "🌲",
        "requires": { "bins": ["git", "jq"] },
      },
  }
---

# git_worktree

Git worktree management for agents. Structured JSON output for every command.

## When to Use

✅ **USE this skill when:**
- Working on multiple branches simultaneously
- Running parallel builds or tests on different branches
- Need an isolated working tree for a specific task
- Cleaning up stale worktrees after crashes

## When NOT to Use

❌ **DON'T use this skill when:**
- Simple branch switching (use `git checkout` / `git switch`)
- You only need one working tree at a time
- Basic git operations (commit, push, pull)

## Commands

### list
List all worktrees as a JSON array.
```bash
./scripts/worktree.sh list
# [{"path":"/repo","branch":"refs/heads/main","head":"abc123","locked":false,"prunable":false},...]
```

### add
Create a new worktree. Optionally on a new branch from a base branch.
```bash
# Create worktree on existing branch
./scripts/worktree.sh add /tmp/feature feature-branch

# Create worktree with new branch
./scripts/worktree.sh add /tmp/feature feature-branch main

# Create worktree detached (no branch)
./scripts/worktree.sh add /tmp/hotfix "" main
```

### remove
Remove a worktree. Use `--force` for dirty worktrees.
```bash
./scripts/worktree.sh remove /tmp/feature
./scripts/worktree.sh remove /tmp/feature --force
```

### prune
Remove stale worktree references (crashed/unreachable worktrees).
```bash
./scripts/worktree.sh prune           # Actually prune
./scripts/worktree.sh prune --dry-run # Preview only
```

### lock / unlock
Lock a worktree to prevent accidental removal.
```bash
./scripts/worktree.sh lock /tmp/important
./scripts/worktree.sh unlock /tmp/important
```

### info
Get detailed info about a worktree (default: current directory).
```bash
./scripts/worktree.sh info /tmp/feature
# {"path":"/tmp/feature","is_worktree":true,"branch":"feature","head":"abc123","dirty_files":3,"locked":false}
```

## Requirements

- git 2.5+ (worktree support)
- jq (for JSON construction)

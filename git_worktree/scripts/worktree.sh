#!/usr/bin/env bash
# git_worktree — Git worktree management for agents
# Commands: list, add, remove, prune, lock, unlock, info
# Usage: worktree.sh <command> [args...]

set -euo pipefail

# JSON output helper
json_ok() { echo "$1"; }
json_err() { echo "$1" >&2; return 1; }

# Validate path is not dangerous (path traversal, sensitive dirs)
validate_path() {
    local path="$1"
    local action="${2:-use}"

    # Reject empty paths
    if [[ -z "$path" ]]; then
        json_err '{"error":"path is required"}'
        return 1
    fi

    # Reject paths starting with dash (argument injection)
    if [[ "$path" == -* ]]; then
        json_err '{"error":"invalid path (must not start with dash)","path":"'"$path"'"}'
        return 1
    fi

    # Resolve to absolute path
    local resolved
    if [[ -d "$path" ]]; then
        resolved=$(cd "$path" && pwd -P 2>/dev/null) || true
    else
        # For paths that don't exist yet, resolve parent
        local parent
        parent=$(dirname "$path")
        if [[ -d "$parent" ]]; then
            resolved=$(cd "$parent" && pwd -P 2>/dev/null)/$(basename "$path") || true
        else
            resolved="$path"
        fi
    fi

    # Block access to sensitive system directories
    local blocked_dirs=("/etc" "/sys" "/proc" "/dev" "/boot" "/usr" "/var/lib" "/lib" "/sbin" "/bin")
    for bd in "${blocked_dirs[@]}"; do
        if [[ "$resolved" == "$bd" || "$resolved" == "$bd/"* ]]; then
            json_err '{"error":"path '"$action"' not allowed: blocked system directory","path":"'"$path"'"}'
            return 1
        fi
    done

    # Block home directory dotfiles (.ssh, .gnupg, etc.)
    local home="$HOME"
    if [[ -n "$home" ]]; then
        local sensitive_dirs=(".ssh" ".gnupg" ".aws" ".config" ".kube")
        for sd in "${sensitive_dirs[@]}"; do
            if [[ "$resolved" == "$home/$sd" || "$resolved" == "$home/$sd/"* ]]; then
                json_err '{"error":"path '"$action"' not allowed: sensitive directory","path":"'"$path"'"}'
                return 1
            fi
        done
    fi

    return 0
}

# Ensure we're in a git repo with worktree support
ensure_git_repo() {
    if ! git rev-parse --git-dir &>/dev/null; then
        json_err '{"error":"not a git repository"}'
        return 1
    fi
}

# List all worktrees as JSON array
cmd_list() {
    ensure_git_repo

    local output
    output=$(git worktree list --porcelain 2>/dev/null) || {
        json_err '{"error":"failed to list worktrees"}'
        return 1
    }

    local result="["
    local first=true
    local path="" branch="" head="" locked="" prunable=""

    while IFS= read -r line; do
        if [[ "$line" == "worktree "* ]]; then
            # Start of new entry — flush previous if exists
            if [[ -n "$path" ]]; then
                if [[ "$first" == "true" ]]; then first=false; else result+=","; fi
                result+=$(printf '{"path":"%s","branch":"%s","head":"%s","locked":%s,"prunable":%s}' \
                    "$path" "$branch" "$head" "$locked" "$prunable")
            fi
            path="${line#worktree }"
            branch="" head="" locked="false" prunable="false"
        elif [[ "$line" == "HEAD "* ]]; then
            head="${line#HEAD }"
        elif [[ "$line" == "branch "* ]]; then
            branch="${line#branch }"
        elif [[ "$line" == "locked" ]]; then
            locked="true"
        elif [[ "$line" == "prunable" ]]; then
            prunable="true"
        fi
    done <<< "$output"

    # Flush last entry
    if [[ -n "$path" ]]; then
        if [[ "$first" == "true" ]]; then first=false; else result+=","; fi
        result+=$(printf '{"path":"%s","branch":"%s","head":"%s","locked":%s,"prunable":%s}' \
            "$path" "$branch" "$head" "$locked" "$prunable")
    fi

    result+="]"
    json_ok "$result"
}

# Add a worktree
cmd_add() {
    ensure_git_repo

    local path="${1:-}"
    local branch="${2:-}"
    local base_branch="${3:-HEAD}"

    if [[ -z "$path" ]]; then
        json_err '{"error":"path is required","usage":"worktree.sh add <path> [branch] [base-branch]"}'
        return 1
    fi

    validate_path "$path" "add" || return 1

    local args=()
    if [[ -n "$branch" ]]; then
        args+=("-b" "$branch")
    fi
    args+=("$path")
    if [[ "$base_branch" != "HEAD" && -n "$base_branch" ]]; then
        args+=("$base_branch")
    fi

    local output
    if output=$(git worktree add "${args[@]}" 2>&1); then
        # Get the actual branch and head of new worktree
        local actual_branch actual_head
        actual_branch=$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "$branch")
        actual_head=$(git -C "$path" rev-parse HEAD 2>/dev/null || echo "")

        json_ok "$(printf '{"action":"add","path":"%s","branch":"%s","head":"%s","success":true}' \
            "$path" "$actual_branch" "$actual_head")"
    else
        json_err "$(printf '{"action":"add","path":"%s","error":"%s","success":false}' \
            "$path" "$output")"
        return 1
    fi
}

# Remove a worktree
cmd_remove() {
    ensure_git_repo

    local path="${1:-}"
    local force="${2:-false}"

    if [[ -z "$path" ]]; then
        json_err '{"error":"path is required","usage":"worktree.sh remove <path> [--force]"}'
        return 1
    fi

    validate_path "$path" "remove" || return 1

    local args=("remove")
    if [[ "$force" == "--force" || "$force" == "-f" ]]; then
        args+=("--force")
    fi
    args+=("$path")

    local output
    if output=$(git worktree "${args[@]}" 2>&1); then
        json_ok "$(printf '{"action":"remove","path":"%s","success":true}' "$path")"
    else
        json_err "$(printf '{"action":"remove","path":"%s","error":"%s","success":false}' \
            "$path" "$output")"
        return 1
    fi
}

# Prune stale worktrees
cmd_prune() {
    ensure_git_repo

    local dry_run="${1:-false}"
    local args=("prune")

    if [[ "$dry_run" == "--dry-run" || "$dry_run" == "-n" ]]; then
        args+=("--dry-run")
    fi

    local output
    if output=$(git worktree "${args[@]}" 2>&1); then
        local pruned=0
        if [[ -n "$output" ]]; then
            pruned=$(echo "$output" | grep -c "Removing" || true)
        fi
        json_ok "$(printf '{"action":"prune","pruned":%d,"dry_run":%s,"output":"%s"}' \
            "$pruned" "$([[ "$dry_run" == "--dry-run" ]] && echo true || echo false)" "$output")"
    else
        json_err "$(printf '{"action":"prune","error":"%s","success":false}' "$output")"
        return 1
    fi
}

# Lock a worktree
cmd_lock() {
    ensure_git_repo

    local path="${1:-}"
    if [[ -z "$path" ]]; then
        json_err '{"error":"path is required","usage":"worktree.sh lock <path>"}'
        return 1
    fi

    validate_path "$path" "lock" || return 1

    local output
    if output=$(git worktree lock "$path" 2>&1); then
        json_ok "$(printf '{"action":"lock","path":"%s","success":true}' "$path")"
    else
        json_err "$(printf '{"action":"lock","path":"%s","error":"%s","success":false}' \
            "$path" "$output")"
        return 1
    fi
}

# Unlock a worktree
cmd_unlock() {
    ensure_git_repo

    local path="${1:-}"
    if [[ -z "$path" ]]; then
        json_err '{"error":"path is required","usage":"worktree.sh unlock <path>"}'
        return 1
    fi

    validate_path "$path" "unlock" || return 1

    local output
    if output=$(git worktree unlock "$path" 2>&1); then
        json_ok "$(printf '{"action":"unlock","path":"%s","success":true}' "$path")"
    else
        json_err "$(printf '{"action":"unlock","path":"%s","error":"%s","success":false}' \
            "$path" "$output")"
        return 1
    fi
}

# Get detailed info about a specific worktree
cmd_info() {
    ensure_git_repo

    local path="${1:-.}"
    # Resolve to absolute
    path=$(cd "$path" && pwd -P 2>/dev/null) || {
        json_err '{"error":"path not found","path":"'"$1"'"}'
        return 1
    }

    # Check it's a worktree
    local is_worktree=false
    local gitdir
    gitdir=$(git -C "$path" rev-parse --git-dir 2>/dev/null) || true
    if [[ "$gitdir" == *".git/worktrees/"* ]]; then
        is_worktree=true
    fi

    local branch head status
    branch=$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    head=$(git -C "$path" rev-parse HEAD 2>/dev/null || echo "unknown")
    status=$(git -C "$path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')

    local locked="false"
    if git worktree list --porcelain 2>/dev/null | grep -A5 "worktree $path" | grep -q "^locked$"; then
        locked="true"
    fi

    json_ok "$(printf '{"path":"%s","is_worktree":%s,"branch":"%s","head":"%s","dirty_files":%s,"locked":%s}' \
        "$path" "$is_worktree" "$branch" "$head" "$status" "$locked")"
}

# Main dispatcher
main() {
    local cmd="${1:-}"
    shift || true

    case "$cmd" in
        list)    cmd_list "$@" ;;
        add)     cmd_add "$@" ;;
        remove)  cmd_remove "$@" ;;
        prune)   cmd_prune "$@" ;;
        lock)    cmd_lock "$@" ;;
        unlock)  cmd_unlock "$@" ;;
        info)    cmd_info "$@" ;;
        *)
            cat >&2 <<'EOF'
git_worktree — Git worktree management for agents

Commands:
  list                                    List all worktrees as JSON
  add <path> [branch] [base-branch]       Add a worktree (optionally create branch)
  remove <path> [--force]                 Remove a worktree
  prune [--dry-run]                       Remove stale worktree references
  lock <path>                             Lock a worktree (prevent removal)
  unlock <path>                           Unlock a worktree
  info [path]                             Get worktree details (default: current dir)

Examples:
  worktree.sh list
  worktree.sh add /tmp/feature-x feature-x main
  worktree.sh remove /tmp/feature-x
  worktree.sh prune --dry-run
  worktree.sh info /tmp/feature-x
EOF
            exit 1
            ;;
    esac
}

main "$@"

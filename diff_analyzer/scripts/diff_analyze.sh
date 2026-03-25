#!/usr/bin/env bash
# diff_analyzer — Structured diff analysis for agents
# Usage: diff_analyzer.sh [options] [<file>]
# If no file, reads from stdin.
# Options:
#   --from <ref>        Compare from this ref (git diff ref)
#   --to <ref>          Compare to this ref (default: working tree)
#   --repo <path>       Run in this repo directory
#   --staged            Analyze staged changes (git diff --cached)
#   --file <path>       Analyze diff for a single file
#   --summarize         Include summary statistics

set -euo pipefail

FROM_REF=""
TO_REF=""
REPO=""
STAGED=false
FILE_PATH=""
SUMMARIZE=false
INPUT_FILE=""

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --from)    FROM_REF="$2"; shift 2 ;;
        --to)      TO_REF="$2"; shift 2 ;;
        --repo)    REPO="$2"; shift 2 ;;
        --staged)  STAGED=true; shift ;;
        --file)    FILE_PATH="$2"; shift 2 ;;
        --summarize) SUMMARIZE=true; shift ;;
        -*)        echo '{"error":"unknown option '"$1"'"}' >&2; exit 1 ;;
        *)         INPUT_FILE="$1"; shift ;;
    esac
done

# Get diff content
get_diff() {
    if [[ -n "$INPUT_FILE" && "$INPUT_FILE" != "-" ]]; then
        cat "$INPUT_FILE"
    elif [[ -n "$REPO" || -n "$FROM_REF" || "$STAGED" == "true" || -n "$FILE_PATH" ]]; then
        local args=("diff")
        if [[ "$STAGED" == "true" ]]; then
            args+=("--cached")
        fi
        if [[ -n "$FROM_REF" ]]; then
            if [[ -n "$TO_REF" ]]; then
                args+=("$FROM_REF" "$TO_REF")
            else
                args+=("$FROM_REF")
            fi
        fi
        if [[ -n "$FILE_PATH" ]]; then
            args+=("--" "$FILE_PATH")
        fi

        local dir="."
        if [[ -n "$REPO" ]]; then
            dir="$REPO"
        fi

        git -C "$dir" "${args[@]}"
    else
        cat -
    fi
}

# Check if content looks like binary (has NUL bytes or diff says "Binary files")
is_binary() {
    local file="$1"
    if echo "$2" | grep -q "^Binary files"; then
        return 0
    fi
    if echo "$2" | tr -d '\0' | wc -c | grep -q "^0$"; then
        return 0
    fi
    return 1
}

# Escape a string for JSON
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    echo "$s"
}

# Main analysis
analyze_diff() {
    local diff_content
    diff_content=$(get_diff) || true

    if [[ -z "$diff_content" ]]; then
        echo '{"files":[],"summary":{"files_changed":0,"total_additions":0,"total_deletions":0,"total_lines":0}}'
        return
    fi

    local files_json="["
    local total_add=0
    local total_del=0
    local total_files=0
    local first_file=true

    local current_file=""
    local current_add=0
    local current_del=0
    local current_binary=false
    local current_new=false
    local current_deleted=false
    local current_renamed=false
    local current_rename_from=""
    local current_hunks="["
    local first_hunk=true
    local in_file=false

    # Track hunks
    local hunk_old_start=0 hunk_old_count=0 hunk_new_start=0 hunk_new_count=0
    local hunk_context=""
    local hunk_lines="["
    local in_hunk=false
    local first_line=true

    flush_hunk() {
        if [[ "$in_hunk" == "true" ]]; then
            hunk_lines+="]"
            if [[ "$first_hunk" == "true" ]]; then
                first_hunk=false
            else
                current_hunks+=","
            fi
            local context_escaped
            context_escaped=$(json_escape "$hunk_context")
            current_hunks+=$(printf '{"old_start":%d,"old_count":%d,"new_start":%d,"new_count":%d,"context":"%s","lines":%s}' \
                "$hunk_old_start" "$hunk_old_count" "$hunk_new_start" "$hunk_new_count" "$context_escaped" "$hunk_lines")
            in_hunk=false
            hunk_lines="["
            first_line=true
        fi
    }

    flush_file() {
        if [[ "$in_file" == "true" ]]; then
            flush_hunk
            current_hunks+="]"

            if [[ "$first_file" == "true" ]]; then
                first_file=false
            else
                files_json+=","
            fi

            local type="modified"
            if [[ "$current_new" == "true" ]]; then type="added"; fi
            if [[ "$current_deleted" == "true" ]]; then type="deleted"; fi
            if [[ "$current_renamed" == "true" ]]; then type="renamed"; fi

            files_json+=$(printf '{"path":"%s","type":"%s","binary":%s,"additions":%d,"deletions":%d,"hunks":%s' \
                "$current_file" "$type" "$current_binary" "$current_add" "$current_del" "$current_hunks")

            if [[ "$current_renamed" == "true" ]]; then
                files_json+=$(printf ',"renamed_from":"%s"' "$current_rename_from")
            fi

            files_json+="}"

            total_add=$((total_add + current_add))
            total_del=$((total_del + current_del))
            total_files=$((total_files + 1))
        fi
    }

    while IFS= read -r line; do
        # New file header
        if [[ "$line" =~ ^diff\ --git ]]; then
            flush_file
            # Extract filename: diff --git a/path b/path
            if [[ "$line" =~ ^diff\ --git\ a/(.*)\ b/(.*)$ ]]; then
                current_file="${BASH_REMATCH[2]}"
            else
                current_file="unknown"
            fi
            current_add=0
            current_del=0
            current_binary=false
            current_new=false
            current_deleted=false
            current_renamed=false
            current_rename_from=""
            current_hunks="["
            first_hunk=true
            in_file=true
            in_hunk=false
            hunk_lines="["
            first_line=true
            continue
        fi

        # Detect new file
        if [[ "$line" == "new file mode "* ]]; then
            current_new=true
            continue
        fi

        # Detect deleted file
        if [[ "$line" == "deleted file mode "* ]]; then
            current_deleted=true
            continue
        fi

        # Detect rename
        if [[ "$line" =~ ^rename\ from\ (.*)$ ]]; then
            current_renamed=true
            current_rename_from="${BASH_REMATCH[1]}"
            continue
        fi

        # Detect binary
        if [[ "$line" =~ ^Binary\ files ]]; then
            current_binary=true
            continue
        fi

        # Hunk header
        if [[ "$line" =~ ^@@\ -([0-9]+)(,([0-9]+))?\ \+([0-9]+)(,([0-9]+))?\ @@(.*)$ ]]; then
            flush_hunk
            hunk_old_start="${BASH_REMATCH[1]}"
            hunk_old_count="${BASH_REMATCH[3]:-1}"
            hunk_new_start="${BASH_REMATCH[4]}"
            hunk_new_count="${BASH_REMATCH[6]:-1}"
            hunk_context="${BASH_REMATCH[7]}"
            in_hunk=true
            hunk_lines="["
            first_line=true
            continue
        fi

        # Count additions/deletions
        if [[ "$in_hunk" == "true" ]]; then
            local escaped_line
            escaped_line=$(json_escape "$line")

            if [[ "$first_line" == "true" ]]; then
                first_line=false
            else
                hunk_lines+=","
            fi

            local ltype="context"
            if [[ "$line" == +* && "$line" != "+++"* ]]; then
                ltype="addition"
                current_add=$((current_add + 1))
            elif [[ "$line" == -* && "$line" != "---"* ]]; then
                ltype="deletion"
                current_del=$((current_del + 1))
            fi

            hunk_lines+=$(printf '{"type":"%s","content":"%s"}' "$ltype" "$escaped_line")
        fi
    done <<< "$diff_content"

    flush_file
    files_json+="]"

    # Build output
    local output="{\"files\":$files_json"
    if [[ "$SUMMARIZE" == "true" ]]; then
        output+=$(printf ',"summary":{"files_changed":%d,"total_additions":%d,"total_deletions":%d,"total_lines":%d}' \
            "$total_files" "$total_add" "$total_del" "$((total_add + total_del))")
    fi
    output+="}"

    echo "$output" | jq .
}

analyze_diff

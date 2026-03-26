#!/usr/bin/env bash
# man_page_reader — Parse man pages into structured agent-friendly JSON
# Usage: man_page.sh <command|section> [command]
# Examples:
#   man_page.sh ls
#   man_page.sh 5 passwd
#   man_page.sh --file /path/to/manpage.1

set -uo pipefail

# Prevent interactive pager from launching (safety: prevents shell escape via less)
export MANPAGER=cat
export PAGER=cat

MAN_CMD=""
MAN_SECTION=""
FILE_PATH=""
MAX_DESCRIPTION=500  # Truncate long descriptions

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --file)    FILE_PATH="$2"; shift 2 ;;
        --section) MAN_SECTION="$2"; shift 2 ;;
        -*)
            # If it looks like a command name (multi-char or not a known flag pattern),
            # reject as argument injection rather than unknown option
            echo '{"error":"invalid command name (must not start with dash)","command":"'"$1"'"}' >&2
            exit 1
            ;;
        *)
            if [[ -z "$MAN_CMD" ]]; then
                if [[ "$1" =~ ^[0-9]$ ]]; then
                    MAN_SECTION="$1"
                else
                    MAN_CMD="$1"
                fi
            else
                # Second positional arg after section number
                MAN_CMD="$1"
            fi
            shift
            ;;
    esac
done

# Reject argument injection: command names starting with dash
if [[ -n "$MAN_CMD" && "$MAN_CMD" == -* ]]; then
    echo '{"error":"invalid command name (must not start with dash)","command":"'"$MAN_CMD"'"}' >&2
    exit 1
fi

# Reject section injection: section values starting with dash
if [[ -n "$MAN_SECTION" && "$MAN_SECTION" == -* ]]; then
    echo '{"error":"invalid section (must not start with dash)","section":"'"$MAN_SECTION"'"}' >&2
    exit 1
fi

if [[ -z "$MAN_CMD" && -z "$FILE_PATH" ]]; then
    cat >&2 <<'EOF'
man_page_reader — Parse man pages into structured JSON

Usage:
  man_page.sh <command>              Parse man page for command
  man_page.sh <section> <command>    Parse specific section (1-9)
  man_page.sh --file <path>          Parse a man page file

Options:
  --section <n>    Man section number (1-9)
  --file <path>    Read from file instead of man command

Output JSON:
  {
    "name": "ls",
    "section": "1",
    "synopsis": "ls [OPTION]... [FILE]...",
    "description": "List directory contents...",
    "options": [
      {"flag": "-a", "description": "do not ignore entries starting with ."}
    ],
    "sections": {
      "NAME": "...",
      "SYNOPSIS": "...",
      "DESCRIPTION": "...",
      "OPTIONS": "..."
    },
    "see_also": ["dir(1)", "vdir(1)"]
  }
EOF
    exit 1
fi

# Get raw man page content
get_man_content() {
    if [[ -n "$FILE_PATH" ]]; then
        cat "$FILE_PATH"
    elif [[ -n "$MAN_SECTION" ]]; then
        man "$MAN_SECTION" "$MAN_CMD" 2>/dev/null | col -b 2>/dev/null || true
    else
        man "$MAN_CMD" 2>/dev/null | col -b 2>/dev/null || true
    fi
}

# Clean up man page formatting
clean_man() {
    sed 's/\x08.\x08//g' |  # Remove backspace formatting
    sed 's/^\s*//' |         # Trim leading whitespace
    cat
}

# Extract a named section from the content
extract_section() {
    local content="$1"
    local section_name="$2"

    # Match section headers (all caps, possibly with spaces)
    echo "$content" | awk "
        /^[[:space:]]*${section_name}[[:space:]]*\$/ { found=1; next }
        found && /^[[:space:]]*[A-Z][A-Z _-]+[[:space:]]*\$/ { exit }
        found { print }
    "
}

# Escape a string for JSON
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    # Remove leading/trailing whitespace
    s=$(echo "$s" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    echo "$s"
}

# Parse options from the OPTIONS or FLAGS section
parse_options() {
    local content="$1"
    local options_section

    # Try OPTIONS first, then FLAGS
    options_section=$(extract_section "$content" "OPTIONS")
    if [[ -z "$options_section" ]]; then
        options_section=$(extract_section "$content" "FLAGS")
    fi
    if [[ -z "$options_section" ]]; then
        options_section=$(extract_section "$content" "COMMAND OPTIONS")
    fi

    if [[ -z "$options_section" ]]; then
        echo "[]"
        return
    fi

    local options="["
    local first=true
    local current_flag=""
    local current_desc=""

    while IFS= read -r line; do
        # Match option patterns: -x, --long, -x, --long=value, etc.
        if [[ "$line" =~ ^[[:space:]]*(-[a-zA-Z]|--[a-zA-Z][-a-zA-Z_]*) ]]; then
            # Save previous option if exists
            if [[ -n "$current_flag" ]]; then
                if [[ "$first" == "true" ]]; then first=false; else options+=","; fi
                local flag_esc desc_esc
                flag_esc=$(json_escape "$current_flag")
                desc_esc=$(json_escape "$current_desc")
                options+=$(printf '{"flag":"%s","description":"%s"}' "$flag_esc" "$desc_esc")
            fi

            # Extract new flag and description
            current_flag=$(echo "$line" | grep -oP '^\s*\K(-\w|--[\w-]+(\=\w+)?)' | head -1 || echo "")
            current_desc=$(echo "$line" | sed -E 's/^\s*(-\w|--[\w-]+(\=\w+)?)\s*//' | sed 's/^\s*//')
        elif [[ -n "$current_flag" && -n "$line" ]]; then
            # Continuation of description
            current_desc+=" $(echo "$line" | sed 's/^\s*//')"
        fi
    done <<< "$options_section"

    # Save last option
    if [[ -n "$current_flag" ]]; then
        if [[ "$first" == "true" ]]; then first=false; else options+=","; fi
        local flag_esc desc_esc
        flag_esc=$(json_escape "$current_flag")
        desc_esc=$(json_escape "$current_desc")
        options+=$(printf '{"flag":"%s","description":"%s"}' "$flag_esc" "$desc_esc")
    fi

    options+="]"
    echo "$options"
}

# Parse SEE ALSO references
parse_see_also() {
    local content="$1"
    local see_also_section

    see_also_section=$(extract_section "$content" "SEE ALSO")

    if [[ -z "$see_also_section" ]]; then
        echo "[]"
        return
    fi

    local refs="["
    local first=true

    # Extract references like command(section)
    echo "$see_also_section" | grep -oP '\w+\(\d\)' 2>/dev/null | while IFS= read -r ref; do
        if [[ "$first" == "true" ]]; then first=false; else refs+=","; fi
        refs+="\"$ref\""
    done

    refs+="]"
    echo "$refs"
}

# Main parser
parse_man_page() {
    local raw_content
    raw_content=$(get_man_content)

    if [[ -z "$raw_content" ]]; then
        echo '{"error":"man page not found","command":"'"${MAN_CMD:-$FILE_PATH}"'"}'
        return 1
    fi

    # Clean up
    local content
    content=$(echo "$raw_content" | clean_man)

    # Extract name and section from first line
    local first_line
    first_line=$(echo "$content" | head -1)

    # Try to get section from man
    local section=""
    if [[ -n "$MAN_SECTION" ]]; then
        section="$MAN_SECTION"
    else
        # Try to detect from first line pattern "COMMAND(1)"
        if [[ "$first_line" =~ \(([0-9])\) ]]; then
            section="${BASH_REMATCH[1]}"
        fi
    fi

    # Extract NAME section
    local name_section
    name_section=$(extract_section "$content" "NAME")
    local name=""
    if [[ -n "$name_section" ]]; then
        # NAME section typically has "command - description"
        name=$(echo "$name_section" | head -1 | sed 's/\s*-.*//' | xargs)
    fi
    if [[ -z "$name" && -n "$MAN_CMD" ]]; then
        name="$MAN_CMD"
    fi

    # Extract SYNOPSIS
    local synopsis_section
    synopsis_section=$(extract_section "$content" "SYNOPSIS")
    local synopsis=""
    if [[ -n "$synopsis_section" ]]; then
        synopsis=$(echo "$synopsis_section" | tr '\n' ' ' | sed 's/\s\+/ /g' | xargs)
    fi

    # Extract DESCRIPTION
    local desc_section
    desc_section=$(extract_section "$content" "DESCRIPTION")
    local description=""
    if [[ -n "$desc_section" ]]; then
        description=$(echo "$desc_section" | tr '\n' ' ' | sed 's/\s\+/ /g')
        # Truncate if too long
        if [[ ${#description} -gt $MAX_DESCRIPTION ]]; then
            description="${description:0:$MAX_DESCRIPTION}..."
        fi
        description=$(json_escape "$description")
    fi

    # Extract all sections as key-value pairs
    local sections_json="{"
    local first_section=true
    local current_section_name=""
    local current_section_content=""

    while IFS= read -r line; do
        # Check if this is a section header (ALL CAPS, possibly with spaces)
        if [[ "$line" =~ ^[[:space:]]*([A-Z][A-Z _-]+)[[:space:]]*$ ]]; then
            # Save previous section
            if [[ -n "$current_section_name" ]]; then
                local content_esc
                content_esc=$(json_escape "$current_section_content")
                if [[ ${#content_esc} -gt 500 ]]; then
                    content_esc="${content_esc:0:500}..."
                fi
                if [[ "$first_section" == "true" ]]; then first_section=false; else sections_json+=","; fi
                sections_json+="\"$current_section_name\":\"$content_esc\""
            fi
            current_section_name="${BASH_REMATCH[1]}"
            current_section_content=""
        elif [[ -n "$current_section_name" ]]; then
            if [[ -z "$current_section_content" ]]; then
                current_section_content="$line"
            else
                current_section_content+=" $line"
            fi
        fi
    done <<< "$content"

    # Save last section
    if [[ -n "$current_section_name" ]]; then
        local content_esc
        content_esc=$(json_escape "$current_section_content")
        if [[ ${#content_esc} -gt 500 ]]; then
            content_esc="${content_esc:0:500}..."
        fi
        if [[ "$first_section" == "true" ]]; then first_section=false; else sections_json+=","; fi
        sections_json+="\"$current_section_name\":\"$content_esc\""
    fi
    sections_json+="}"

    # Parse options
    local options
    options=$(parse_options "$content")

    # Parse see also
    local see_also
    see_also=$(parse_see_also "$content")

    # Build output
    local name_esc synopsis_esc
    name_esc=$(json_escape "$name")
    synopsis_esc=$(json_escape "$synopsis")

    printf '{"name":"%s","section":"%s","synopsis":"%s","description":"%s","options":%s,"sections":%s,"see_also":%s}\n' \
        "$name_esc" "$section" "$synopsis_esc" "$description" "$options" "$sections_json" "$see_also" | jq .
}

parse_man_page

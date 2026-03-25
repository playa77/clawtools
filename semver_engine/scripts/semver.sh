#!/usr/bin/env bash
# semver_engine — Deterministic semver operations for agents
# Commands: parse, compare, bump, validate, satisfies
# Usage: semver.sh <command> [args...]

set -euo pipefail

# Parse a semver string into components
# Output: {"major":N,"minor":N,"patch":N,"prerelease":"...","build":"..."}
parse_semver() {
    local ver="$1"
    # Regex: major.minor.patch[-prerelease][+build]
    local regex='^([0-9]+)\.([0-9]+)\.([0-9]+)(-([0-9A-Za-z.-]+))?(\+([0-9A-Za-z.-]+))?$'
    if [[ ! "$ver" =~ $regex ]]; then
        echo '{"error":"invalid semver","input":"'"$ver"'"}' >&2
        return 1
    fi
    local major="${BASH_REMATCH[1]}"
    local minor="${BASH_REMATCH[2]}"
    local patch="${BASH_REMATCH[3]}"
    local prerelease="${BASH_REMATCH[5]:-}"
    local build="${BASH_REMATCH[7]:-}"

    printf '{"major":%d,"minor":%d,"patch":%d,"prerelease":"%s","build":"%s"}\n' \
        "$major" "$minor" "$patch" "$prerelease" "$build"
}

# Validate a semver string
# Output: {"valid":true/false,"input":"..."}
validate_semver() {
    local ver="$1"
    local regex='^([0-9]+)\.([0-9]+)\.([0-9]+)(-([0-9A-Za-z.-]+))?(\+([0-9A-Za-z.-]+))?$'
    if [[ "$ver" =~ $regex ]]; then
        echo '{"valid":true,"input":"'"$ver"'"}'
    else
        echo '{"valid":false,"input":"'"$ver"'"}'
    fi
}

# Compare two semver versions
# Output: -1 (a < b), 0 (a == b), 1 (a > b)
# Note: per semver spec, pre-release versions have lower precedence than normal
compare_semver() {
    local a="$1" b="$2"

    # Parse both
    local ra rb
    ra=$(parse_semver "$a") || return 1
    rb=$(parse_semver "$b") || return 1

    local ma Mi pa pra
    ma=$(echo "$ra" | jq -r '.major')
    Mi=$(echo "$ra" | jq -r '.minor')
    pa=$(echo "$ra" | jq -r '.patch')
    pra=$(echo "$ra" | jq -r '.prerelease')

    local mb Mib pb prb
    mb=$(echo "$rb" | jq -r '.major')
    Mib=$(echo "$rb" | jq -r '.minor')
    pb=$(echo "$rb" | jq -r '.patch')
    prb=$(echo "$rb" | jq -r '.prerelease')

    # Compare major
    if (( ma > mb )); then echo 1; return; fi
    if (( ma < mb )); then echo -1; return; fi

    # Compare minor
    if (( Mi > Mib )); then echo 1; return; fi
    if (( Mi < Mib )); then echo -1; return; fi

    # Compare patch
    if (( pa > pb )); then echo 1; return; fi
    if (( pa < pb )); then echo -1; return; fi

    # Same major.minor.patch — compare prerelease
    # Per semver: no prerelease > has prerelease
    if [[ -z "$pra" && -z "$prb" ]]; then echo 0; return; fi
    if [[ -z "$pra" && -n "$prb" ]]; then echo 1; return; fi
    if [[ -n "$pra" && -z "$prb" ]]; then echo -1; return; fi

    # Both have prerelease — compare dot-separated identifiers
    compare_prerelease "$pra" "$prb"
}

# Compare two prerelease strings per semver spec
compare_prerelease() {
    local a="$1" b="$2"
    local IFS='.'
    local -a a_parts=($a)
    local -a b_parts=($b)
    local max=${#a_parts[@]}
    (( ${#b_parts[@]} > max )) && max=${#b_parts[@]}

    for (( i=0; i<max; i++ )); do
        local ai="${a_parts[$i]:-}"
        local bi="${b_parts[$i]:-}"

        # Missing identifier < present identifier
        if [[ -z "$ai" ]]; then echo -1; return; fi
        if [[ -z "$bi" ]]; then echo 1; return; fi

        # Both numeric?
        local ai_num bi_num
        if [[ "$ai" =~ ^[0-9]+$ ]]; then ai_num=1; else ai_num=0; fi
        if [[ "$bi" =~ ^[0-9]+$ ]]; then bi_num=1; else bi_num=0; fi

        if (( ai_num && bi_num )); then
            # Both numeric — compare as integers
            if (( 10#$ai > 10#$bi )); then echo 1; return; fi
            if (( 10#$ai < 10#$bi )); then echo -1; return; fi
        elif (( !ai_num && !bi_num )); then
            # Both alphanumeric — compare lexically
            if [[ "$ai" > "$bi" ]]; then echo 1; return; fi
            if [[ "$ai" < "$bi" ]]; then echo -1; return; fi
        else
            # Mixed types — numeric has lower precedence
            if (( ai_num )); then echo -1; return; fi
            echo 1; return
        fi
    done
    echo 0
}

# Bump a version
# Usage: semver.sh bump <major|minor|patch|premajor|preminor|prepatch|prerelease> <version> [prerelease-id]
bump_semver() {
    local bump_type="$1"
    local ver="$2"
    local pre_id="${3:-rc}"

    local ra
    ra=$(parse_semver "$ver") || return 1

    local ma Mi pa pra
    ma=$(echo "$ra" | jq -r '.major')
    Mi=$(echo "$ra" | jq -r '.minor')
    pa=$(echo "$ra" | jq -r '.patch')
    pra=$(echo "$ra" | jq -r '.prerelease')

    case "$bump_type" in
        major)
            echo "$((ma+1)).0.0"
            ;;
        minor)
            echo "${ma}.$((Mi+1)).0"
            ;;
        patch)
            echo "${ma}.${Mi}.$((pa+1))"
            ;;
        premajor)
            echo "$((ma+1)).0.0-${pre_id}.0"
            ;;
        preminor)
            echo "${ma}.$((Mi+1)).0-${pre_id}.0"
            ;;
        prepatch)
            echo "${ma}.${Mi}.$((pa+1))-${pre_id}.0"
            ;;
        prerelease)
            if [[ -n "$pra" ]]; then
                # Increment existing prerelease number
                local base num
                if [[ "$pra" =~ ^(.+)\.([0-9]+)$ ]]; then
                    base="${BASH_REMATCH[1]}"
                    num="${BASH_REMATCH[2]}"
                    echo "${ma}.${Mi}.${pa}-${base}.$((num+1))"
                else
                    echo "${ma}.${Mi}.${pa}-${pra}.0"
                fi
            else
                echo "${ma}.${Mi}.$((pa+1))-${pre_id}.0"
            fi
            ;;
        *)
            echo '{"error":"unknown bump type '"$bump_type"'","valid_types":["major","minor","patch","premajor","preminor","prepatch","prerelease"]}' >&2
            return 1
            ;;
    esac
}

# Check if a version satisfies a constraint
# Supports: ==, !=, >, <, >=, <=, ^, ~
# Usage: semver.sh satisfies <version> <constraint>
satisfies_constraint() {
    local ver="$1"
    local constraint="$2"

    # Parse constraint operator and version
    local op cver
    if [[ "$constraint" =~ ^(\^|~|>=|<=|>|<|==|!=)(.+)$ ]]; then
        op="${BASH_REMATCH[1]}"
        cver="${BASH_REMATCH[2]}"
    elif [[ "$constraint" =~ ^([0-9]) ]]; then
        # Bare version means ">= that version"
        op=">="
        cver="$constraint"
    else
        echo '{"error":"invalid constraint","input":"'"$constraint"'"}' >&2
        return 1
    fi

    local cmp
    cmp=$(compare_semver "$ver" "$cver")

    case "$op" in
        "==") [[ "$cmp" -eq 0 ]] ;;
        "!=") [[ "$cmp" -ne 0 ]] ;;
        ">")  [[ "$cmp" -eq 1 ]] ;;
        "<")  [[ "$cmp" -eq -1 ]] ;;
        ">=") [[ "$cmp" -eq 0 || "$cmp" -eq 1 ]] ;;
        "<=") [[ "$cmp" -eq 0 || "$cmp" -eq -1 ]] ;;
        "^")
            # Caret: >=cver, <next major (if major > 0)
            # If major=0 and minor>0: <next minor
            # If major=0 and minor=0: <next patch
            local rb
            rb=$(parse_semver "$cver") || return 1
            local cmaj cmin cpat
            cmaj=$(echo "$rb" | jq -r '.major')
            cmin=$(echo "$rb" | jq -r '.minor')
            cpat=$(echo "$rb" | jq -r '.patch')

            local upper_ok
            if (( cmaj > 0 )); then
                upper_ok=$(compare_semver "$ver" "$((cmaj+1)).0.0")
                [[ "$cmp" -ge 0 && "$upper_ok" -eq -1 ]]
            elif (( cmin > 0 )); then
                upper_ok=$(compare_semver "$ver" "0.$((cmin+1)).0")
                [[ "$cmp" -ge 0 && "$upper_ok" -eq -1 ]]
            else
                upper_ok=$(compare_semver "$ver" "0.0.$((cpat+1))")
                [[ "$cmp" -ge 0 && "$upper_ok" -eq -1 ]]
            fi
            ;;
        "~")
            # Tilde: >=cver, <next minor
            local rb
            rb=$(parse_semver "$cver") || return 1
            local cmaj cmin
            cmaj=$(echo "$rb" | jq -r '.major')
            cmin=$(echo "$rb" | jq -r '.minor')

            local upper_ok
            upper_ok=$(compare_semver "$ver" "${cmaj}.$((cmin+1)).0")
            [[ "$cmp" -ge 0 && "$upper_ok" -eq -1 ]]
            ;;
    esac
}

# Check multiple constraints (space-separated, AND logic)
# Usage: semver.sh satisfies-all <version> "<constraint1> <constraint2> ..."
satisfies_all() {
    local ver="$1"
    shift
    local constraints="$*"

    for c in $constraints; do
        if ! satisfies_constraint "$ver" "$c"; then
            echo '{"satisfies":false,"failed":"'"$c"'","version":"'"$ver"'"}'
            return 0
        fi
    done
    echo '{"satisfies":true,"version":"'"$ver"'","constraints":"'"$constraints"'"}'
}

# Main dispatcher
main() {
    local cmd="${1:-}"
    shift || true

    case "$cmd" in
        parse)
            [[ $# -lt 1 ]] && { echo "Usage: semver.sh parse <version>" >&2; exit 1; }
            parse_semver "$1"
            ;;
        validate)
            [[ $# -lt 1 ]] && { echo "Usage: semver.sh validate <version>" >&2; exit 1; }
            validate_semver "$1"
            ;;
        compare)
            [[ $# -lt 2 ]] && { echo "Usage: semver.sh compare <version_a> <version_b>" >&2; exit 1; }
            local result
            result=$(compare_semver "$1" "$2")
            echo '{"a":"'"$1"'","b":"'"$2"'","result":'"$result"'}'
            ;;
        bump)
            [[ $# -lt 2 ]] && { echo "Usage: semver.sh bump <type> <version> [prerelease-id]" >&2; exit 1; }
            local bumped
            bumped=$(bump_semver "$1" "$2" "${3:-rc}")
            echo '{"input":"'"$2"'","bump":"'"$1"'","result":"'"$bumped"'"}'
            ;;
        satisfies)
            [[ $# -lt 2 ]] && { echo "Usage: semver.sh satisfies <version> <constraint>" >&2; exit 1; }
            if satisfies_constraint "$1" "$2"; then
                echo '{"satisfies":true,"version":"'"$1"'","constraint":"'"$2"'"}'
            else
                echo '{"satisfies":false,"version":"'"$1"'","constraint":"'"$2"'"}'
            fi
            ;;
        satisfies-all)
            [[ $# -lt 2 ]] && { echo "Usage: semver.sh satisfies-all <version> <constraint1> [constraint2...]" >&2; exit 1; }
            satisfies_all "$@"
            ;;
        *)
            cat >&2 <<'EOF'
semver_engine — Deterministic semver operations

Commands:
  parse <version>                         Parse semver into JSON components
  validate <version>                      Validate a semver string
  compare <version_a> <version_b>         Compare two versions (-1/0/1)
  bump <type> <version> [pre-id]          Bump version (major|minor|patch|premajor|preminor|prepatch|prerelease)
  satisfies <version> <constraint>        Check version against constraint (==, !=, >, <, >=, <=, ^, ~)
  satisfies-all <version> <constraints>   Check version against multiple space-separated constraints

Examples:
  semver.sh parse 1.2.3-beta.1+build.42
  semver.sh compare 1.2.3 2.0.0
  semver.sh bump minor 1.2.3
  semver.sh satisfies 1.5.0 "^1.0.0"
  semver.sh satisfies-all 1.5.0 ">=1.0.0" "<2.0.0"
EOF
            exit 1
            ;;
    esac
}

main "$@"

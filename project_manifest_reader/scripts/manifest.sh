#!/usr/bin/env bash
# project_manifest_reader — Cross-ecosystem project manifest reader
# Usage: manifest.sh <project-root> [--fields field1,field2]
# Auto-detects ecosystem and returns normalized metadata as JSON.

set -uo pipefail

PROJECT_ROOT="${1:-.}"
FIELDS=""
DETECT_ONLY=false

# Parse options
shift || true
while [[ $# -gt 0 ]]; do
    case "$1" in
        --fields)   FIELDS="$2"; shift 2 ;;
        --detect)   DETECT_ONLY=true; shift ;;
        -*)         echo '{"error":"unknown option '"$1"'"}' >&2; exit 1 ;;
        *)          shift ;;
    esac
done

if [[ ! -d "$PROJECT_ROOT" ]]; then
    echo '{"error":"directory not found","path":"'"$PROJECT_ROOT"'"}' >&2
    exit 1
fi

# Normalize path
PROJECT_ROOT=$(cd "$PROJECT_ROOT" && pwd -P)

# Detect ecosystem
detect_ecosystem() {
    local detected=()

    [[ -f "$PROJECT_ROOT/package.json" ]] && detected+=("node")
    [[ -f "$PROJECT_ROOT/Cargo.toml" ]] && detected+=("rust")
    [[ -f "$PROJECT_ROOT/pyproject.toml" || -f "$PROJECT_ROOT/setup.py" || -f "$PROJECT_ROOT/setup.cfg" || -f "$PROJECT_ROOT/Pipfile" ]] && detected+=("python")
    [[ -f "$PROJECT_ROOT/go.mod" ]] && detected+=("go")
    [[ -f "$PROJECT_ROOT/build.gradle" || -f "$PROJECT_ROOT/build.gradle.kts" || -f "$PROJECT_ROOT/pom.xml" ]] && detected+=("java")
    [[ -f "$PROJECT_ROOT/Gemfile" ]] && detected+=("ruby")
    [[ -f "$PROJECT_ROOT/composer.json" ]] && detected+=("php")
    [[ -f "$PROJECT_ROOT/CMakeLists.txt" ]] && detected+=("cmake")
    [[ -f "$PROJECT_ROOT/Makefile" ]] && detected+=("make")
    [[ -f "$PROJECT_ROOT/Dockerfile" ]] && detected+=("docker")
    [[ -f "$PROJECT_ROOT/.github/workflows" ]] && detected+=("github_actions")

    # Return as JSON array
    local result="["
    local first=true
    for e in "${detected[@]}"; do
        if [[ "$first" == "true" ]]; then first=false; else result+=","; fi
        result+="\"$e\""
    done
    result+="]"
    echo "$result"
}

# Read Node.js package.json
read_node() {
    local pf="$PROJECT_ROOT/package.json"
    [[ ! -f "$pf" ]] && return

    local name version description main entry license repo_url author
    name=$(jq -r '.name // empty' "$pf")
    version=$(jq -r '.version // empty' "$pf")
    description=$(jq -r '.description // empty' "$pf")
    main=$(jq -r '.main // .exports // empty' "$pf")
    license=$(jq -r '.license // empty' "$pf")
    repo_url=$(jq -r '.repository.url // .repository // empty' "$pf" 2>/dev/null)
    author=$(jq -r '.author.name // .author // empty' "$pf" 2>/dev/null)

    local scripts deps dev_deps
    scripts=$(jq '.scripts // {}' "$pf" 2>/dev/null)
    deps=$(jq '[.dependencies // {} | to_entries[] | {name: .key, version: .value}]' "$pf" 2>/dev/null)
    dev_deps=$(jq '[.devDependencies // {} | to_entries[] | {name: .key, version: .value}]' "$pf" 2>/dev/null)

    local private pkg_type
    private=$(jq -r '.private // false' "$pf" 2>/dev/null)
    pkg_type=$(jq -r '.type // "commonjs"' "$pf" 2>/dev/null)

    local engines_node
    engines_node=$(jq -r '.engines.node // empty' "$pf" 2>/dev/null)

    cat <<JSON
{
    "ecosystem": "node",
    "name": "$name",
    "version": "$version",
    "description": "$description",
    "language": "javascript",
    "entry": "$main",
    "license": "$license",
    "author": "$author",
    "repository": "$repo_url",
    "private": $private,
    "module_type": "$pkg_type",
    "node_engine": "$engines_node",
    "scripts": $scripts,
    "dependencies": $deps,
    "devDependencies": $dev_deps,
    "dependency_count": $(echo "$deps" | jq 'length'),
    "devDependency_count": $(echo "$dev_deps" | jq 'length')
}
JSON
}

# Read Rust Cargo.toml
read_rust() {
    local pf="$PROJECT_ROOT/Cargo.toml"
    [[ ! -f "$pf" ]] && return

    # Simple TOML parsing with grep/sed (no toml parser assumed)
    local name version description edition license
    name=$(grep -oP '^name\s*=\s*"\K[^"]+' "$pf" | head -1 || echo "")
    version=$(grep -oP '^version\s*=\s*"\K[^"]+' "$pf" | head -1 || echo "")
    description=$(grep -oP '^description\s*=\s*"\K[^"]+' "$pf" | head -1 || echo "")
    edition=$(grep -oP '^edition\s*=\s*"\K[^"]+' "$pf" | head -1 || echo "")
    license=$(grep -oP '^license\s*=\s*"\K[^"]+' "$pf" | head -1 || echo "")

    # Parse [dependencies] section
    local deps="["
    local first=true
    local in_deps=false
    while IFS= read -r line; do
        if [[ "$line" == "[dependencies]" ]]; then
            in_deps=true
            continue
        elif [[ "$line" == "["*"]" && "$in_deps" == "true" ]]; then
            break
        elif [[ "$in_deps" == "true" && -n "$line" && "$line" != "#"* ]]; then
            local dep_name
            dep_name=$(echo "$line" | grep -oP '^\s*\K\w[\w-]*' | head -1 || echo "")
            if [[ -n "$dep_name" ]]; then
                if [[ "$first" == "true" ]]; then first=false; else deps+=","; fi
                deps+="\"$dep_name\""
            fi
        fi
    done < "$pf"
    deps+="]"

    local dep_count
    dep_count=$(echo "$deps" | jq 'length')

    cat <<JSON
{
    "ecosystem": "rust",
    "name": "$name",
    "version": "$version",
    "description": "$description",
    "language": "rust",
    "edition": "$edition",
    "license": "$license",
    "dependencies": $deps,
    "dependency_count": $dep_count
}
JSON
}

# Read Python pyproject.toml / setup.py
read_python() {
    local pf=""
    local ecosystem="python"

    if [[ -f "$PROJECT_ROOT/pyproject.toml" ]]; then
        pf="$PROJECT_ROOT/pyproject.toml"
    elif [[ -f "$PROJECT_ROOT/setup.py" ]]; then
        pf="$PROJECT_ROOT/setup.py"
    elif [[ -f "$PROJECT_ROOT/setup.cfg" ]]; then
        pf="$PROJECT_ROOT/setup.cfg"
    elif [[ -f "$PROJECT_ROOT/Pipfile" ]]; then
        pf="$PROJECT_ROOT/Pipfile"
    fi

    [[ -z "$pf" ]] && return

    local name version description python_req
    if [[ "$pf" == *".toml" ]]; then
        name=$(grep -oP '^\s*name\s*=\s*"\K[^"]+' "$pf" | head -1 || echo "")
        version=$(grep -oP '^\s*version\s*=\s*"\K[^"]+' "$pf" | head -1 || echo "")
        description=$(grep -oP '^\s*description\s*=\s*"\K[^"]+' "$pf" | head -1 || echo "")
        python_req=$(grep -oP 'python_requires\s*=\s*"\K[^"]+' "$pf" | head -1 || echo "")
    elif [[ "$pf" == *"setup.py"* ]]; then
        name=$(grep -oP "name=['\"]\\K[^'\"]+" "$pf" | head -1 || echo "")
        version=$(grep -oP "version=['\"]\\K[^'\"]+" "$pf" | head -1 || echo "")
        description=$(grep -oP "description=['\"]\\K[^'\"]+" "$pf" | head -1 || echo "")
    elif [[ "$pf" == *"setup.cfg"* ]]; then
        name=$(grep -oP '^name\s*=\s*\K\S+' "$pf" | head -1 || echo "")
        version=$(grep -oP '^version\s*=\s*\K\S+' "$pf" | head -1 || echo "")
        description=$(grep -oP '^description\s*=\s*\K.*' "$pf" | head -1 || echo "")
    fi

    # Detect build system
    local build_system=""
    if grep -q "\[build-system\]" "$PROJECT_ROOT/pyproject.toml" 2>/dev/null; then
        build_system=$(grep -oP 'requires\s*=\s*\[\s*"\K[^"]+' "$PROJECT_ROOT/pyproject.toml" | head -1 || echo "")
    fi

    # Detect dependencies
    local deps="["
    if [[ -f "$PROJECT_ROOT/requirements.txt" ]]; then
        local first=true
        while IFS= read -r line; do
            line=$(echo "$line" | sed 's/#.*//' | xargs)
            [[ -z "$line" ]] && continue
            local dep_name
            dep_name=$(echo "$line" | sed 's/[>=<!\[].*//' | xargs)
            if [[ -n "$dep_name" ]]; then
                if [[ "$first" == "true" ]]; then first=false; else deps+=","; fi
                deps+="\"$dep_name\""
            fi
        done < "$PROJECT_ROOT/requirements.txt"
    fi
    deps+="]"

    local dep_count
    dep_count=$(echo "$deps" | jq 'length')

    cat <<JSON
{
    "ecosystem": "python",
    "name": "$name",
    "version": "$version",
    "description": "$description",
    "language": "python",
    "python_requires": "$python_req",
    "build_system": "$build_system",
    "dependencies": $deps,
    "dependency_count": $dep_count
}
JSON
}

# Read Go go.mod
read_go() {
    local pf="$PROJECT_ROOT/go.mod"
    [[ ! -f "$pf" ]] && return

    local module_name go_version
    module_name=$(grep -oP '^module\s+\K\S+' "$pf" | head -1 || echo "")
    go_version=$(grep -oP '^go\s+\K\S+' "$pf" | head -1 || echo "")

    # Parse require blocks (there may be multiple)
    local deps="["
    local first=true
    local in_require=false
    while IFS= read -r line; do
        if [[ "$line" == "require ("* ]]; then
            in_require=true
            continue
        elif [[ "$line" == ")" && "$in_require" == "true" ]]; then
            in_require=false
            continue
        elif [[ "$in_require" == "true" && -n "$line" ]]; then
            local dep_name
            dep_name=$(echo "$line" | awk '{print $1}')
            if [[ -n "$dep_name" && "$dep_name" != "//" ]]; then
                if [[ "$first" == "true" ]]; then first=false; else deps+=","; fi
                deps+="\"$dep_name\""
            fi
        fi
    done < "$pf"
    deps+="]"

    local dep_count
    dep_count=$(echo "$deps" | jq 'length')

    cat <<JSON
{
    "ecosystem": "go",
    "name": "$module_name",
    "version": "",
    "description": "",
    "language": "go",
    "go_version": "$go_version",
    "dependencies": $deps,
    "dependency_count": $dep_count
}
JSON
}

# Read Java build.gradle / pom.xml
read_java() {
    local pf=""
    if [[ -f "$PROJECT_ROOT/build.gradle" ]]; then
        pf="$PROJECT_ROOT/build.gradle"
    elif [[ -f "$PROJECT_ROOT/build.gradle.kts" ]]; then
        pf="$PROJECT_ROOT/build.gradle.kts"
    elif [[ -f "$PROJECT_ROOT/pom.xml" ]]; then
        pf="$PROJECT_ROOT/pom.xml"
    fi

    [[ -z "$pf" ]] && return

    local name version description java_version
    if [[ "$pf" == *"pom.xml"* ]]; then
        name=$(grep -oP '<artifactId>\K[^<]+' "$pf" | head -1 || echo "")
        version=$(grep -oP '<version>\K[^<]+' "$pf" | head -1 || echo "")
        description=$(grep -oP '<description>\K[^<]+' "$pf" | head -1 || echo "")
    else
        name=$(grep -oP "^rootProject\.name\s*=\s*['\"]\\K[^'\"]+" "$pf" | head -1 || echo "")
        version=$(grep -oP "^version\s*=\s*['\"]\\K[^'\"]+" "$pf" | head -1 || echo "")
    fi

    cat <<JSON
{
    "ecosystem": "java",
    "name": "$name",
    "version": "$version",
    "description": "$description",
    "language": "java"
}
JSON
}

# Read Ruby Gemfile
read_ruby() {
    local pf="$PROJECT_ROOT/Gemfile"
    [[ ! -f "$pf" ]] && return

    local deps="["
    local first=true
    while IFS= read -r line; do
        if [[ "$line" =~ gem\ \'([^\']+)\'|gem\ \"([^\"]+)\" ]]; then
            local dep="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
            if [[ "$first" == "true" ]]; then first=false; else deps+=","; fi
            deps+="\"$dep\""
        fi
    done < "$pf"
    deps+="]"

    local dep_count
    dep_count=$(echo "$deps" | jq 'length')

    cat <<JSON
{
    "ecosystem": "ruby",
    "name": "",
    "version": "",
    "description": "",
    "language": "ruby",
    "dependencies": $deps,
    "dependency_count": $dep_count
}
JSON
}

# Main
main() {
    # Detect ecosystem
    local ecosystems
    ecosystems=$(detect_ecosystem)

    if [[ "$ecosystems" == "[]" ]]; then
        echo '{"ecosystem":"unknown","name":"","version":"","description":"","language":"","dependencies":[],"dependency_count":0,"detected_files":[]}' | jq .
        return
    fi

    if [[ "$DETECT_ONLY" == "true" ]]; then
        echo "{\"ecosystems\":$ecosystems}" | jq .
        return
    fi

    # Read primary ecosystem manifest (first detected)
    local primary
    primary=$(echo "$ecosystems" | jq -r '.[0]')

    local manifest=""
    case "$primary" in
        node)   manifest=$(read_node) ;;
        rust)   manifest=$(read_rust) ;;
        python) manifest=$(read_python) ;;
        go)     manifest=$(read_go) ;;
        java)   manifest=$(read_java) ;;
        ruby)   manifest=$(read_ruby) ;;
        *)      manifest='{"ecosystem":"'"$primary"'","name":"","version":"","description":""}' ;;
    esac

    # Add metadata
    manifest=$(echo "$manifest" | jq --arg root "$PROJECT_ROOT" --argjson all "$ecosystems" \
        '. + {project_root: $root, detected_ecosystems: $all}')

    # Filter fields if requested
    if [[ -n "$FIELDS" ]]; then
        local jq_fields=""
        IFS=',' read -ra FLDS <<< "$FIELDS"
        for f in "${FLDS[@]}"; do
            jq_fields+=".$f, "
        done
        jq_fields="${jq_fields%, }"
        manifest=$(echo "$manifest" | jq "{$jq_fields}")
    fi

    echo "$manifest" | jq .
}

main

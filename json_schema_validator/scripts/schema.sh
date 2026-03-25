#!/usr/bin/env bash
# json_schema_validator — Validate JSON against schemas and infer schemas from data
# Commands: validate, infer
# Usage: schema.sh <command> [args...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Read JSON from file or stdin
read_json() {
    local input="${1:--}"
    if [[ "$input" == "-" ]]; then
        cat -
    elif [[ -f "$input" ]]; then
        cat "$input"
    else
        echo "$input"
    fi
}

# Validate a value against a schema type
# Returns "true" or "false"
check_type() {
    local value="$1"
    local expected="$2"

    case "$expected" in
        string)
            # JSON strings are quoted
            [[ "$value" =~ ^\" ]] && echo "true" || echo "false"
            ;;
        number)
            # JSON numbers are unquoted and numeric
            [[ "$value" =~ ^-?[0-9]+\.?[0-9]*([eE][+-]?[0-9]+)?$ ]] && echo "true" || echo "false"
            ;;
        integer)
            [[ "$value" =~ ^-?[0-9]+$ ]] && echo "true" || echo "false"
            ;;
        boolean)
            [[ "$value" == "true" || "$value" == "false" ]] && echo "true" || echo "false"
            ;;
        null)
            [[ "$value" == "null" ]] && echo "true" || echo "false"
            ;;
        array)
            [[ "$value" =~ ^\[ ]] && echo "true" || echo "false"
            ;;
        object)
            [[ "$value" =~ ^\{ ]] && echo "true" || echo "false"
            ;;
        *)
            echo "false"
            ;;
    esac
}

# Main validation using jq as the JSON processor
validate_json() {
    local schema_file="$1"
    local data_file="$2"

    # Read schema and data
    local schema data
    schema=$(cat "$schema_file")
    data=$(cat "$data_file")

    # Validate JSON syntax first
    if ! echo "$data" | jq . > /dev/null 2>&1; then
        echo '{"valid":false,"errors":[{"path":"root","message":"Invalid JSON"}],"schema":"'"$(echo "$schema" | jq -r '.title // "schema"')"'"}'
        return
    fi

    # Use jq to do the heavy lifting
    local errors="[]"
    local valid="true"

    # Type check
    local schema_type
    schema_type=$(echo "$schema" | jq -r '.type // empty')

    if [[ -n "$schema_type" ]]; then
        local data_type
        data_type=$(echo "$data" | jq -r 'type')

        # Map jq types to schema types
        case "$data_type" in
            "string") data_type="string" ;;
            "number") data_type="number" ;;
            "boolean") data_type="boolean" ;;
            "null") data_type="null" ;;
            "array") data_type="array" ;;
            "object") data_type="object" ;;
        esac

        # Handle type arrays (e.g., ["string", "null"])
        if echo "$schema_type" | jq -e 'type == "array"' > /dev/null 2>&1; then
            local matches
            matches=$(echo "$schema_type" | jq --arg dt "$data_type" 'map(select(. == $dt)) | length')
            if [[ "$matches" == "0" ]]; then
                errors=$(echo "$errors" | jq --arg dt "$data_type" --arg st "$(echo "$schema_type" | jq -r 'join(", ")')" \
                    '. += [{"path":"root","message":"type mismatch: expected one of (\($st)), got \($dt)"}]')
                valid="false"
            fi
        elif [[ "$data_type" != "$schema_type" ]]; then
            # jq can't distinguish integer from number — accept number for integer
            if ! [[ "$schema_type" == "integer" && "$data_type" == "number" ]]; then
                errors=$(echo "$errors" | jq --arg dt "$data_type" --arg st "$schema_type" \
                    '. += [{"path":"root","message":"type mismatch: expected \($st), got \($dt)"}]')
                valid="false"
            fi
        fi
    fi

    # Required properties
    local required
    required=$(echo "$schema" | jq -r '.required // []')
    local req_count
    req_count=$(echo "$required" | jq 'length')

    if [[ "$req_count" -gt 0 ]]; then
        errors=$(echo "$errors" | jq --argjson data "$data" --argjson required "$required" '
            reduce $required[] as $prop (.;
                if ($data | has($prop)) | not then
                    . += [{"path":$prop,"message":"required property \($prop) is missing"}]
                else . end
            )')
        local missing
        missing=$(echo "$errors" | jq --argjson rc "$req_count" 'length')
        if [[ "$missing" -gt 0 ]]; then
            valid="false"
        fi
    fi

    # Properties validation
    local properties
    properties=$(echo "$schema" | jq -r '.properties // {}')
    local prop_names
    prop_names=$(echo "$properties" | jq -r 'keys[]')

    # Additional properties check
    local has_additional_props
    has_additional_props=$(echo "$schema" | jq 'has("additionalProperties")')

    if [[ "$has_additional_props" == "true" ]]; then
        local additional_props
        additional_props=$(echo "$schema" | jq -r '.additionalProperties')

        if [[ "$additional_props" == "false" ]]; then
            local data_keys schema_keys
            data_keys=$(echo "$data" | jq -r 'keys[]' 2>/dev/null || true)
            schema_keys=$(echo "$properties" | jq -r 'keys[]' 2>/dev/null || true)

            while IFS= read -r key; do
                if [[ -n "$key" ]] && ! echo "$schema_keys" | grep -qx "$key"; then
                    errors=$(echo "$errors" | jq --arg k "$key" \
                        '. += [{"path":$k,"message":"additional property \($k) is not allowed"}]')
                    valid="false"
                fi
            done <<< "$data_keys"
        fi
    fi

    # Property-level validation — use process substitution to avoid subshell
    local prop_names_arr
    prop_names_arr=$(echo "$properties" | jq -r 'keys[]')

    local prop_errors_file
    prop_errors_file=$(mktemp)
    echo '[]' > "$prop_errors_file"
    local prop_valid="true"

    while IFS= read -r prop_name; do
        [[ -z "$prop_name" ]] && continue

        # Skip if property doesn't exist in data
        local has_prop
        has_prop=$(echo "$data" | jq --arg p "$prop_name" 'has($p)')
        if [[ "$has_prop" != "true" ]]; then
            continue
        fi

        local prop_value prop_schema
        prop_value=$(echo "$data" | jq --arg p "$prop_name" '.[$p]')
        prop_schema=$(echo "$properties" | jq --arg p "$prop_name" '.[$p]')

        # Type check
        local prop_type
        prop_type=$(echo "$prop_schema" | jq -r '.type // empty')
        if [[ -n "$prop_type" ]]; then
            local actual_type
            actual_type=$(echo "$prop_value" | jq -r 'type')
            # jq can't distinguish integer from number — treat number as valid for integer
            local type_ok=true
            if [[ "$actual_type" != "$prop_type" ]]; then
                if [[ "$prop_type" == "integer" && "$actual_type" == "number" ]]; then
                    type_ok=true
                else
                    type_ok=false
                fi
            fi
            if [[ "$type_ok" == "false" ]]; then
                cat "$prop_errors_file" | jq --arg p "$prop_name" --arg at "$actual_type" --arg et "$prop_type" \
                    '. += [{"path":$p,"message":"type mismatch: expected \($et), got \($at)"}]' > "$prop_errors_file.tmp" && mv "$prop_errors_file.tmp" "$prop_errors_file"
                prop_valid="false"
            fi
        fi

        # Enum check
        local prop_enum
        prop_enum=$(echo "$prop_schema" | jq 'has("enum")')
        if [[ "$prop_enum" == "true" ]]; then
            local in_prop_enum
            in_prop_enum=$(echo "$prop_schema" | jq --argjson v "$prop_value" '.enum | map(select(. == $v)) | length > 0')
            if [[ "$in_prop_enum" != "true" ]]; then
                local allowed
                allowed=$(echo "$prop_schema" | jq -r '.enum | map(tostring) | join(", ")')
                cat "$prop_errors_file" | jq --arg p "$prop_name" --arg a "$allowed" \
                    '. += [{"path":$p,"message":"value not in allowed values: \($a)"}]' > "$prop_errors_file.tmp" && mv "$prop_errors_file.tmp" "$prop_errors_file"
                prop_valid="false"
            fi
        fi

        # Number constraints
        if [[ "$prop_type" == "number" || "$prop_type" == "integer" ]]; then
            local prop_min prop_max
            prop_min=$(echo "$prop_schema" | jq 'has("minimum")')
            prop_max=$(echo "$prop_schema" | jq 'has("maximum")')

            if [[ "$prop_min" == "true" ]]; then
                local min_val val_num
                min_val=$(echo "$prop_schema" | jq '.minimum')
                val_num=$(echo "$prop_value" | jq '.')
                if (( $(echo "$val_num < $min_val" | bc -l 2>/dev/null || echo "0") )); then
                    cat "$prop_errors_file" | jq --arg p "$prop_name" --arg m "$min_val" --arg d "$val_num" \
                        '. += [{"path":$p,"message":"value \($d) is less than minimum \($m)"}]' > "$prop_errors_file.tmp" && mv "$prop_errors_file.tmp" "$prop_errors_file"
                    prop_valid="false"
                fi
            fi

            if [[ "$prop_max" == "true" ]]; then
                local max_val val_num
                max_val=$(echo "$prop_schema" | jq '.maximum')
                val_num=$(echo "$prop_value" | jq '.')
                if (( $(echo "$val_num > $max_val" | bc -l 2>/dev/null || echo "0") )); then
                    cat "$prop_errors_file" | jq --arg p "$prop_name" --arg m "$max_val" --arg d "$val_num" \
                        '. += [{"path":$p,"message":"value \($d) is greater than maximum \($m)"}]' > "$prop_errors_file.tmp" && mv "$prop_errors_file.tmp" "$prop_errors_file"
                    prop_valid="false"
                fi
            fi
        fi

        # String constraints
        if [[ "$prop_type" == "string" ]]; then
            local prop_minlen prop_maxlen
            prop_minlen=$(echo "$prop_schema" | jq 'has("minLength")')
            prop_maxlen=$(echo "$prop_schema" | jq 'has("maxLength")')

            if [[ "$prop_minlen" == "true" ]]; then
                local minlen strlen
                minlen=$(echo "$prop_schema" | jq '.minLength')
                strlen=$(echo "$prop_value" | jq -r '. | length')
                if [[ "$strlen" -lt "$minlen" ]]; then
                    cat "$prop_errors_file" | jq --arg p "$prop_name" --arg m "$minlen" --arg l "$strlen" \
                        '. += [{"path":$p,"message":"string length \($l) is less than minLength \($m)"}]' > "$prop_errors_file.tmp" && mv "$prop_errors_file.tmp" "$prop_errors_file"
                    prop_valid="false"
                fi
            fi

            if [[ "$prop_maxlen" == "true" ]]; then
                local maxlen strlen
                maxlen=$(echo "$prop_schema" | jq '.maxLength')
                strlen=$(echo "$prop_value" | jq -r '. | length')
                if [[ "$strlen" -gt "$maxlen" ]]; then
                    cat "$prop_errors_file" | jq --arg p "$prop_name" --arg m "$maxlen" --arg l "$strlen" \
                        '. += [{"path":$p,"message":"string length \($l) is greater than maxLength \($m)"}]' > "$prop_errors_file.tmp" && mv "$prop_errors_file.tmp" "$prop_errors_file"
                    prop_valid="false"
                fi
            fi

            # Format check
            local prop_format
            prop_format=$(echo "$prop_schema" | jq -r '.format // empty')
            if [[ -n "$prop_format" ]]; then
                local strval format_ok
                strval=$(echo "$prop_value" | jq -r '.')
                format_ok=true
                case "$prop_format" in
                    email) echo "$strval" | grep -qP '^[^@]+@[^@]+\.[^@]+$' || format_ok=false ;;
                    uri) echo "$strval" | grep -qP '^https?://' || format_ok=false ;;
                    date) echo "$strval" | grep -qP '^\d{4}-\d{2}-\d{2}$' || format_ok=false ;;
                    date-time) echo "$strval" | grep -qP '^\d{4}-\d{2}-\d{2}T' || format_ok=false ;;
                    ipv4) echo "$strval" | grep -qP '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$' || format_ok=false ;;
                esac
                if [[ "$format_ok" == "false" ]]; then
                    cat "$prop_errors_file" | jq --arg p "$prop_name" --arg f "$prop_format" \
                        '. += [{"path":$p,"message":"string does not match format \($f)"}]' > "$prop_errors_file.tmp" && mv "$prop_errors_file.tmp" "$prop_errors_file"
                    prop_valid="false"
                fi
            fi

            # Pattern check
            local prop_pattern
            prop_pattern=$(echo "$prop_schema" | jq -r '.pattern // empty')
            if [[ -n "$prop_pattern" ]]; then
                local strval
                strval=$(echo "$prop_value" | jq -r '.')
                if ! echo "$strval" | grep -qP "$prop_pattern" 2>/dev/null; then
                    cat "$prop_errors_file" | jq --arg p "$prop_name" --arg pat "$prop_pattern" \
                        '. += [{"path":$p,"message":"string does not match pattern \($pat)"}]' > "$prop_errors_file.tmp" && mv "$prop_errors_file.tmp" "$prop_errors_file"
                    prop_valid="false"
                fi
            fi
        fi

        # Array constraints
        if [[ "$prop_type" == "array" ]]; then
            local prop_minitems prop_maxitems
            prop_minitems=$(echo "$prop_schema" | jq 'has("minItems")')
            prop_maxitems=$(echo "$prop_schema" | jq 'has("maxItems")')

            if [[ "$prop_minitems" == "true" ]]; then
                local minitems arrlen
                minitems=$(echo "$prop_schema" | jq '.minItems')
                arrlen=$(echo "$prop_value" | jq 'length')
                if [[ "$arrlen" -lt "$minitems" ]]; then
                    cat "$prop_errors_file" | jq --arg p "$prop_name" --arg m "$minitems" --arg l "$arrlen" \
                        '. += [{"path":$p,"message":"array length \($l) is less than minItems \($m)"}]' > "$prop_errors_file.tmp" && mv "$prop_errors_file.tmp" "$prop_errors_file"
                    prop_valid="false"
                fi
            fi

            if [[ "$prop_maxitems" == "true" ]]; then
                local maxitems arrlen
                maxitems=$(echo "$prop_schema" | jq '.maxItems')
                arrlen=$(echo "$prop_value" | jq 'length')
                if [[ "$arrlen" -gt "$maxitems" ]]; then
                    cat "$prop_errors_file" | jq --arg p "$prop_name" --arg m "$maxitems" --arg l "$arrlen" \
                        '. += [{"path":$p,"message":"array length \($l) is greater than maxItems \($m)"}]' > "$prop_errors_file.tmp" && mv "$prop_errors_file.tmp" "$prop_errors_file"
                    prop_valid="false"
                fi
            fi
        fi
    done <<< "$prop_names_arr"

    # Merge property errors
    local prop_errors
    prop_errors=$(cat "$prop_errors_file")
    rm -f "$prop_errors_file" "$prop_errors_file.tmp"
    errors=$(echo "$errors" | jq --argjson pe "$prop_errors" '. + $pe')
    if [[ "$prop_valid" == "false" ]]; then
        valid="false"
    fi

    # Enum check
    local enum_val
    enum_val=$(echo "$schema" | jq -r '.enum // empty')
    if [[ -n "$enum_val" && "$enum_val" != "null" ]]; then
        local in_enum
        in_enum=$(echo "$schema" | jq --argjson d "$data" '.enum | map(select(. == $d)) | length > 0')
        if [[ "$in_enum" != "true" ]]; then
            local allowed
            allowed=$(echo "$schema" | jq -r '.enum | map(tostring) | join(", ")')
            errors=$(echo "$errors" | jq --arg a "$allowed" \
                '. += [{"path":"root","message":"value not in allowed values: \($a)"}]')
            valid="false"
        fi
    fi

    # Const check
    local const_val
    const_val=$(echo "$schema" | jq 'has("const")')
    if [[ "$const_val" == "true" ]]; then
        local expected_const
        expected_const=$(echo "$schema" | jq '.const')
        if [[ "$data" != "$expected_const" ]]; then
            errors=$(echo "$errors" | jq --arg e "$expected_const" --arg g "$data" \
                '. += [{"path":"root","message":"const mismatch: expected \($e), got \($g)"}]')
            valid="false"
        fi
    fi

    # Min/max for numbers
    if [[ "$schema_type" == "number" || "$schema_type" == "integer" ]]; then
        local minimum maximum
        minimum=$(echo "$schema" | jq 'has("minimum")')
        maximum=$(echo "$schema" | jq 'has("maximum")')

        if [[ "$minimum" == "true" ]]; then
            local min_val
            min_val=$(echo "$schema" | jq '.minimum')
            local data_num
            data_num=$(echo "$data" | jq '.')
            if (( $(echo "$data_num < $min_val" | bc -l 2>/dev/null || echo "0") )); then
                errors=$(echo "$errors" | jq --arg m "$min_val" --arg d "$data_num" \
                    '. += [{"path":"root","message":"value \($d) is less than minimum \($m)"}]')
                valid="false"
            fi
        fi

        if [[ "$maximum" == "true" ]]; then
            local max_val
            max_val=$(echo "$schema" | jq '.maximum')
            local data_num
            data_num=$(echo "$data" | jq '.')
            if (( $(echo "$data_num > $max_val" | bc -l 2>/dev/null || echo "0") )); then
                errors=$(echo "$errors" | jq --arg m "$max_val" --arg d "$data_num" \
                    '. += [{"path":"root","message":"value \($d) is greater than maximum \($m)"}]')
                valid="false"
            fi
        fi
    fi

    # Min/max length for strings
    if [[ "$schema_type" == "string" ]]; then
        local has_minlen has_maxlen
        has_minlen=$(echo "$schema" | jq 'has("minLength")')
        has_maxlen=$(echo "$schema" | jq 'has("maxLength")')

        if [[ "$has_minlen" == "true" ]]; then
            local minlen
            minlen=$(echo "$schema" | jq '.minLength')
            local strlen
            strlen=$(echo "$data" | jq -r '. | length')
            if [[ "$strlen" -lt "$minlen" ]]; then
                errors=$(echo "$errors" | jq --arg m "$minlen" --arg l "$strlen" \
                    '. += [{"path":"root","message":"string length \($l) is less than minLength \($m)"}]')
                valid="false"
            fi
        fi

        if [[ "$has_maxlen" == "true" ]]; then
            local maxlen
            maxlen=$(echo "$schema" | jq '.maxLength')
            local strlen
            strlen=$(echo "$data" | jq -r '. | length')
            if [[ "$strlen" -gt "$maxlen" ]]; then
                errors=$(echo "$errors" | jq --arg m "$maxlen" --arg l "$strlen" \
                    '. += [{"path":"root","message":"string length \($l) is greater than maxLength \($m)"}]')
                valid="false"
            fi
        fi
    fi

    # Min/max items for arrays
    if [[ "$schema_type" == "array" ]]; then
        local has_minitems has_maxitems
        has_minitems=$(echo "$schema" | jq 'has("minItems")')
        has_maxitems=$(echo "$schema" | jq 'has("maxItems")')

        if [[ "$has_minitems" == "true" ]]; then
            local minitems
            minitems=$(echo "$schema" | jq '.minItems')
            local arrlen
            arrlen=$(echo "$data" | jq 'length')
            if [[ "$arrlen" -lt "$minitems" ]]; then
                errors=$(echo "$errors" | jq --arg m "$minitems" --arg l "$arrlen" \
                    '. += [{"path":"root","message":"array length \($l) is less than minItems \($m)"}]')
                valid="false"
            fi
        fi

        if [[ "$has_maxitems" == "true" ]]; then
            local maxitems
            maxitems=$(echo "$schema" | jq '.maxItems')
            local arrlen
            arrlen=$(echo "$data" | jq 'length')
            if [[ "$arrlen" -gt "$maxitems" ]]; then
                errors=$(echo "$errors" | jq --arg m "$maxitems" --arg l "$arrlen" \
                    '. += [{"path":"root","message":"array length \($l) is greater than maxItems \($m)"}]')
                valid="false"
            fi
        fi

        # Items type validation
        local items_schema
        items_schema=$(echo "$schema" | jq '.items // empty')
        if [[ -n "$items_schema" && "$items_schema" != "null" ]]; then
            local items_type
            items_type=$(echo "$items_schema" | jq -r '.type // empty')
            if [[ -n "$items_type" ]]; then
                local idx=0
                echo "$data" | jq -c '.[]' 2>/dev/null | while IFS= read -r item; do
                    local item_type
                    item_type=$(echo "$item" | jq -r 'type')
                    if [[ "$item_type" != "$items_type" ]]; then
                        errors=$(echo "$errors" | jq --arg i "$idx" --arg it "$item_type" --arg et "$items_type" \
                            '. += [{"path":"[\($i)]","message":"type mismatch: expected \($et), got \($it)"}]')
                        valid="false"
                    fi
                    ((idx++)) || true
                done
            fi
        fi
    fi

    # Min/max properties for objects
    if [[ "$schema_type" == "object" ]]; then
        local has_minprops has_maxprops
        has_minprops=$(echo "$schema" | jq 'has("minProperties")')
        has_maxprops=$(echo "$schema" | jq 'has("maxProperties")')

        if [[ "$has_minprops" == "true" ]]; then
            local minprops
            minprops=$(echo "$schema" | jq '.minProperties')
            local objlen
            objlen=$(echo "$data" | jq 'length')
            if [[ "$objlen" -lt "$minprops" ]]; then
                errors=$(echo "$errors" | jq --arg m "$minprops" --arg l "$objlen" \
                    '. += [{"path":"root","message":"object property count \($l) is less than minProperties \($m)"}]')
                valid="false"
            fi
        fi

        if [[ "$has_maxprops" == "true" ]]; then
            local maxprops
            maxprops=$(echo "$schema" | jq '.maxProperties')
            local objlen
            objlen=$(echo "$data" | jq 'length')
            if [[ "$objlen" -gt "$maxprops" ]]; then
                errors=$(echo "$errors" | jq --arg m "$maxprops" --arg l "$objlen" \
                    '. += [{"path":"root","message":"object property count \($l) is greater than maxProperties \($m)"}]')
                valid="false"
            fi
        fi
    fi

    # Pattern check for strings
    if [[ "$schema_type" == "string" ]]; then
        local has_pattern
        has_pattern=$(echo "$schema" | jq 'has("pattern")')
        if [[ "$has_pattern" == "true" ]]; then
            local pattern
            pattern=$(echo "$schema" | jq -r '.pattern')
            local strval
            strval=$(echo "$data" | jq -r '.')
            if ! echo "$strval" | grep -qP "$pattern" 2>/dev/null; then
                errors=$(echo "$errors" | jq --arg p "$pattern" \
                    '. += [{"path":"root","message":"string does not match pattern \($p)"}]')
                valid="false"
            fi
        fi
    fi

    # Format check (basic: email, uri, date, date-time)
    if [[ "$schema_type" == "string" ]]; then
        local has_format
        has_format=$(echo "$schema" | jq 'has("format")')
        if [[ "$has_format" == "true" ]]; then
            local format
            format=$(echo "$schema" | jq -r '.format')
            local strval
            strval=$(echo "$data" | jq -r '.')
            local format_ok=true

            case "$format" in
                email)
                    echo "$strval" | grep -qP '^[^@]+@[^@]+\.[^@]+$' || format_ok=false
                    ;;
                uri)
                    echo "$strval" | grep -qP '^https?://' || format_ok=false
                    ;;
                date)
                    echo "$strval" | grep -qP '^\d{4}-\d{2}-\d{2}$' || format_ok=false
                    ;;
                date-time)
                    echo "$strval" | grep -qP '^\d{4}-\d{2}-\d{2}T' || format_ok=false
                    ;;
                ipv4)
                    echo "$strval" | grep -qP '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$' || format_ok=false
                    ;;
            esac

            if [[ "$format_ok" == "false" ]]; then
                errors=$(echo "$errors" | jq --arg f "$format" \
                    '. += [{"path":"root","message":"string does not match format \($f)"}]')
                valid="false"
            fi
        fi
    fi

    local error_count
    error_count=$(echo "$errors" | jq 'length')

    # Remove empty errors if valid
    if [[ "$valid" == "true" ]]; then
        errors="[]"
    fi

    local schema_title
    schema_title=$(echo "$schema" | jq -r '.title // "schema"')

    echo "{\"valid\":$valid,\"errors\":$errors,\"error_count\":$error_count,\"schema\":\"$schema_title\"}"
}

# Infer a JSON Schema from a sample
infer_schema() {
    local data_file="$1"
    local data
    data=$(cat "$data_file")

    # Validate input
    if ! echo "$data" | jq . > /dev/null 2>&1; then
        echo '{"error":"invalid JSON input"}' >&2
        return 1
    fi

    local data_type
    data_type=$(echo "$data" | jq -r 'type')

    case "$data_type" in
        object)
            local props="{}"
            local required="[]"

            echo "$data" | jq -c 'to_entries[]' 2>/dev/null | while IFS= read -r entry; do
                local key value val_type
                key=$(echo "$entry" | jq -r '.key')
                value=$(echo "$entry" | jq '.value')
                val_type=$(echo "$value" | jq -r 'type')

                local prop_schema
                case "$val_type" in
                    string)  prop_schema='{"type":"string"}' ;;
                    number)  prop_schema='{"type":"number"}' ;;
                    boolean) prop_schema='{"type":"boolean"}' ;;
                    null)    prop_schema='{"type":"null"}' ;;
                    array)
                        # Check first element type
                        local elem_type
                        elem_type=$(echo "$value" | jq -r '.[0] | type // "null"')
                        case "$elem_type" in
                            string)  prop_schema='{"type":"array","items":{"type":"string"}}' ;;
                            number)  prop_schema='{"type":"array","items":{"type":"number"}}' ;;
                            boolean) prop_schema='{"type":"array","items":{"type":"boolean"}}' ;;
                            object)  prop_schema='{"type":"array","items":{"type":"object"}}' ;;
                            *)       prop_schema='{"type":"array"}' ;;
                        esac
                        ;;
                    object)  prop_schema='{"type":"object"}' ;;
                    *)       prop_schema='{}' ;;
                esac

                echo "$key|$prop_schema"
            done | {
                props="{}"
                required="[]"
                while IFS='|' read -r key schema; do
                    props=$(echo "$props" | jq --arg k "$key" --argjson s "$schema" '. + {($k): $s}')
                    required=$(echo "$required" | jq --arg k "$key" '. + [$k]')
                done

                echo "{\"type\":\"object\",\"properties\":$props,\"required\":$required}"
            }
            ;;
        array)
            local elem_type
            elem_type=$(echo "$data" | jq -r '.[0] | type // "null"')
            local items_schema
            case "$elem_type" in
                string)  items_schema='{"type":"string"}' ;;
                number)  items_schema='{"type":"number"}' ;;
                boolean) items_schema='{"type":"boolean"}' ;;
                object)  items_schema='{"type":"object"}' ;;
                *)       items_schema='{}' ;;
            esac
            echo "{\"type\":\"array\",\"items\":$items_schema}"
            ;;
        string)  echo '{"type":"string"}' ;;
        number)  echo '{"type":"number"}' ;;
        boolean) echo '{"type":"boolean"}' ;;
        null)    echo '{"type":"null"}' ;;
        *)       echo '{"type":"string"}' ;;
    esac
}

# Main dispatcher
main() {
    local cmd="${1:-}"
    shift || true

    case "$cmd" in
        validate)
            local schema_input="${1:-}"
            local data_input="${2:-}"

            if [[ -z "$schema_input" ]]; then
                echo '{"error":"schema file required","usage":"schema.sh validate <schema.json> <data.json>"}' >&2
                exit 1
            fi

            local schema_tmp data_tmp
            schema_tmp=$(mktemp)
            data_tmp=$(mktemp)
            trap "rm -f '$schema_tmp' '$data_tmp'" EXIT

            read_json "$schema_input" > "$schema_tmp"
            read_json "$data_input" > "$data_tmp"

            validate_json "$schema_tmp" "$data_tmp"
            ;;
        infer)
            local data_input="${1:-}"
            if [[ -z "$data_input" ]]; then
                echo '{"error":"data input required","usage":"schema.sh infer <data.json>"}' >&2
                exit 1
            fi

            local data_tmp
            data_tmp=$(mktemp)
            trap "rm -f '$data_tmp'" EXIT

            read_json "$data_input" > "$data_tmp"
            infer_schema "$data_tmp"
            ;;
        *)
            cat >&2 <<'EOF'
json_schema_validator — Validate and infer JSON schemas

Commands:
  validate <schema.json> <data.json>    Validate JSON data against a schema
  infer <data.json>                     Infer a JSON Schema from a sample

Schema supports: type, properties, required, additionalProperties, enum, const,
minimum, maximum, minLength, maxLength, minItems, maxItems, minProperties,
maxProperties, pattern, format (email, uri, date, date-time, ipv4), items

Examples:
  schema.sh validate schema.json data.json
  echo '{"name":"test"}' | schema.sh validate schema.json -
  schema.sh infer sample.json
  echo '{"x":1}' | schema.sh infer -
EOF
            exit 1
            ;;
    esac
}

main "$@"

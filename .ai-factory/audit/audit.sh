#!/bin/bash
# Security audit script for tinkoff-invest-api-v2-php
# Compares current file state against saved registry and runs pattern checks
#
# Usage:
#   ./audit.sh              — full audit (registry diff + pattern scan)
#   ./audit.sh --snapshot   — save current state as baseline (no checks)
#   ./audit.sh --diff-only  — only show changed/new files vs registry
#   ./audit.sh --scan-only  — only run pattern checks on hand-written code
#   ./audit.sh --tags       — scan ALL git tags for backdoors
#   ./audit.sh --tags 0.4.20 — scan tags starting from specified version

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REGISTRY_FILE="$SCRIPT_DIR/registry.json"
CERTS_FILE="$SCRIPT_DIR/certs-fingerprints.json"
REPORT_FILE="$SCRIPT_DIR/audit-report.txt"

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

TOTAL_FINDINGS=0

# ─── Utility ─────────────────────────────────────────────

hash_file() {
    shasum -a 256 "$1" | awk '{print $1}'
}

log_finding() {
    local severity="$1" file="$2" message="$3"
    case "$severity" in
        CRITICAL) echo -e "${RED}[CRITICAL]${NC} $file: $message" ;;
        WARNING)  echo -e "${YELLOW}[WARNING]${NC}  $file: $message" ;;
        INFO)     echo -e "${CYAN}[INFO]${NC}     $file: $message" ;;
    esac
    echo "[$severity] $file: $message" >> "$REPORT_FILE"
    TOTAL_FINDINGS=$((TOTAL_FINDINGS + 1))
}

# Grep wrapper that doesn't fail on no-match
safe_grep() {
    grep "$@" || true
}

# ─── Snapshot: save current state as baseline ────────────

do_snapshot() {
    echo -e "${CYAN}Creating baseline snapshot...${NC}"

    cd "$PROJECT_ROOT"

    # Build registry using a simple approach
    local tmp_registry
    tmp_registry=$(mktemp)

    echo "{" > "$tmp_registry"

    local first=true
    while IFS= read -r f; do
        local h
        h=$(hash_file "$f")
        if [ "$first" = true ]; then
            first=false
        else
            echo "," >> "$tmp_registry"
        fi
        printf '  "%s": "%s"' "$f" "$h" >> "$tmp_registry"
    done < <(find src examples etc library/src/docs/contracts -type f 2>/dev/null | sort)

    # Also track composer.json
    if [ -f "composer.json" ]; then
        local h
        h=$(hash_file "composer.json")
        echo "," >> "$tmp_registry"
        printf '  "%s": "%s"' "composer.json" "$h" >> "$tmp_registry"
    fi

    echo "" >> "$tmp_registry"
    echo "}" >> "$tmp_registry"
    mv "$tmp_registry" "$REGISTRY_FILE"

    # Save cert fingerprints
    echo "{" > "$CERTS_FILE"
    first=true
    for cert in etc/*.pem; do
        if [ -f "$cert" ]; then
            local h size
            h=$(hash_file "$cert")
            size=$(wc -c < "$cert" | tr -d ' ')
            if [ "$first" = true ]; then
                first=false
            else
                echo "," >> "$CERTS_FILE"
            fi
            printf '  "%s": {"sha256": "%s", "size": %s}' "$cert" "$h" "$size" >> "$CERTS_FILE"
        fi
    done
    echo "" >> "$CERTS_FILE"
    echo "}" >> "$CERTS_FILE"

    local file_count
    file_count=$(safe_grep -c ':' "$REGISTRY_FILE")
    echo -e "${GREEN}Snapshot saved.${NC}"
    echo "  Registry: $REGISTRY_FILE ($file_count files)"
    echo "  Certs:    $CERTS_FILE"
}

# ─── Diff: compare current state against registry ───────

do_diff() {
    if [ ! -f "$REGISTRY_FILE" ]; then
        echo -e "${YELLOW}No registry found. Run with --snapshot first to create baseline.${NC}"
        return 0
    fi

    echo -e "${CYAN}═══ Registry Diff ═══${NC}"

    cd "$PROJECT_ROOT"

    # Check each file in current tree
    while IFS= read -r f; do
        local current_hash saved_hash
        current_hash=$(hash_file "$f")
        saved_hash=$(safe_grep "\"$f\"" "$REGISTRY_FILE" | sed 's/.*: *"//;s/".*//')

        if [ -z "$saved_hash" ]; then
            log_finding "WARNING" "$f" "NEW FILE — not in registry"
        elif [ "$current_hash" != "$saved_hash" ]; then
            log_finding "WARNING" "$f" "MODIFIED — hash mismatch"
        fi
    done < <(find src examples etc library/src/docs/contracts -type f 2>/dev/null | sort)

    # Check composer.json
    if [ -f "composer.json" ]; then
        local current_hash saved_hash
        current_hash=$(hash_file "composer.json")
        saved_hash=$(safe_grep '"composer.json"' "$REGISTRY_FILE" | sed 's/.*: *"//;s/".*//')
        if [ -n "$saved_hash" ] && [ "$current_hash" != "$saved_hash" ]; then
            log_finding "WARNING" "composer.json" "MODIFIED — hash mismatch"
        fi
    fi

    # Check for deleted files — extract keys (file paths) from registry JSON
    safe_grep -oE '^\s*"[^"]+":' "$REGISTRY_FILE" | sed 's/.*"\([^"]*\)".*/\1/' | while IFS= read -r f; do
        if [ ! -f "$f" ]; then
            log_finding "INFO" "$f" "DELETED — was in registry"
        fi
    done

    # Check cert fingerprints
    if [ -f "$CERTS_FILE" ]; then
        for cert in etc/*.pem; do
            if [ -f "$cert" ]; then
                local current_hash saved_hash
                current_hash=$(hash_file "$cert")
                saved_hash=$(safe_grep "$cert" "$CERTS_FILE" | safe_grep -o '"sha256": *"[^"]*"' | sed 's/.*"sha256": *"//;s/"//')
                if [ -n "$saved_hash" ] && [ "$current_hash" != "$saved_hash" ]; then
                    log_finding "CRITICAL" "$cert" "SSL CERTIFICATE CHANGED"
                fi
            fi
        done
    fi

    if [ "$TOTAL_FINDINGS" -eq 0 ]; then
        echo -e "${GREEN}No changes detected vs registry.${NC}"
    fi
}

# ─── Scan: pattern-based security checks ────────────────

scan_pattern() {
    local label="$1" severity="$2" pattern="$3" target="$4" exclude="${5:-}"

    local results
    if [ -n "$exclude" ]; then
        results=$(safe_grep -rn -E "$pattern" "$target" --include='*.php' | safe_grep -v "$exclude")
    else
        results=$(safe_grep -rn -E "$pattern" "$target" --include='*.php')
    fi

    if [ -n "$results" ]; then
        while IFS= read -r line; do
            local file
            file=$(echo "$line" | cut -d: -f1)
            local content
            content=$(echo "$line" | cut -d: -f3-)
            log_finding "$severity" "$file" "$label: $content"
        done <<< "$results"
    fi
}

# Run all pattern checks against a given directory.
# Usage: scan_in_dir <dir> [label_prefix]
# The directory must contain src/ structure.
scan_in_dir() {
    local dir="$1"
    local prefix="${2:-}"

    # ── 1. Dangerous functions in hand-written code ──
    scan_pattern "${prefix}Dangerous function" "CRITICAL" \
        'eval\s*\(|exec\s*\(|system\s*\(|passthru\s*\(|proc_open\s*\(|shell_exec\s*\(|popen\s*\(|pcntl_exec\s*\(' \
        "$dir/src/" "$dir/src/models/"

    # ── 2. Obfuscation patterns ──
    scan_pattern "${prefix}Obfuscation" "CRITICAL" \
        'base64_decode\s*\(|gzinflate\s*\(|gzuncompress\s*\(|str_rot13\s*\(|convert_uudecode\s*\(' \
        "$dir/src/" "$dir/src/models/"

    # ── 3. Network calls outside gRPC ──
    scan_pattern "${prefix}Non-gRPC network" "CRITICAL" \
        "curl_init|curl_exec|file_get_contents\s*\(\s*[\"']https?://|fsockopen|stream_socket_client" \
        "$dir/src/" "$dir/src/models/"

    # ── 4. Token/credential handling ──
    local token_results
    token_results=$(safe_grep -rn -E '\$.*token|api_token|Bearer' "$dir/src/" --include='*.php' \
        | safe_grep -v 'src/models/' \
        | safe_grep -v 'ClientConnection.php' \
        | safe_grep -v 'TinkoffClientsFactory.php')
    if [ -n "$token_results" ]; then
        while IFS= read -r line; do
            local file
            file=$(echo "$line" | cut -d: -f1)
            log_finding "WARNING" "$file" "${prefix}Token reference outside expected files"
        done <<< "$token_results"
    fi

    # ── 5. Hostname validation ──
    local conn_file="$dir/src/ClientConnection.php"
    if [ -f "$conn_file" ]; then
        local hostnames
        hostnames=$(safe_grep "HOSTNAME.*=" "$conn_file" | safe_grep -oE "'[^']+'" | tr -d "'")
        if [ -n "$hostnames" ]; then
            while IFS= read -r host; do
                case "$host" in
                    invest-public-api.tbank.ru|sandbox-invest-public-api.tbank.ru|\
                    invest-public-api.tinkoff.ru|sandbox-invest-public-api.tinkoff.ru)
                        # known good (tbank.ru is current, tinkoff.ru was used in older versions)
                        ;;
                    *)
                        log_finding "CRITICAL" "$conn_file" "${prefix}UNKNOWN HOSTNAME: $host"
                        ;;
                esac
            done <<< "$hostnames"
        fi
    fi

    # ── 6. File write operations ──
    scan_pattern "${prefix}File write" "WARNING" \
        "fwrite\s*\(|file_put_contents\s*\(" \
        "$dir/src/" "$dir/src/models/"

    # ── 7. Suspicious patterns in auto-generated models ──
    if [ -d "$dir/src/models/" ]; then
        scan_pattern "${prefix}Suspicious in model" "CRITICAL" \
            'eval\s*\(|exec\s*\(|system\s*\(|curl|file_get_contents|fsockopen|base64_decode|mail\s*\(|header\s*\(' \
            "$dir/src/models/"
    fi
}

do_scan() {
    echo -e "${CYAN}═══ Pattern Security Scan ═══${NC}"

    cd "$PROJECT_ROOT"

    echo -e "\n${CYAN}[1/7] Dangerous function calls...${NC}"
    echo -e "${CYAN}[2/7] Obfuscation patterns...${NC}"
    echo -e "${CYAN}[3/7] Non-gRPC network calls...${NC}"
    echo -e "${CYAN}[4/7] Token handling audit...${NC}"
    echo -e "${CYAN}[5/7] API hostname check...${NC}"
    echo -e "${CYAN}[6/7] File write operations...${NC}"
    echo -e "${CYAN}[7/7] Suspicious code in auto-generated models...${NC}"

    scan_in_dir "$PROJECT_ROOT"

    # Print hostname summary for interactive use
    local hostnames
    hostnames=$(safe_grep "HOSTNAME.*=" src/ClientConnection.php | safe_grep -oE "'[^']+'" | tr -d "'")
    if [ -n "$hostnames" ]; then
        while IFS= read -r host; do
            case "$host" in
                invest-public-api.tbank.ru|sandbox-invest-public-api.tbank.ru|\
                invest-public-api.tinkoff.ru|sandbox-invest-public-api.tinkoff.ru|\
                invest-public-api.tinkoff.ru:443|sandbox-invest-public-api.tinkoff.ru:443)
                    echo -e "  ${GREEN}✓${NC} $host — known good"
                    ;;
            esac
        done <<< "$hostnames"
    fi

    echo ""
}

# ─── Tags: scan all git tags ────────────────────────────

do_tags() {
    local from_tag="${1:-}"

    cd "$PROJECT_ROOT"

    # Collect tags
    local all_tags
    all_tags=$(git tag --sort=version:refname)
    local tag_count
    tag_count=$(echo "$all_tags" | wc -l | tr -d ' ')

    # Filter from specified tag if given
    local tags_to_scan="$all_tags"
    if [ -n "$from_tag" ]; then
        local found=false
        local filtered=""
        while IFS= read -r t; do
            if [ "$t" = "$from_tag" ]; then
                found=true
            fi
            if [ "$found" = true ]; then
                filtered="${filtered}${t}"$'\n'
            fi
        done <<< "$all_tags"

        if [ -z "$filtered" ]; then
            echo -e "${RED}Tag '$from_tag' not found. Available tags:${NC}"
            echo "$all_tags"
            exit 1
        fi
        tags_to_scan=$(echo "$filtered" | sed '/^$/d')
        tag_count=$(echo "$tags_to_scan" | wc -l | tr -d ' ')
    fi

    echo -e "${CYAN}═══ Scanning $tag_count tags for backdoors ═══${NC}"
    echo ""

    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap "rm -rf '$tmp_dir'" EXIT

    local tags_clean=0
    local tags_dirty=0
    local current_tag_num=0

    while IFS= read -r tag; do
        current_tag_num=$((current_tag_num + 1))
        local tag_dir="$tmp_dir/$tag"
        mkdir -p "$tag_dir"

        echo -ne "${CYAN}[$current_tag_num/$tag_count]${NC} $tag ... "

        # Extract tag contents without checkout
        git archive "$tag" | tar -x -C "$tag_dir" 2>/dev/null

        if [ ! -d "$tag_dir/src" ]; then
            echo -e "${YELLOW}no src/ directory, skipped${NC}"
            continue
        fi

        # Count findings before scan
        local before=$TOTAL_FINDINGS

        scan_in_dir "$tag_dir" "[$tag] "

        local after=$TOTAL_FINDINGS
        local tag_findings=$((after - before))

        if [ "$tag_findings" -gt 0 ]; then
            echo -e "${RED}$tag_findings findings!${NC}"
            tags_dirty=$((tags_dirty + 1))
        else
            echo -e "${GREEN}clean${NC}"
            tags_clean=$((tags_clean + 1))
        fi

        # Cleanup to save disk
        rm -rf "$tag_dir"
    done <<< "$tags_to_scan"

    echo ""
    echo -e "${CYAN}═══ Tags scan complete ═══${NC}"
    echo -e "  Clean: ${GREEN}$tags_clean${NC}"
    if [ "$tags_dirty" -gt 0 ]; then
        echo -e "  Dirty: ${RED}$tags_dirty${NC}"
    else
        echo -e "  Dirty: ${GREEN}0${NC}"
    fi
    echo ""
}

# ─── Main ────────────────────────────────────────────────

> "$REPORT_FILE"  # clear report

case "${1:-full}" in
    --snapshot)
        do_snapshot
        ;;
    --diff-only)
        do_diff
        ;;
    --scan-only)
        do_scan
        ;;
    --tags)
        do_tags "${2:-}"
        ;;
    full|"")
        do_diff
        echo ""
        do_scan
        ;;
    *)
        echo "Usage: $0 [--snapshot|--diff-only|--scan-only|--tags [from_version]]"
        exit 1
        ;;
esac

if [ -s "$REPORT_FILE" ]; then
    local_findings=$(wc -l < "$REPORT_FILE" | tr -d ' ')
    local_critical=$(safe_grep -c '^\[CRITICAL\]' "$REPORT_FILE")
    echo -e "${YELLOW}═══ Summary: $local_findings findings ($local_critical critical) ═══${NC}"
    echo "Full report: $REPORT_FILE"
    exit 1
else
    echo -e "${GREEN}═══ Audit passed — no findings ═══${NC}"
    exit 0
fi

#!/bin/bash
#
# Blobnode Stripe Repair Metrics Collector
#
# Collects blobstore_blobnode_stripe_repair_count and stripe_repair_bytes
# from a list of blobnodes for LRC repair verification.
#
# Why this script instead of Grafana:
# 1. 测试环境监控覆盖不完整：多 AZ 部署下，Grafana/Prometheus 的 scrape 配置
#    无法覆盖所有 AZ 的 blobnode 服务，面板数据不完整，无法作为可靠的验证依据。
# 2. 操作验证的即时性：脚本通过一键式 before/after 快照对比，直接给出 LRC
#    修复路径的判定结论，避免人工在 Grafana 面板上跨节点手动核算 delta。
#
# Usage:
#   # Take a snapshot before repair
#   $0 snapshot hosts.txt before.snap
#
#   # ... run repair tasks ...
#
#   # Take a snapshot after repair
#   $0 snapshot hosts.txt after.snap
#
#   # Compare two snapshots to see delta
#   $0 diff before.snap after.snap
#
#   # Or do snapshot-before, run a command, snapshot-after, then diff
#   $0 watch hosts.txt -- <your repair command>
#
# Host file format (one per line, ip:port):
#   10.0.0.1:8899
#   10.0.0.2:8899
#   10.0.0.3:8899

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

CURL_TIMEOUT=10

# ============================================================================
# Helpers
# ============================================================================

die() {
    echo -e "${RED}ERROR: $*${NC}" >&2
    exit 1
}

info() {
    echo -e "${BLUE}INFO:${NC} $*" >&2
}

warn() {
    echo -e "${YELLOW}WARN:${NC} $*" >&2
}

usage() {
    cat <<'EOF'
Usage:
  blobnode-repair-metrics.sh snapshot <hosts_file> <output_file>
  blobnode-repair-metrics.sh diff     <before_file> <after_file>
  blobnode-repair-metrics.sh watch    <hosts_file> [--] <command> [args...]
  blobnode-repair-metrics.sh discover <cm_addr> <output_file>

Subcommands:
  snapshot  Collect current metrics from all blobnodes and save to file
  diff      Compare two snapshot files, show per-node delta and totals
  watch     Take snapshot, run command, take snapshot again, show diff
  discover  Discover all blobnode hosts from cluster manager and save to file

Host file format (one per line):
  10.0.0.1:8899
  10.0.0.2:8899

Options:
  -t, --timeout SEC   curl timeout in seconds (default: 10)
  -h, --help          Show this help

Examples:
  # Auto-discover blobnode hosts from cluster manager
  blobnode-repair-metrics.sh discover http://cm:9999 hosts.txt

  # Before/after workflow
  blobnode-repair-metrics.sh snapshot hosts.txt before.snap
  # ... run your repair tasks ...
  blobnode-repair-metrics.sh snapshot hosts.txt after.snap
  blobnode-repair-metrics.sh diff before.snap after.snap

  # All-in-one: snapshot, run command, snapshot, diff
  blobnode-repair-metrics.sh watch hosts.txt -- send_repair_msg 100 500 "0 3"
EOF
    exit 0
}

# ============================================================================
# Metric Collection
# ============================================================================

# Query a single blobnode and extract the 4 metric values
# Output: host count_local count_global bytes_local bytes_global
query_blobnode() {
    local host="$1"
    local url

    # Add http:// prefix if not present
    if [[ "$host" != http://* && "$host" != https://* ]]; then
        url="http://${host}/metrics"
    else
        url="${host}/metrics"
    fi

    local metrics
    metrics=$(curl -sS --connect-timeout "$CURL_TIMEOUT" --max-time "$CURL_TIMEOUT" "$url" 2>/dev/null) || {
        echo "$host -1 -1 -1 -1"
        return
    }

    local count_local count_global bytes_local bytes_global

    # Use || true to prevent exit on no match (grep returns 1 when no match found)
    # Use printf "%.0f" to convert scientific notation (e.g. 6.07e+11) to plain integers
    count_local=$(echo "$metrics" \
        | grep '^blobstore_blobnode_stripe_repair_count{' \
        | grep 'type="local"' \
        | awk '{printf "%.0f\n", $NF}' || true)
    count_local=${count_local:-0}

    count_global=$(echo "$metrics" \
        | grep '^blobstore_blobnode_stripe_repair_count{' \
        | grep 'type="global"' \
        | awk '{printf "%.0f\n", $NF}' || true)
    count_global=${count_global:-0}

    bytes_local=$(echo "$metrics" \
        | grep '^blobstore_blobnode_stripe_repair_bytes{' \
        | grep 'type="local"' \
        | awk '{printf "%.0f\n", $NF}' || true)
    bytes_local=${bytes_local:-0}

    bytes_global=$(echo "$metrics" \
        | grep '^blobstore_blobnode_stripe_repair_bytes{' \
        | grep 'type="global"' \
        | awk '{printf "%.0f\n", $NF}' || true)
    bytes_global=${bytes_global:-0}

    echo "$host $count_local $count_global $bytes_local $bytes_global"
}

# Convert scientific notation (e.g. 6.07e+11) or float to plain integer
# Falls back to 0 for empty or non-numeric input
sci_to_int() {
    local val="$1"
    [[ -z "$val" || "$val" == "0" ]] && echo 0 && return
    awk "BEGIN { printf \"%.0f\n\", $val + 0 }" 2>/dev/null || echo 0
}

# Format bytes to human-readable with sign prefix (B/KB/MB/GB/TB)
fmt_bytes() {
    local val="$1"
    awk "BEGIN {
        v = $val + 0
        if (v > 0) sign = \"+\"
        else if (v < 0) { sign = \"-\"; v = -v }
        else { sign = \" \"; v = 0 }
        if      (v >= 1099511627776) printf \"%s%.1fT\", sign, v/1099511627776
        else if (v >= 1073741824)    printf \"%s%.1fG\", sign, v/1073741824
        else if (v >= 1048576)       printf \"%s%.1fM\", sign, v/1048576
        else if (v >= 1024)          printf \"%s%.1fK\", sign, v/1024
        else                         printf \"%s%.0fB\", sign, v
    }"
}

# Read host file (skip blank lines and comments)
read_hosts() {
    local file="$1"
    [[ -f "$file" ]] || die "host file not found: $file"
    # Use || true to prevent exit when grep finds no matches
    grep -v '^\s*#' "$file" | grep -v '^\s*$' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true
}

# ============================================================================
# Snapshot
# ============================================================================

cmd_snapshot() {
    local hosts_file="$1"
    local output_file="$2"

    info "Collecting metrics from $(read_hosts "$hosts_file" | wc -l) blobnodes..."

    local tmpfile
    tmpfile=$(mktemp)
    # Use eval to safely capture tmpfile at trap setup time
    # shellcheck disable=SC2064
    trap "rm -f '$tmpfile'" EXIT

    # Header
    {
        echo "# blobnode stripe repair metrics snapshot"
        echo "# timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        echo "# source: $hosts_file"
        echo "# host count_local count_global bytes_local bytes_global"
    } > "$tmpfile"

    local total=0 ok=0 fail=0

    while IFS= read -r host; do
        [[ -z "$host" ]] && continue
        total=$((total + 1))

        local result
        result=$(query_blobnode "$host")

        local h cl cg bl bg
        read -r h cl cg bl bg <<< "$result"

        if [[ "$cl" == "-1" ]]; then
            warn "Failed to query $host"
            fail=$((fail + 1))
            echo "# FAILED $host" >> "$tmpfile"
        else
            ok=$((ok + 1))
            echo "$h $cl $cg $bl $bg" >> "$tmpfile"
        fi
    done < <(read_hosts "$hosts_file")

    mv "$tmpfile" "$output_file"
    trap - EXIT

    info "Snapshot saved to $output_file (${ok}/${total} succeeded, ${fail} failed)"
}

# ============================================================================
# Diff
# ============================================================================

cmd_diff() {
    local before_file="$1"
    local after_file="$2"

    [[ -f "$before_file" ]] || die "before file not found: $before_file"
    [[ -f "$after_file" ]] || die "after file not found: $after_file"

    # Extract timestamps
    local ts_before ts_after
    ts_before=$(grep '^# timestamp:' "$before_file" | awk '{print $3}')
    ts_after=$(grep '^# timestamp:' "$after_file" | awk '{print $3}')

    echo ""
    echo -e "${BOLD}=== Stripe Repair Metrics Diff ===${NC}"
    echo -e "  Before: ${ts_before:-unknown}"
    echo -e "  After:  ${ts_after:-unknown}"
    echo ""

    # Table header
    printf "${BOLD}%-30s  %10s %10s %10s  %10s %10s %10s${NC}\n" \
        "Host" "CntLocal" "CntGlobal" "CntTotal" "BytLocal" "BytGlobal" "BytTotal"
    printf "%-30s  %10s %10s %10s  %10s %10s %10s\n" \
        "------------------------------" "----------" "----------" "----------" \
        "----------" "----------" "----------"

    # Read before snapshot into associative array
    declare -A before_cl before_cg before_bl before_bg
    while IFS= read -r line; do
        [[ "$line" =~ ^# ]] && continue
        [[ -z "$line" ]] && continue
        local h cl cg bl bg
        read -r h cl cg bl bg <<< "$line"
        before_cl[$h]=$(sci_to_int "$cl")
        before_cg[$h]=$(sci_to_int "$cg")
        before_bl[$h]=$(sci_to_int "$bl")
        before_bg[$h]=$(sci_to_int "$bg")
    done < "$before_file"

    # Process after snapshot
    declare -A after_cl after_cg after_bl after_bg
    declare -A all_hosts

    while IFS= read -r line; do
        [[ "$line" =~ ^# ]] && continue
        [[ -z "$line" ]] && continue
        local h cl cg bl bg
        read -r h cl cg bl bg <<< "$line"
        after_cl[$h]=$(sci_to_int "$cl")
        after_cg[$h]=$(sci_to_int "$cg")
        after_bl[$h]=$(sci_to_int "$bl")
        after_bg[$h]=$(sci_to_int "$bg")
        all_hosts[$h]=1
    done < "$after_file"

    # Also add hosts only in before
    for h in "${!before_cl[@]}"; do
        all_hosts[$h]=1
    done

    local sum_dcl=0 sum_dcg=0 sum_dbl=0 sum_dbg=0
    local sum_dcl_abs=0 sum_dcg_abs=0
    local node_count=0

    # Sort hosts and iterate
    for h in $(echo "${!all_hosts[@]}" | tr ' ' '\n' | sort); do
        local b_cl=${before_cl[$h]:-0}
        local b_cg=${before_cg[$h]:-0}
        local b_bl=${before_bl[$h]:-0}
        local b_bg=${before_bg[$h]:-0}
        local a_cl=${after_cl[$h]:-0}
        local a_cg=${after_cg[$h]:-0}
        local a_bl=${after_bl[$h]:-0}
        local a_bg=${after_bg[$h]:-0}

        local d_cl=$((a_cl - b_cl))
        local d_cg=$((a_cg - b_cg))
        local d_bl=$((a_bl - b_bl))
        local d_bg=$((a_bg - b_bg))
        local d_total=$((d_cl + d_cg))

        sum_dcl=$((sum_dcl + d_cl))
        sum_dcg=$((sum_dcg + d_cg))
        sum_dbl=$((sum_dbl + d_bl))
        sum_dbg=$((sum_dbg + d_bg))
        sum_dcl_abs=$((sum_dcl_abs + d_cl))
        sum_dcg_abs=$((sum_dcg_abs + d_cg))
        node_count=$((node_count + 1))

        # Shorten host for display
        local display_host="$h"
        if [[ ${#display_host} -gt 30 ]]; then
            display_host="...${display_host: -27}"
        fi

        # Color the delta
        local color_nc=""
        if [[ $d_total -gt 0 ]]; then
            color_nc="${GREEN}"
        elif [[ $d_total -lt 0 ]]; then
            color_nc="${RED}"
        fi

        local f_bl f_bg f_bt
        f_bl=$(fmt_bytes "$d_bl")
        f_bg=$(fmt_bytes "$d_bg")
        f_bt=$(fmt_bytes "$((d_bl + d_bg))")

        printf "%-30s  ${color_nc}%+10d %+10d %+10d${NC}  ${color_nc}%10s %10s %10s${NC}\n" \
            "$display_host" "$d_cl" "$d_cg" "$d_total" "$f_bl" "$f_bg" "$f_bt"
    done

    # Separator
    printf "%-30s  %10s %10s %10s  %10s %10s %10s\n" \
        "------------------------------" "----------" "----------" "----------" \
        "----------" "----------" "----------"

    # Totals
    local f_sum_bl f_sum_bg f_sum_bt
    f_sum_bl=$(fmt_bytes "$sum_dbl")
    f_sum_bg=$(fmt_bytes "$sum_dbg")
    f_sum_bt=$(fmt_bytes "$((sum_dbl + sum_dbg))")

    printf "${BOLD}%-30s  ${GREEN}%+10d %+10d %+10d${NC}  ${GREEN}%10s %10s %10s${NC}\n" \
        "TOTAL ($node_count nodes)" \
        "$sum_dcl" "$sum_dcg" "$((sum_dcl + sum_dcg))" \
        "$f_sum_bl" "$f_sum_bg" "$f_sum_bt"

    echo ""

    # Summary for LRC verification
    echo -e "${BOLD}=== LRC Verification Summary ===${NC}"
    echo ""

    local local_ratio=""
    local total_repair=$((sum_dcl_abs + sum_dcg_abs))
    if [[ $total_repair -gt 0 ]]; then
        local_ratio=$(awk "BEGIN { printf \"%.1f\", $sum_dcl_abs * 100.0 / $total_repair }")
    fi

    printf "  %-25s %s\n" "Local repairs (LRC):" "$sum_dcl_abs"
    printf "  %-25s %s\n" "Global repairs:" "$sum_dcg_abs"
    printf "  %-25s %s\n" "Total repairs:" "$total_repair"
    if [[ -n "$local_ratio" ]]; then
        printf "  %-25s %s%%\n" "Local repair ratio:" "$local_ratio"
    fi

    echo ""

    # Verdict
    if [[ $total_repair -eq 0 ]]; then
        echo -e "  ${YELLOW}⚠ No repair activity detected${NC}"
    elif [[ $sum_dcl_abs -gt 0 && $sum_dcg_abs -eq 0 ]]; then
        echo -e "  ${GREEN}✓ All repairs used local (LRC) path${NC}"
    elif [[ $sum_dcl_abs -gt $sum_dcg_abs ]]; then
        echo -e "  ${GREEN}✓ LRC is effective: majority of repairs used local path${NC}"
    elif [[ $sum_dcl_abs -gt 0 ]]; then
        echo -e "  ${YELLOW}⚠ Mixed: some local repairs, but global repairs are more frequent${NC}"
    else
        echo -e "  ${RED}✗ No local repairs detected, all repairs used global path${NC}"
    fi
    echo ""
}

# ============================================================================
# Watch (snapshot + command + snapshot + diff)
# ============================================================================

cmd_watch() {
    local hosts_file="$1"
    shift
    # Remove leading "--" if present
    [[ "${1:-}" == "--" ]] && shift

    if [[ $# -eq 0 ]]; then
        die "watch requires a command to run"
    fi

    local before_tmp after_tmp
    before_tmp=$(mktemp /tmp/repair-metrics-before.XXXXXX)
    after_tmp=$(mktemp /tmp/repair-metrics-after.XXXXXX)
    # Use eval to safely capture variables at trap setup time
    # shellcheck disable=SC2064
    trap "rm -f '$before_tmp' '$after_tmp'" EXIT

    info "Taking BEFORE snapshot..."
    cmd_snapshot "$hosts_file" "$before_tmp"

    echo ""
    info "Running command: $*"
    echo -e "${BOLD}────────────────────────────────────────────────${NC}"
    "$@"
    local cmd_rc=$?
    echo -e "${BOLD}────────────────────────────────────────────────${NC}"

    if [[ $cmd_rc -ne 0 ]]; then
        warn "Command exited with code $cmd_rc"
    fi

    echo ""
    info "Taking AFTER snapshot..."
    cmd_snapshot "$hosts_file" "$after_tmp"

    cmd_diff "$before_tmp" "$after_tmp"

    rm -f "$before_tmp" "$after_tmp"
    trap - EXIT

    return $cmd_rc
}

# ============================================================================
# Discover blobnode hosts from cluster manager
# ============================================================================

cmd_discover() {
    local cm_addr="$1"
    local output_file="$2"

    info "Discovering blobnode hosts from $cm_addr..."

    # Query cluster manager for all blobnode services
    local url="${cm_addr}/service/get?name=BLOBNODE"
    local response
    response=$(curl -sS --connect-timeout "$CURL_TIMEOUT" --max-time "$CURL_TIMEOUT" "$url" 2>/dev/null) || {
        die "Failed to query $url"
    }

    # Parse JSON to extract host addresses
    local hosts
    if ! hosts=$(echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    nodes = data.get('nodes', [])
    for node in nodes:
        host = node.get('host', '')
        if host:
            # Remove http:// prefix if present for consistency
            if host.startswith('http://'):
                host = host[7:]
            elif host.startswith('https://'):
                host = host[8:]
            print(host)
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" 2>&1); then
        die "Failed to parse response: $hosts"
    fi

    if [[ -z "$hosts" ]]; then
        die "No blobnode hosts found from $cm_addr"
    fi

    # Write to output file
    {
        echo "# Blobnode hosts discovered from $cm_addr"
        echo "# timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        echo "# count: $(echo "$hosts" | wc -l)"
        echo "$hosts" | sort -u
    } > "$output_file"

    local count
    count=$(echo "$hosts" | sort -u | wc -l)
    info "Discovered $count blobnode host(s), saved to $output_file"
}

# ============================================================================
# Main
# ============================================================================

main() {
    # Parse global options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t|--timeout)
                [[ $# -ge 2 ]] || die "$1 requires an argument"
                CURL_TIMEOUT="$2"
                shift 2
                ;;
            -h|--help|help)
                usage
                ;;
            -*)
                die "Unknown option: $1"
                ;;
            *)
                break
                ;;
        esac
    done

    if [[ $# -eq 0 ]]; then
        usage
    fi

    local subcmd="$1"
    shift

    case "$subcmd" in
        snapshot)
            [[ $# -ge 2 ]] || die "snapshot requires <hosts_file> <output_file>"
            cmd_snapshot "$1" "$2"
            ;;
        diff)
            [[ $# -ge 2 ]] || die "diff requires <before_file> <after_file>"
            cmd_diff "$1" "$2"
            ;;
        watch)
            [[ $# -ge 2 ]] || die "watch requires <hosts_file> [--] <command> [args...]"
            cmd_watch "$@"
            ;;
        discover)
            [[ $# -ge 2 ]] || die "discover requires <cm_addr> <output_file>"
            cmd_discover "$1" "$2"
            ;;
        -h|--help|help)
            usage
            ;;
        *)
            die "Unknown subcommand: $subcmd\nRun '$0 --help' for usage"
            ;;
    esac
}

main "$@"

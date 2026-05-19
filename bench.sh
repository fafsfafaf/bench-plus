#!/usr/bin/env bash
#
# bench-plus — improved server benchmark
# Tests: system info, CPU, RAM, disk I/O, network speed, GeekBench-style summary
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/fafsfafaf/bench-plus/master/bench.sh | bash
#   bash bench.sh                  # full run
#   bash bench.sh --quick          # skip network speed tests
#   bash bench.sh --json out.json  # also write JSON report
#   bash bench.sh --no-net         # skip all network tests
#

set -u
LC_ALL=C
export LC_ALL

VERSION="1.0.0"
START_TS=$(date +%s)

# ---------- colors ----------
if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    C_RESET="$(tput sgr0)"; C_BOLD="$(tput bold)"
    C_RED="$(tput setaf 1)"; C_GREEN="$(tput setaf 2)"
    C_YELLOW="$(tput setaf 3)"; C_BLUE="$(tput setaf 4)"
    C_MAGENTA="$(tput setaf 5)"; C_CYAN="$(tput setaf 6)"
else
    C_RESET=""; C_BOLD=""; C_RED=""; C_GREEN=""
    C_YELLOW=""; C_BLUE=""; C_MAGENTA=""; C_CYAN=""
fi

# ---------- args ----------
QUICK=0
NO_NET=0
JSON_OUT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --quick) QUICK=1 ;;
        --no-net) NO_NET=1 ;;
        --json) JSON_OUT="${2:-bench.json}"; shift ;;
        -h|--help)
            sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
    shift
done

# ---------- helpers ----------
hr()      { printf '%s\n' "${C_BLUE}────────────────────────────────────────────────────────────────${C_RESET}"; }
section() { printf '\n%s%s %s%s\n' "$C_BOLD" "$C_CYAN" "$1" "$C_RESET"; hr; }
kv()      { printf '  %-22s %s\n' "${C_BOLD}$1${C_RESET}" "$2"; }
ok()      { printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$1"; }
warn()    { printf '  %s!%s %s\n' "$C_YELLOW" "$C_RESET" "$1"; }
err()     { printf '  %s✗%s %s\n' "$C_RED" "$C_RESET" "$1" >&2; }

need_root_for() {
    if [ "$(id -u)" -ne 0 ]; then
        warn "Not root — $1 may be limited"
        return 1
    fi
    return 0
}

human_bytes() {
    awk -v b="$1" 'BEGIN{
        s="B KB MB GB TB PB"; split(s,a," "); i=1;
        while (b>=1024 && i<6){b/=1024;i++}
        printf "%.2f %s", b, a[i];
    }'
}

# Track JSON pairs
JSON_PAIRS=()
j_set() { JSON_PAIRS+=("\"$1\": $2"); }
j_str() { JSON_PAIRS+=("\"$1\": \"$(printf '%s' "$2" | sed 's/\\/\\\\/g; s/"/\\"/g')\""); }

# ---------- banner ----------
printf '\n'
printf '%s╔════════════════════════════════════════════════════════════╗%s\n' "$C_MAGENTA" "$C_RESET"
printf '%s║%s  %sbench-plus v%s%s  —  improved server benchmark            %s║%s\n' "$C_MAGENTA" "$C_RESET" "$C_BOLD" "$VERSION" "$C_RESET" "$C_MAGENTA" "$C_RESET"
printf '%s╚════════════════════════════════════════════════════════════╝%s\n' "$C_MAGENTA" "$C_RESET"

# ============================================================
# 1. SYSTEM INFO
# ============================================================
section "System Information"

OS_NAME="$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || uname -s)"
KERNEL="$(uname -r)"
ARCH="$(uname -m)"
HOSTNAME="$(hostname 2>/dev/null || echo unknown)"
UPTIME="$(uptime -p 2>/dev/null || awk '{print int($1/86400)"d "int($1%86400/3600)"h"}' /proc/uptime)"

CPU_MODEL="$(awk -F: '/model name/{print $2; exit}' /proc/cpuinfo 2>/dev/null | sed 's/^ *//' || echo unknown)"
CPU_CORES="$(nproc 2>/dev/null || echo unknown)"
CPU_FREQ="$(awk -F: '/cpu MHz/{print $2; exit}' /proc/cpuinfo 2>/dev/null | sed 's/^ *//' | awk '{printf "%.0f MHz", $1}')"
CPU_CACHE="$(awk -F: '/cache size/{print $2; exit}' /proc/cpuinfo 2>/dev/null | sed 's/^ *//' || echo unknown)"

VIRT="$(systemd-detect-virt 2>/dev/null || echo none)"

MEM_TOTAL_KB=$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null || echo 0)
MEM_AVAIL_KB=$(awk '/MemAvailable/{print $2}' /proc/meminfo 2>/dev/null || echo 0)
SWAP_TOTAL_KB=$(awk '/SwapTotal/{print $2}' /proc/meminfo 2>/dev/null || echo 0)

DISK_TOTAL=$(df -B1 --total --exclude-type=tmpfs --exclude-type=devtmpfs --exclude-type=overlay 2>/dev/null | awk '/^total/{print $2}')
DISK_USED=$(df -B1 --total --exclude-type=tmpfs --exclude-type=devtmpfs --exclude-type=overlay 2>/dev/null | awk '/^total/{print $3}')

kv "Hostname"     "$HOSTNAME"
kv "OS"           "$OS_NAME"
kv "Kernel"       "$KERNEL ($ARCH)"
kv "Uptime"       "$UPTIME"
kv "Virtualization" "$VIRT"
kv "CPU Model"    "$CPU_MODEL"
kv "CPU Cores"    "$CPU_CORES @ $CPU_FREQ"
kv "CPU Cache"    "$CPU_CACHE"
kv "Memory"       "$(human_bytes $((MEM_TOTAL_KB*1024))) total / $(human_bytes $((MEM_AVAIL_KB*1024))) available"
kv "Swap"         "$(human_bytes $((SWAP_TOTAL_KB*1024)))"
kv "Disk"         "$(human_bytes "${DISK_USED:-0}") used / $(human_bytes "${DISK_TOTAL:-0}") total"

j_str os "$OS_NAME"
j_str kernel "$KERNEL"
j_str arch "$ARCH"
j_str hostname "$HOSTNAME"
j_str virtualization "$VIRT"
j_str cpu_model "$CPU_MODEL"
j_set cpu_cores "$CPU_CORES"
j_set mem_total_bytes "$((MEM_TOTAL_KB*1024))"
j_set disk_total_bytes "${DISK_TOTAL:-0}"

# ============================================================
# 2. CPU BENCHMARK
# ============================================================
section "CPU Benchmark"

if command -v sysbench >/dev/null 2>&1; then
    printf '  Running sysbench (single-thread, 10s)…\n'
    SB_SINGLE=$(sysbench cpu --threads=1 --time=10 --cpu-max-prime=20000 run 2>/dev/null \
        | awk '/events per second/{print $4}')
    [ -n "$SB_SINGLE" ] && ok "Single-thread: ${C_BOLD}$SB_SINGLE${C_RESET} events/s" || warn "sysbench single failed"

    printf '  Running sysbench (multi-thread, 10s)…\n'
    SB_MULTI=$(sysbench cpu --threads="$CPU_CORES" --time=10 --cpu-max-prime=20000 run 2>/dev/null \
        | awk '/events per second/{print $4}')
    [ -n "$SB_MULTI" ] && ok "Multi-thread:  ${C_BOLD}$SB_MULTI${C_RESET} events/s ($CPU_CORES threads)" || warn "sysbench multi failed"

    j_set cpu_single_thread_eps "${SB_SINGLE:-0}"
    j_set cpu_multi_thread_eps "${SB_MULTI:-0}"
else
    # Fallback: openssl speed
    if command -v openssl >/dev/null 2>&1; then
        printf '  sysbench not found, falling back to openssl speed…\n'
        OSSL=$(openssl speed -seconds 3 -bytes 1024 sha256 2>/dev/null | awk '/^sha256/{print $7}')
        [ -n "$OSSL" ] && ok "OpenSSL SHA-256: ${C_BOLD}$OSSL${C_RESET} (1k block, k/s)" || warn "openssl failed"
        j_set openssl_sha256_kps "${OSSL:-0}"
    else
        warn "Neither sysbench nor openssl available — install one for CPU benchmark"
    fi
fi

# ============================================================
# 3. MEMORY BENCHMARK
# ============================================================
section "Memory Benchmark"

if command -v sysbench >/dev/null 2>&1; then
    printf '  Running sysbench memory read/write (5s each)…\n'
    MEM_READ=$(sysbench memory --memory-oper=read --memory-total-size=10G --time=5 run 2>/dev/null \
        | awk '/transferred/{print $4, $5}' | tr -d '()')
    MEM_WRITE=$(sysbench memory --memory-oper=write --memory-total-size=10G --time=5 run 2>/dev/null \
        | awk '/transferred/{print $4, $5}' | tr -d '()')
    [ -n "$MEM_READ" ] && ok "Memory read:  ${C_BOLD}$MEM_READ${C_RESET}" || warn "memory read failed"
    [ -n "$MEM_WRITE" ] && ok "Memory write: ${C_BOLD}$MEM_WRITE${C_RESET}" || warn "memory write failed"
    j_str mem_read "$MEM_READ"
    j_str mem_write "$MEM_WRITE"
else
    warn "sysbench not installed — skipping memory test"
fi

# ============================================================
# 4. DISK I/O
# ============================================================
section "Disk I/O"

TMPFILE="$(mktemp -p "${TMPDIR:-/tmp}" benchplus.XXXXXX)"
trap 'rm -f "$TMPFILE"' EXIT INT TERM

if command -v fio >/dev/null 2>&1; then
    printf '  Running fio (4k random, 30s)…\n'
    FIO_OUT=$(fio --name=randrw --filename="$TMPFILE" --size=512M --rw=randrw --rwmixread=70 \
        --bs=4k --ioengine=libaio --iodepth=64 --runtime=20 --time_based --group_reporting \
        --output-format=terse 2>/dev/null | head -1)
    if [ -n "$FIO_OUT" ]; then
        # fio terse format: groups separated by ;
        FIO_R_IOPS=$(echo "$FIO_OUT" | awk -F';' '{print $8}')
        FIO_W_IOPS=$(echo "$FIO_OUT" | awk -F';' '{print $49}')
        FIO_R_BW=$(echo "$FIO_OUT" | awk -F';' '{print $7}')
        FIO_W_BW=$(echo "$FIO_OUT" | awk -F';' '{print $48}')
        ok "Random read:  ${C_BOLD}${FIO_R_IOPS} IOPS${C_RESET} (${FIO_R_BW} KB/s)"
        ok "Random write: ${C_BOLD}${FIO_W_IOPS} IOPS${C_RESET} (${FIO_W_BW} KB/s)"
        j_set fio_read_iops "${FIO_R_IOPS:-0}"
        j_set fio_write_iops "${FIO_W_IOPS:-0}"
    else
        warn "fio failed"
    fi
else
    printf '  fio not found, falling back to dd…\n'
    # dd write test
    DD_WRITE=$(dd if=/dev/zero of="$TMPFILE" bs=1M count=512 oflag=direct 2>&1 \
        | awk -F, '/copied/{gsub(/^ +/,"",$NF); print $NF}')
    [ -z "$DD_WRITE" ] && DD_WRITE=$(dd if=/dev/zero of="$TMPFILE" bs=1M count=512 2>&1 \
        | awk -F, '/copied|bytes/{gsub(/^ +/,"",$NF); print $NF}')
    ok "Sequential write (dd 512MB): ${C_BOLD}${DD_WRITE:-n/a}${C_RESET}"

    # dd read test (drop caches if possible)
    if [ "$(id -u)" -eq 0 ] && [ -w /proc/sys/vm/drop_caches ]; then
        sync; echo 3 > /proc/sys/vm/drop_caches
    fi
    DD_READ=$(dd if="$TMPFILE" of=/dev/null bs=1M 2>&1 \
        | awk -F, '/copied|bytes/{gsub(/^ +/,"",$NF); print $NF}')
    ok "Sequential read  (dd 512MB): ${C_BOLD}${DD_READ:-n/a}${C_RESET}"

    j_str dd_write "$DD_WRITE"
    j_str dd_read "$DD_READ"
fi

rm -f "$TMPFILE"

# ============================================================
# 5. NETWORK
# ============================================================
if [ "$NO_NET" -eq 0 ]; then
    section "Network"

    # Public IP + ASN
    PUB_IP4=$(curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null || echo "")
    PUB_IP6=$(curl -fsS --max-time 5 https://api6.ipify.org 2>/dev/null || echo "")
    ASN_INFO=$(curl -fsS --max-time 5 "https://ipinfo.io/${PUB_IP4}/json" 2>/dev/null || echo "{}")
    ASN_ORG=$(echo "$ASN_INFO" | grep -oE '"org":[^,]*' | sed 's/"org":"//; s/"//g')
    ASN_LOC=$(echo "$ASN_INFO" | grep -oE '"city":[^,]*|"country":[^,]*' | sed 's/"[a-z]*"://; s/"//g' | paste -sd', ')

    kv "Public IPv4"  "${PUB_IP4:-n/a}"
    kv "Public IPv6"  "${PUB_IP6:-n/a}"
    kv "ASN / Org"    "${ASN_ORG:-n/a}"
    kv "Location"     "${ASN_LOC:-n/a}"

    j_str public_ip4 "$PUB_IP4"
    j_str asn_org "$ASN_ORG"
    j_str location "$ASN_LOC"

    if [ "$QUICK" -eq 0 ]; then
        # Latency probes
        printf '\n  %sLatency:%s\n' "$C_BOLD" "$C_RESET"
        for target in "1.1.1.1:Cloudflare" "8.8.8.8:Google" "9.9.9.9:Quad9"; do
            host="${target%%:*}"; name="${target##*:}"
            rtt=$(ping -c 3 -W 2 "$host" 2>/dev/null | awk -F'/' '/^rtt/||/^round-trip/{print $5}')
            printf '    %-20s %s%s ms%s\n' "$name ($host)" "$C_GREEN" "${rtt:-timeout}" "$C_RESET"
        done

        # Speedtest
        printf '\n  %sSpeedtest:%s\n' "$C_BOLD" "$C_RESET"
        if command -v speedtest-cli >/dev/null 2>&1 || command -v speedtest >/dev/null 2>&1; then
            ST_BIN=$(command -v speedtest-cli || command -v speedtest)
            ST_OUT=$("$ST_BIN" --simple 2>/dev/null || true)
            if [ -n "$ST_OUT" ]; then
                echo "$ST_OUT" | sed 's/^/    /'
            else
                warn "speedtest failed"
            fi
        else
            warn "speedtest-cli not installed — skip with --quick or install it"
        fi
    else
        warn "Quick mode: skipping latency + speedtest"
    fi
else
    section "Network"
    warn "Network tests disabled (--no-net)"
fi

# ============================================================
# 6. SUMMARY
# ============================================================
END_TS=$(date +%s)
ELAPSED=$((END_TS - START_TS))

section "Summary"
kv "Elapsed"    "${ELAPSED}s"
kv "Finished"   "$(date '+%Y-%m-%d %H:%M:%S %Z')"
printf '\n  %sFor a fair comparison, run as root and ensure the system is idle.%s\n\n' "$C_YELLOW" "$C_RESET"

# ---------- JSON output ----------
if [ -n "$JSON_OUT" ]; then
    j_set elapsed_seconds "$ELAPSED"
    j_str version "$VERSION"
    j_str finished_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    {
        printf '{\n'
        for i in "${!JSON_PAIRS[@]}"; do
            sep=','
            [ "$i" -eq $((${#JSON_PAIRS[@]} - 1)) ] && sep=''
            printf '  %s%s\n' "${JSON_PAIRS[$i]}" "$sep"
        done
        printf '}\n'
    } > "$JSON_OUT"
    ok "JSON report written to $JSON_OUT"
fi

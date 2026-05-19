#!/usr/bin/env bash
#
# bench-plus — improved server benchmark (v2.0.0)
# Tests: system info, CPU, RAM, disk I/O, network, GPU, sensors,
#        compression, DNS, crypto, container detection, HTML/JSON reports
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/fafsfafaf/bench-plus/master/bench.sh | bash
#   bash bench.sh                  # full run
#   bash bench.sh --quick          # skip slow network speedtests
#   bash bench.sh --no-net         # skip network entirely
#   bash bench.sh --json out.json  # write JSON report
#   bash bench.sh --html out.html  # write HTML report
#   bash bench.sh --score          # show summary score only
#   bash bench.sh --share          # upload result to bashupload.com
#

set -u
LC_ALL=C
export LC_ALL

VERSION="2.0.0"
START_TS=$(date +%s)
SCORE_TOTAL=0
SCORE_PARTS=()

# ---------- colors ----------
if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    C_RESET="$(tput sgr0)"; C_BOLD="$(tput bold)"; C_DIM="$(tput dim)"
    C_RED="$(tput setaf 1)"; C_GREEN="$(tput setaf 2)"
    C_YELLOW="$(tput setaf 3)"; C_BLUE="$(tput setaf 4)"
    C_MAGENTA="$(tput setaf 5)"; C_CYAN="$(tput setaf 6)"; C_GRAY="$(tput setaf 7)"
else
    C_RESET=""; C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""
    C_YELLOW=""; C_BLUE=""; C_MAGENTA=""; C_CYAN=""; C_GRAY=""
fi

# ---------- args ----------
QUICK=0
NO_NET=0
JSON_OUT=""
HTML_OUT=""
SCORE_ONLY=0
SHARE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --quick)      QUICK=1 ;;
        --no-net)     NO_NET=1 ;;
        --json)       JSON_OUT="${2:-bench.json}"; shift ;;
        --html)       HTML_OUT="${2:-bench.html}"; shift ;;
        --score)      SCORE_ONLY=1 ;;
        --share)      SHARE=1 ;;
        -h|--help)    sed -n '2,18p' "$0"; exit 0 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
    shift
done

# ---------- helpers ----------
hr()      { printf '%s────────────────────────────────────────────────────────────────%s\n' "$C_BLUE" "$C_RESET"; }
section() { printf '\n%s%s ▸ %s%s\n' "$C_BOLD" "$C_CYAN" "$1" "$C_RESET"; hr; }
kv()      { printf '  %s%-22s%s %s\n' "$C_BOLD" "$1" "$C_RESET" "$2"; }
ok()      { printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$1"; }
warn()    { printf '  %s!%s %s\n' "$C_YELLOW" "$C_RESET" "$1"; }
err()     { printf '  %s✗%s %s\n' "$C_RED" "$C_RESET" "$1" >&2; }
note()    { printf '  %s%s%s\n' "$C_DIM" "$1" "$C_RESET"; }

has() { command -v "$1" >/dev/null 2>&1; }

human_bytes() {
    awk -v b="$1" 'BEGIN{
        s="B KB MB GB TB PB"; split(s,a," "); i=1;
        while (b>=1024 && i<6){b/=1024;i++}
        printf "%.2f %s", b, a[i];
    }'
}

spinner_pid=""
spin_start() {
    if [ ! -t 1 ]; then return; fi
    (
        local chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
        local i=0
        while :; do
            i=$(( (i + 1) % 10 ))
            printf '\r  %s%s%s %s' "$C_MAGENTA" "${chars:$i:1}" "$C_RESET" "$1"
            sleep 0.1
        done
    ) &
    spinner_pid=$!
    disown 2>/dev/null || true
}
spin_stop() {
    [ -n "$spinner_pid" ] && kill "$spinner_pid" 2>/dev/null
    spinner_pid=""
    [ -t 1 ] && printf '\r\033[K'
}

# JSON accumulator
JSON_PAIRS=()
j_set() { JSON_PAIRS+=("\"$1\": $2"); }
j_str() { JSON_PAIRS+=("\"$1\": \"$(printf '%s' "$2" | sed 's/\\/\\\\/g; s/"/\\"/g')\""); }

add_score() {
    # $1=name $2=points
    SCORE_TOTAL=$(awk -v a="$SCORE_TOTAL" -v b="$2" 'BEGIN{printf "%.0f", a+b}')
    SCORE_PARTS+=("$1=$2")
}

# ---------- banner ----------
printf '\n'
printf '%s ██████╗ ███████╗███╗   ██╗ ██████╗██╗  ██╗   ██████╗ ██╗     ██╗   ██╗███████╗%s\n' "$C_MAGENTA" "$C_RESET"
printf '%s ██╔══██╗██╔════╝████╗  ██║██╔════╝██║  ██║   ██╔══██╗██║     ██║   ██║██╔════╝%s\n' "$C_MAGENTA" "$C_RESET"
printf '%s ██████╔╝█████╗  ██╔██╗ ██║██║     ███████║   ██████╔╝██║     ██║   ██║███████╗%s\n' "$C_MAGENTA" "$C_RESET"
printf '%s ██╔══██╗██╔══╝  ██║╚██╗██║██║     ██╔══██║   ██╔═══╝ ██║     ██║   ██║╚════██║%s\n' "$C_MAGENTA" "$C_RESET"
printf '%s ██████╔╝███████╗██║ ╚████║╚██████╗██║  ██║   ██║     ███████╗╚██████╔╝███████║%s\n' "$C_MAGENTA" "$C_RESET"
printf '%s ╚═════╝ ╚══════╝╚═╝  ╚═══╝ ╚═════╝╚═╝  ╚═╝   ╚═╝     ╚══════╝ ╚═════╝ ╚══════╝%s\n' "$C_MAGENTA" "$C_RESET"
printf '%s                     v%s — the modern server benchmark%s\n\n' "$C_DIM" "$VERSION" "$C_RESET"

# ============================================================
# 1. SYSTEM INFO
# ============================================================
section "System Information"

OS_NAME="$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || uname -s)"
KERNEL="$(uname -r)"
ARCH="$(uname -m)"
HOSTNAME="$(hostname 2>/dev/null || echo unknown)"
UPTIME_PRETTY="$(uptime -p 2>/dev/null || awk '{print int($1/86400)"d "int($1%86400/3600)"h"}' /proc/uptime)"
LOAD_AVG="$(awk '{print $1", "$2", "$3}' /proc/loadavg 2>/dev/null || echo n/a)"

CPU_MODEL="$(awk -F: '/model name/{print $2; exit}' /proc/cpuinfo 2>/dev/null | sed 's/^ *//' || echo unknown)"
[ -z "$CPU_MODEL" ] && CPU_MODEL="$(awk -F: '/Hardware|Processor/{print $2; exit}' /proc/cpuinfo 2>/dev/null | sed 's/^ *//')"
CPU_CORES="$(nproc 2>/dev/null || echo 1)"
CPU_FREQ="$(awk -F: '/cpu MHz/{print $2; exit}' /proc/cpuinfo 2>/dev/null | sed 's/^ *//' | awk '{printf "%.0f MHz", $1}')"
CPU_CACHE="$(awk -F: '/cache size/{print $2; exit}' /proc/cpuinfo 2>/dev/null | sed 's/^ *//' || echo unknown)"
CPU_FLAGS="$(awk -F: '/^flags|^Features/{print $2; exit}' /proc/cpuinfo 2>/dev/null)"
AES_NI="no"; AVX="no"; AVX2="no"; AVX512="no"; SSE42="no"
echo "$CPU_FLAGS" | grep -qw aes && AES_NI="yes"
echo "$CPU_FLAGS" | grep -qw avx && AVX="yes"
echo "$CPU_FLAGS" | grep -qw avx2 && AVX2="yes"
echo "$CPU_FLAGS" | grep -qw avx512f && AVX512="yes"
echo "$CPU_FLAGS" | grep -qw sse4_2 && SSE42="yes"

VIRT="$(systemd-detect-virt 2>/dev/null || echo none)"
CONTAINER="$(systemd-detect-virt --container 2>/dev/null || echo none)"
if [ -f /.dockerenv ]; then CONTAINER="docker"; fi
if [ -n "${KUBERNETES_SERVICE_HOST:-}" ]; then CONTAINER="kubernetes"; fi

MEM_TOTAL_KB=$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null || echo 0)
MEM_AVAIL_KB=$(awk '/MemAvailable/{print $2}' /proc/meminfo 2>/dev/null || echo 0)
SWAP_TOTAL_KB=$(awk '/SwapTotal/{print $2}' /proc/meminfo 2>/dev/null || echo 0)

DISK_TOTAL=$(df -B1 --total --exclude-type=tmpfs --exclude-type=devtmpfs --exclude-type=overlay 2>/dev/null | awk '/^total/{print $2}')
DISK_USED=$(df -B1 --total --exclude-type=tmpfs --exclude-type=devtmpfs --exclude-type=overlay 2>/dev/null | awk '/^total/{print $3}')
ROOT_FS="$(df -T / 2>/dev/null | awk 'NR==2{print $2}')"

kv "Hostname"     "$HOSTNAME"
kv "OS"           "$OS_NAME"
kv "Kernel"       "$KERNEL ($ARCH)"
kv "Uptime"       "$UPTIME_PRETTY"
kv "Load Average" "$LOAD_AVG"
kv "Virtualization" "$VIRT${CONTAINER:+ / $CONTAINER}"
kv "CPU Model"    "$CPU_MODEL"
kv "CPU Cores"    "$CPU_CORES @ ${CPU_FREQ:-?}"
kv "CPU Cache"    "$CPU_CACHE"
kv "CPU Features" "AES-NI=$AES_NI  AVX=$AVX  AVX2=$AVX2  AVX-512=$AVX512  SSE4.2=$SSE42"
kv "Memory"       "$(human_bytes $((MEM_TOTAL_KB*1024))) total / $(human_bytes $((MEM_AVAIL_KB*1024))) free"
kv "Swap"         "$(human_bytes $((SWAP_TOTAL_KB*1024)))"
kv "Root FS"      "${ROOT_FS:-unknown}"
kv "Disk"         "$(human_bytes "${DISK_USED:-0}") used / $(human_bytes "${DISK_TOTAL:-0}") total"

# TCP congestion control
TCP_CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)
TCP_QDISC=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo unknown)
kv "TCP cc/qdisc"  "$TCP_CC / $TCP_QDISC"

j_str os "$OS_NAME"; j_str kernel "$KERNEL"; j_str arch "$ARCH"
j_str hostname "$HOSTNAME"; j_str virtualization "$VIRT"
j_str container "$CONTAINER"; j_str cpu_model "$CPU_MODEL"
j_set cpu_cores "$CPU_CORES"; j_set mem_total_bytes "$((MEM_TOTAL_KB*1024))"
j_set disk_total_bytes "${DISK_TOTAL:-0}"; j_str root_fs "${ROOT_FS:-unknown}"
j_str tcp_cc "$TCP_CC"; j_str cpu_aes_ni "$AES_NI"
j_str cpu_avx2 "$AVX2"; j_str cpu_avx512 "$AVX512"

# ============================================================
# 2. GPU / SENSORS
# ============================================================
section "Hardware Sensors"

GPU_INFO="none"
if has nvidia-smi; then
    GPU_INFO=$(nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader 2>/dev/null | head -1)
    GPU_TEMP=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1)
    [ -n "$GPU_INFO" ] && kv "GPU (NVIDIA)" "$GPU_INFO"
    [ -n "${GPU_TEMP:-}" ] && kv "GPU Temp"     "${GPU_TEMP}°C"
elif has lspci; then
    GPU_LINE=$(lspci 2>/dev/null | grep -iE 'vga|3d|2d' | head -1 | sed 's/^.*: //')
    [ -n "$GPU_LINE" ] && { GPU_INFO="$GPU_LINE"; kv "GPU" "$GPU_LINE"; }
fi

# CPU temperature
CPU_TEMP=""
if [ -r /sys/class/thermal/thermal_zone0/temp ]; then
    t=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
    [ -n "$t" ] && CPU_TEMP=$(awk -v t="$t" 'BEGIN{printf "%.1f°C", t/1000}')
fi
if [ -z "$CPU_TEMP" ] && has sensors; then
    CPU_TEMP=$(sensors 2>/dev/null | awk '/Package id 0|Tctl|CPU Temperature/ {gsub(/\+|°C/, "", $4); print $4 "°C"; exit}')
fi
kv "CPU Temp"    "${CPU_TEMP:-n/a}"

# Battery (laptops)
if [ -d /sys/class/power_supply/BAT0 ]; then
    BAT_CAP=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null)
    BAT_STAT=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null)
    [ -n "$BAT_CAP" ] && kv "Battery"   "${BAT_CAP}% ($BAT_STAT)"
fi

j_str gpu "$GPU_INFO"; j_str cpu_temp "${CPU_TEMP:-n/a}"

# ============================================================
# 3. CPU BENCHMARK
# ============================================================
section "CPU Benchmark"

if has sysbench; then
    spin_start "sysbench single-thread (10s)…"
    SB_SINGLE=$(sysbench cpu --threads=1 --time=10 --cpu-max-prime=20000 run 2>/dev/null \
        | awk '/events per second/{print $4}')
    spin_stop
    [ -n "$SB_SINGLE" ] && ok "Single-thread: ${C_BOLD}$SB_SINGLE${C_RESET} events/s" || warn "sysbench single failed"

    spin_start "sysbench multi-thread (10s, $CPU_CORES threads)…"
    SB_MULTI=$(sysbench cpu --threads="$CPU_CORES" --time=10 --cpu-max-prime=20000 run 2>/dev/null \
        | awk '/events per second/{print $4}')
    spin_stop
    [ -n "$SB_MULTI" ] && ok "Multi-thread:  ${C_BOLD}$SB_MULTI${C_RESET} events/s" || warn "sysbench multi failed"

    j_set cpu_single_thread_eps "${SB_SINGLE:-0}"
    j_set cpu_multi_thread_eps "${SB_MULTI:-0}"
    add_score cpu_single "$(awk -v v="${SB_SINGLE:-0}" 'BEGIN{printf "%.0f", v/10}')"
    add_score cpu_multi  "$(awk -v v="${SB_MULTI:-0}"  'BEGIN{printf "%.0f", v/100}')"
else
    if has openssl; then
        spin_start "openssl SHA-256 speed test…"
        OSSL=$(openssl speed -seconds 3 -bytes 1024 sha256 2>/dev/null | awk '/^sha256/{print $7}')
        spin_stop
        [ -n "$OSSL" ] && ok "OpenSSL SHA-256: ${C_BOLD}$OSSL${C_RESET} k/s" || warn "openssl failed"
        j_set openssl_sha256_kps "${OSSL:-0}"
    else
        warn "Install sysbench or openssl for CPU benchmark"
    fi
fi

# Pi calculation via bc (universal)
if has bc; then
    spin_start "π via bc to 2000 digits (timing)…"
    PI_TIME=$( { time -p echo "scale=2000; 4*a(1)" | bc -lq >/dev/null; } 2>&1 | awk '/real/{print $2"s"}')
    spin_stop
    [ -n "$PI_TIME" ] && ok "π@2000 digits (bc): ${C_BOLD}$PI_TIME${C_RESET}"
    j_str pi_2000_time "${PI_TIME:-n/a}"
fi

# ============================================================
# 4. CRYPTO BENCHMARK
# ============================================================
section "Crypto Benchmark"

if has openssl; then
    spin_start "OpenSSL AES-256-CBC (3s, 8KB)…"
    AES_SPEED=$(openssl speed -elapsed -evp aes-256-cbc -seconds 3 -bytes 8192 2>/dev/null | awk '/aes-256-cbc/{print $2, $7}')
    spin_stop
    [ -n "$AES_SPEED" ] && ok "AES-256-CBC (8K): ${C_BOLD}$(echo $AES_SPEED | awk '{print $2}')${C_RESET}"

    spin_start "OpenSSL ChaCha20 (3s, 8KB)…"
    CHACHA=$(openssl speed -elapsed -evp chacha20 -seconds 3 -bytes 8192 2>/dev/null | awk '/chacha20/{print $7}')
    spin_stop
    [ -n "$CHACHA" ] && ok "ChaCha20 (8K):    ${C_BOLD}$CHACHA${C_RESET}"

    j_str aes_256_8k "${AES_SPEED:-n/a}"
    j_str chacha20_8k "${CHACHA:-n/a}"
else
    warn "openssl not found — skipping crypto bench"
fi

# ============================================================
# 5. COMPRESSION BENCHMARK
# ============================================================
section "Compression"

if has dd; then
    COMP_FILE="$(mktemp)"
    dd if=/dev/urandom of="$COMP_FILE" bs=1M count=64 status=none 2>/dev/null

    for tool in gzip zstd xz lz4; do
        if has "$tool"; then
            spin_start "$tool — compressing 64MB random data…"
            T=$( { time -p "$tool" -c "$COMP_FILE" > /dev/null; } 2>&1 | awk '/real/{print $2}')
            spin_stop
            SPEED=$(awk -v t="$T" 'BEGIN{ if(t>0) printf "%.1f MB/s", 64/t; else print "n/a" }')
            ok "$(printf '%-6s' "$tool") → ${T}s (${C_BOLD}$SPEED${C_RESET})"
            j_str "compress_${tool}" "${SPEED}"
        fi
    done
    rm -f "$COMP_FILE"
fi

# ============================================================
# 6. MEMORY BENCHMARK
# ============================================================
section "Memory Benchmark"

if has sysbench; then
    spin_start "sysbench memory read (5s)…"
    MEM_READ=$(sysbench memory --memory-oper=read --memory-total-size=10G --time=5 run 2>/dev/null \
        | awk '/transferred/{print $4, $5}' | tr -d '()')
    spin_stop
    spin_start "sysbench memory write (5s)…"
    MEM_WRITE=$(sysbench memory --memory-oper=write --memory-total-size=10G --time=5 run 2>/dev/null \
        | awk '/transferred/{print $4, $5}' | tr -d '()')
    spin_stop
    [ -n "$MEM_READ" ]  && ok "Memory read:  ${C_BOLD}$MEM_READ${C_RESET}"
    [ -n "$MEM_WRITE" ] && ok "Memory write: ${C_BOLD}$MEM_WRITE${C_RESET}"
    j_str mem_read "$MEM_READ"
    j_str mem_write "$MEM_WRITE"
else
    warn "sysbench not installed — skipping memory bench"
fi

# ============================================================
# 7. DISK I/O
# ============================================================
section "Disk I/O"

TMPFILE="$(mktemp -p "${TMPDIR:-/tmp}" benchplus.XXXXXX)"
trap 'rm -f "$TMPFILE"' EXIT INT TERM

if has fio; then
    for bs in 4k 64k 1m; do
        spin_start "fio random read/write @ ${bs} (15s)…"
        OUT=$(fio --name=rw_${bs} --filename="$TMPFILE" --size=512M --rw=randrw --rwmixread=70 \
            --bs="$bs" --ioengine=libaio --iodepth=64 --runtime=15 --time_based --group_reporting \
            --output-format=terse 2>/dev/null | head -1)
        spin_stop
        if [ -n "$OUT" ]; then
            R_IOPS=$(echo "$OUT" | awk -F';' '{print $8}')
            W_IOPS=$(echo "$OUT" | awk -F';' '{print $49}')
            R_BW=$(echo "$OUT"   | awk -F';' '{print $7}')
            W_BW=$(echo "$OUT"   | awk -F';' '{print $48}')
            printf '  %s%-4s%s  read %s%6s IOPS%s (%s KB/s)  |  write %s%6s IOPS%s (%s KB/s)\n' \
                "$C_BOLD" "$bs" "$C_RESET" \
                "$C_GREEN" "$R_IOPS" "$C_RESET" "$R_BW" \
                "$C_GREEN" "$W_IOPS" "$C_RESET" "$W_BW"
            j_set "fio_${bs}_read_iops" "${R_IOPS:-0}"
            j_set "fio_${bs}_write_iops" "${W_IOPS:-0}"
        fi
    done
else
    note "fio not installed — using dd fallback (less accurate)"
    DD_WRITE=$(dd if=/dev/zero of="$TMPFILE" bs=1M count=512 oflag=direct 2>&1 \
        | awk -F, '/copied|bytes/{gsub(/^ +/,"",$NF); print $NF}')
    [ -z "$DD_WRITE" ] && DD_WRITE=$(dd if=/dev/zero of="$TMPFILE" bs=1M count=512 2>&1 \
        | awk -F, '/copied|bytes/{gsub(/^ +/,"",$NF); print $NF}')
    ok "Sequential write (dd 512MB): ${C_BOLD}${DD_WRITE:-n/a}${C_RESET}"

    if [ "$(id -u)" -eq 0 ] && [ -w /proc/sys/vm/drop_caches ]; then
        sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
    fi
    DD_READ=$(dd if="$TMPFILE" of=/dev/null bs=1M 2>&1 \
        | awk -F, '/copied|bytes/{gsub(/^ +/,"",$NF); print $NF}')
    ok "Sequential read  (dd 512MB): ${C_BOLD}${DD_READ:-n/a}${C_RESET}"
    j_str dd_write "$DD_WRITE"; j_str dd_read "$DD_READ"
fi

rm -f "$TMPFILE"

# Detailed disk info via smartctl
if has smartctl && [ "$(id -u)" -eq 0 ]; then
    ROOT_DEV=$(df / | awk 'NR==2{print $1}' | sed 's/[0-9]*$//')
    if [ -b "$ROOT_DEV" ]; then
        SMART=$(smartctl -i "$ROOT_DEV" 2>/dev/null | awk -F: '/Model Number|Device Model|Rotation Rate/{gsub(/^[ \t]+/,"",$2); print $1": "$2}' | head -3)
        [ -n "$SMART" ] && echo "$SMART" | while read line; do note "$line"; done
    fi
fi

# ============================================================
# 8. NETWORK
# ============================================================
if [ "$NO_NET" -eq 0 ]; then
    section "Network"

    PUB_IP4=$(curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null || echo "")
    PUB_IP6=$(curl -fsS --max-time 5 https://api6.ipify.org 2>/dev/null || echo "")
    ASN_INFO=$(curl -fsS --max-time 5 "https://ipinfo.io/${PUB_IP4}/json" 2>/dev/null || echo "{}")
    ASN_ORG=$(echo "$ASN_INFO" | grep -oE '"org":[^,]*' | sed 's/"org":"//; s/"//g')
    ASN_LOC=$(echo "$ASN_INFO" | grep -oE '"city":[^,]*|"country":[^,]*' | sed 's/"[a-z]*"://; s/"//g' | paste -sd', ')

    kv "Public IPv4"  "${PUB_IP4:-n/a}"
    kv "Public IPv6"  "${PUB_IP6:-n/a}"
    kv "ASN / Org"    "${ASN_ORG:-n/a}"
    kv "Location"     "${ASN_LOC:-n/a}"

    j_str public_ip4 "$PUB_IP4"; j_str public_ip6 "$PUB_IP6"
    j_str asn_org "$ASN_ORG"; j_str location "$ASN_LOC"

    if [ "$QUICK" -eq 0 ]; then
        # Latency to global anycast DNS — tries ICMP ping first,
        # falls back to TCP connect timing (works in restricted containers).
        printf '\n  %sLatency (avg / jitter):%s\n' "$C_BOLD" "$C_RESET"

        # Detect if ICMP is usable at all (containers without CAP_NET_RAW can't ping)
        PING_OK=0
        if ping -c 1 -W 1 1.1.1.1 >/dev/null 2>&1; then
            PING_OK=1
        else
            note "ICMP blocked (common in Docker) — using TCP connect timing on port 443"
        fi

        for target in "1.1.1.1:Cloudflare" "8.8.8.8:Google" "9.9.9.9:Quad9" "208.67.222.222:OpenDNS"; do
            host="${target%%:*}"; name="${target##*:}"
            AVG=""; JIT=""
            if [ "$PING_OK" -eq 1 ]; then
                PING_OUT=$(ping -c 5 -W 2 "$host" 2>/dev/null | awk -F'/' '/^rtt|^round-trip/{print $5, $7}')
                if [ -n "$PING_OUT" ]; then
                    AVG=$(echo "$PING_OUT" | awk '{print $1}')
                    JIT=$(echo "$PING_OUT" | awk '{print $2}')
                fi
            fi
            # TCP fallback via curl --connect-timeout against 443
            if [ -z "$AVG" ] && has curl; then
                samples=""
                for i in 1 2 3 4 5; do
                    T=$(curl -o /dev/null -s -w '%{time_connect}\n' --connect-timeout 2 \
                        --max-time 3 "https://${host}/" 2>/dev/null)
                    [ -n "$T" ] && [ "$T" != "0.000000" ] && samples="$samples $T"
                done
                if [ -n "$samples" ]; then
                    AVG=$(echo "$samples" | awk '{ s=0; n=0; for(i=1;i<=NF;i++){s+=$i; n++} if(n>0) printf "%.1f", (s/n)*1000 }')
                    JIT=$(echo "$samples" | awk -v a="$AVG" '{ s=0; n=0; for(i=1;i<=NF;i++){ d=($i*1000-a); s+=d*d; n++ } if(n>0) printf "%.1f", sqrt(s/n) }')
                fi
            fi
            if [ -n "$AVG" ]; then
                printf '    %-22s %s%6s ms%s ± %s ms\n' "$name" "$C_GREEN" "$AVG" "$C_RESET" "${JIT:-?}"
            else
                printf '    %-22s %s%s%s\n' "$name" "$C_YELLOW" "timeout" "$C_RESET"
            fi
        done

        # DNS resolution speed
        printf '\n  %sDNS resolution (avg of 3 lookups):%s\n' "$C_BOLD" "$C_RESET"
        if has dig; then
            for dns_target in "google.com" "github.com" "cloudflare.com"; do
                T=$(for i in 1 2 3; do
                    dig +noall +stats +time=2 "$dns_target" 2>/dev/null | awk '/Query time/{print $4}'
                done | awk '{s+=$1; n++} END{if(n>0) printf "%.1f", s/n; else print "n/a"}')
                printf '    %-22s %s%6s ms%s\n' "$dns_target" "$C_GREEN" "$T" "$C_RESET"
            done
        else
            note "dig not installed — skipping DNS test"
        fi

        # HTTP timings
        printf '\n  %sHTTP fetch timings:%s\n' "$C_BOLD" "$C_RESET"
        for url in "https://www.google.com" "https://github.com" "https://www.cloudflare.com"; do
            T=$(curl -o /dev/null -s -w '%{time_total}' --max-time 8 "$url" 2>/dev/null)
            T_MS=$(awk -v t="$T" 'BEGIN{printf "%.0f", t*1000}')
            printf '    %-32s %s%6s ms%s\n' "$url" "$C_GREEN" "$T_MS" "$C_RESET"
        done

        # ---------- Built-in speedtest (no external CLI needed) ----------
        printf '\n  %sSpeedtest (curl-based, no external CLI):%s\n' "$C_BOLD" "$C_RESET"

        # Convert bytes-per-second → Mbit/s (1 Mbit = 10^6 bits)
        bps_to_mbits() { awk -v b="$1" 'BEGIN{ if(b>0) printf "%.2f", (b*8)/1000000; else print "0.00" }'; }

        # Download test: fetch a known-size payload, measure time, derive throughput.
        # endpoints chosen for global anycast + reliability. size auto-picked.
        DOWN_BEST=0
        DOWN_BEST_LOC=""
        for entry in \
            "Cloudflare (global anycast)|https://speed.cloudflare.com/__down?bytes=104857600|100" \
            "Hetzner (Falkenstein, DE)|https://nbg1-speed.hetzner.com/100MB.bin|100" \
            "CacheFly (multi-region)|https://cachefly.cachefly.net/100mb.test|100"
        do
            NAME="${entry%%|*}"; rest="${entry#*|}"
            URL="${rest%%|*}";   SIZE_MB="${rest##*|}"
            spin_start "↓ downloading ${SIZE_MB}MB from $NAME …"
            # curl reports total bytes downloaded and time used. timeout caps stalled servers.
            OUT=$(curl -fsS --max-time 30 -o /dev/null \
                  -w '%{size_download} %{time_total} %{speed_download}\n' \
                  "$URL" 2>/dev/null || true)
            spin_stop
            if [ -z "$OUT" ]; then
                printf '    %-30s %s%s%s\n' "$NAME" "$C_YELLOW" "failed" "$C_RESET"
                continue
            fi
            BYTES=$(echo "$OUT" | awk '{print $1}')
            SECS=$(echo "$OUT"  | awk '{print $2}')
            BPS=$(echo "$OUT"   | awk '{print $3}')
            # If <1 MB came back, treat as failed (often an error page returned with 200).
            if [ "${BYTES:-0}" -lt 1000000 ]; then
                printf '    %-30s %s%s%s\n' "$NAME" "$C_YELLOW" "stalled / small payload" "$C_RESET"
                continue
            fi
            MBITS=$(bps_to_mbits "$BPS")
            MIB=$(awk -v b="$BYTES" 'BEGIN{ printf "%.1f", b/1048576 }')
            printf '    %-30s %s↓ %7s Mbit/s%s   (%s MiB in %ss)\n' \
                "$NAME" "$C_GREEN" "$MBITS" "$C_RESET" "$MIB" "$SECS"
            # Track best (highest Mbit/s)
            IS_BEST=$(awk -v a="$MBITS" -v b="$DOWN_BEST" 'BEGIN{ print (a>b)?1:0 }')
            if [ "$IS_BEST" = "1" ]; then
                DOWN_BEST="$MBITS"
                DOWN_BEST_LOC="$NAME"
            fi
            j_str "speedtest_down_${NAME// /_}" "${MBITS} Mbit/s"
        done

        # Upload test against Cloudflare's /__up endpoint (accepts arbitrary bytes).
        UP_MBITS=""
        if has dd; then
            UPFILE=$(mktemp)
            # 25 MiB random data — small enough not to take forever, big enough to be representative.
            dd if=/dev/urandom of="$UPFILE" bs=1M count=25 status=none 2>/dev/null
            spin_start "↑ uploading 25MB to Cloudflare…"
            UP_OUT=$(curl -fsS --max-time 30 -o /dev/null \
                  -w '%{size_upload} %{time_total} %{speed_upload}\n' \
                  -X POST -H 'Content-Type: application/octet-stream' \
                  --data-binary "@$UPFILE" \
                  "https://speed.cloudflare.com/__up" 2>/dev/null || true)
            spin_stop
            rm -f "$UPFILE"
            if [ -n "$UP_OUT" ]; then
                UBYTES=$(echo "$UP_OUT" | awk '{print $1}')
                UBPS=$(echo "$UP_OUT"   | awk '{print $3}')
                if [ "${UBYTES:-0}" -gt 1000000 ]; then
                    UP_MBITS=$(bps_to_mbits "$UBPS")
                    printf '    %-30s %s↑ %7s Mbit/s%s\n' \
                        "Cloudflare upload" "$C_GREEN" "$UP_MBITS" "$C_RESET"
                fi
            fi
            [ -z "$UP_MBITS" ] && printf '    %-30s %s%s%s\n' "Cloudflare upload" "$C_YELLOW" "failed" "$C_RESET"
        fi

        # Summary
        if [ -n "$DOWN_BEST_LOC" ]; then
            printf '\n    %sBest down:%s %s%s Mbit/s%s  (%s)%s   %sUp:%s %s%s Mbit/s%s\n' \
                "$C_BOLD" "$C_RESET" \
                "$C_BOLD" "$DOWN_BEST" "$C_RESET" "$DOWN_BEST_LOC" "$C_RESET" \
                "$C_BOLD" "$C_RESET" \
                "$C_BOLD" "${UP_MBITS:-n/a}" "$C_RESET"
            j_str speedtest_best_down "${DOWN_BEST} Mbit/s (${DOWN_BEST_LOC})"
            j_str speedtest_up "${UP_MBITS:-n/a} Mbit/s"
        fi
    else
        warn "Quick mode: skipping latency / DNS / speedtest"
    fi
else
    section "Network"
    warn "Network tests disabled (--no-net)"
fi

# ============================================================
# 9. TOP PROCESSES
# ============================================================
section "Top Processes"

printf '  %sBy CPU:%s\n' "$C_BOLD" "$C_RESET"
ps -eo pid,pcpu,pmem,comm --sort=-pcpu 2>/dev/null | head -6 | tail -5 | awk '{printf "    %-6s %5s%%  %5s%%  %s\n", $1, $2, $3, $4}'

printf '\n  %sBy Memory:%s\n' "$C_BOLD" "$C_RESET"
ps -eo pid,pcpu,pmem,comm --sort=-pmem 2>/dev/null | head -6 | tail -5 | awk '{printf "    %-6s %5s%%  %5s%%  %s\n", $1, $2, $3, $4}'

# ============================================================
# 10. SCORE + SUMMARY
# ============================================================
END_TS=$(date +%s)
ELAPSED=$((END_TS - START_TS))

section "Summary"
if [ "${#SCORE_PARTS[@]}" -gt 0 ]; then
    kv "Composite score" "${C_BOLD}${C_GREEN}${SCORE_TOTAL}${C_RESET} pts"
    for part in "${SCORE_PARTS[@]}"; do
        note "  • $part"
    done
fi
kv "Elapsed"    "${ELAPSED}s"
kv "Finished"   "$(date '+%Y-%m-%d %H:%M:%S %Z')"

j_set elapsed_seconds "$ELAPSED"
j_set composite_score "$SCORE_TOTAL"
j_str version "$VERSION"
j_str finished_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---------- JSON output ----------
if [ -n "$JSON_OUT" ]; then
    {
        printf '{\n'
        for i in "${!JSON_PAIRS[@]}"; do
            sep=','
            [ "$i" -eq $((${#JSON_PAIRS[@]} - 1)) ] && sep=''
            printf '  %s%s\n' "${JSON_PAIRS[$i]}" "$sep"
        done
        printf '}\n'
    } > "$JSON_OUT"
    ok "JSON report → $JSON_OUT"
fi

# ---------- HTML output ----------
if [ -n "$HTML_OUT" ]; then
    {
        cat <<HTMLHEAD
<!doctype html><html lang=en><head><meta charset=utf-8>
<title>bench-plus report — $HOSTNAME</title>
<style>
 body{font:14px/1.5 -apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif;
      margin:2rem auto;max-width:900px;color:#0f172a;background:#fafafa;padding:0 1.5rem}
 h1{font-size:1.8rem;margin:.2rem 0}
 .tag{display:inline-block;background:#0ea5e9;color:#fff;padding:2px 10px;
      border-radius:99px;font-size:.8rem;margin-left:.5rem}
 table{border-collapse:collapse;width:100%;margin:1rem 0;background:#fff;
       box-shadow:0 1px 3px rgba(0,0,0,.06);border-radius:8px;overflow:hidden}
 th,td{padding:.55rem .9rem;text-align:left;border-bottom:1px solid #eee}
 th{background:#f1f5f9;font-weight:600;width:35%}
 footer{color:#64748b;font-size:.85rem;margin-top:2rem}
 .score{font-size:2.2rem;color:#16a34a;font-weight:700}
</style></head><body>
<h1>bench-plus report <span class=tag>v$VERSION</span></h1>
<div class=score>Composite score: $SCORE_TOTAL pts</div>
<table>
HTMLHEAD
        for pair in "${JSON_PAIRS[@]}"; do
            k=$(echo "$pair" | sed 's/^"\([^"]*\)".*/\1/')
            v=$(echo "$pair" | sed 's/^"[^"]*": //; s/^"//; s/"$//')
            printf '  <tr><th>%s</th><td>%s</td></tr>\n' "$k" "$v"
        done
        cat <<HTMLFOOT
</table>
<footer>Generated by bench-plus v$VERSION on $(date '+%Y-%m-%d %H:%M:%S %Z') · host $HOSTNAME</footer>
</body></html>
HTMLFOOT
    } > "$HTML_OUT"
    ok "HTML report → $HTML_OUT"
fi

# ---------- share ----------
if [ "$SHARE" -eq 1 ] && [ -n "$JSON_OUT" ] && has curl; then
    UPLOAD_URL=$(curl -fsS --max-time 10 "https://bashupload.com" -T "$JSON_OUT" 2>/dev/null | grep -oE 'https?://[^ ]+' | head -1)
    [ -n "$UPLOAD_URL" ] && ok "Shareable URL: ${C_BOLD}$UPLOAD_URL${C_RESET}" || warn "Share upload failed"
fi

printf '\n  %sRun with --quick to skip slow network tests, or --json/--html for reports.%s\n\n' "$C_DIM" "$C_RESET"

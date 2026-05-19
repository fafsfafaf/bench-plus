# bench-plus

An improved, modernized server benchmark script — successor to the classic `bench.sh`.

## Features

- Clean, colorized output with section headers
- Comprehensive system info (CPU, RAM, disk, virtualization, ASN/geo)
- **CPU**: `sysbench` single + multi-thread (auto-falls back to `openssl speed`)
- **Memory**: `sysbench` read + write throughput
- **Disk**: `fio` random 4k IOPS (auto-falls back to `dd` sequential)
- **Network**: public IPv4/IPv6, ASN, latency probes (Cloudflare/Google/Quad9), speedtest
- Optional **JSON report** for automation / dashboards
- Sane fallbacks if optional tools (sysbench/fio/speedtest) aren't installed
- Works as root or unprivileged; warns when results may be affected

## Quick start

```bash
curl -fsSL https://raw.githubusercontent.com/fafsfafaf/bench-plus/master/bench.sh | bash
```

Or download and run:

```bash
wget -O bench.sh https://raw.githubusercontent.com/fafsfafaf/bench-plus/master/bench.sh
chmod +x bench.sh
./bench.sh
```

## Options

| Flag | Purpose |
|------|---------|
| `--quick` | Skip latency + speedtest (system + CPU + RAM + disk only) |
| `--no-net` | Skip all network tests (offline-friendly) |
| `--json FILE` | Also write a machine-readable JSON report to `FILE` |
| `-h`, `--help` | Show usage |

## Recommended (optional) dependencies

For best results, install these before running:

```bash
# Debian / Ubuntu
sudo apt-get update && sudo apt-get install -y sysbench fio speedtest-cli curl

# RHEL / CentOS / Fedora
sudo dnf install -y sysbench fio speedtest-cli curl

# Alpine
sudo apk add sysbench fio speedtest-cli curl bash
```

If any of these are missing, `bench-plus` falls back to built-in tools (`openssl`, `dd`, `ping`).

## Sample output

```
╔════════════════════════════════════════════════════════════╗
║  bench-plus v1.0.0  —  improved server benchmark           ║
╚════════════════════════════════════════════════════════════╝

 System Information
────────────────────────────────────────────────────────────────
  Hostname               my-vps
  OS                     Ubuntu 24.04.1 LTS
  Kernel                 6.8.0-45-generic (x86_64)
  CPU Model              AMD EPYC 9354P
  CPU Cores              8 @ 3250 MHz
  Memory                 16.00 GB total / 13.21 GB available
  Disk                   8.21 GB used / 80.00 GB total

 CPU Benchmark
────────────────────────────────────────────────────────────────
  ✓ Single-thread: 1842.31 events/s
  ✓ Multi-thread:  14210.55 events/s (8 threads)
…
```

## License

MIT

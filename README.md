# bench-plus

An improved, modernized server benchmark — the spiritual successor to the classic `bench.sh`.

## v2.0.0 — Now with way more stuff

- **System**: CPU model, cache, AES-NI / AVX / AVX2 / AVX-512 / SSE4.2 detection,
  virtualization + container detection (Docker, Kubernetes, LXC, KVM…),
  TCP congestion control, root filesystem, load average
- **Hardware sensors**: NVIDIA GPU info, CPU/GPU temperatures, battery state
- **CPU**: `sysbench` single + multi-thread, π@2000 digits via `bc` (auto-falls back to `openssl speed`)
- **Crypto**: OpenSSL AES-256-CBC + ChaCha20 throughput
- **Compression**: `gzip` / `zstd` / `xz` / `lz4` head-to-head on 64MB random data
- **Memory**: `sysbench` read / write throughput
- **Disk**: `fio` 4k / 64k / 1M random read+write IOPS (falls back to `dd`); optional `smartctl` info
- **Network**:
  - Public IPv4 + IPv6 + ASN + city/country
  - Ping latency **and jitter** to Cloudflare, Google, Quad9, OpenDNS
  - DNS resolution timings via `dig`
  - HTTP fetch timings to Google / GitHub / Cloudflare
  - speedtest-cli throughput
- **Reports**: `--json out.json`, `--html out.html`, `--share` to bashupload
- **Composite score** so you can compare boxes at a glance
- **Spinner**, colors, sane fallbacks, idempotent, no apt-installing of anything

## Quick start

```bash
curl -fsSL https://raw.githubusercontent.com/fafsfafaf/bench-plus/master/bench.sh | bash
```

Or for a full report:

```bash
wget -qO bench.sh https://raw.githubusercontent.com/fafsfafaf/bench-plus/master/bench.sh
chmod +x bench.sh
./bench.sh --json bench.json --html bench.html
```

## Flags

| Flag | What it does |
|------|--------------|
| `--quick` | Skip latency / DNS / HTTP / speedtest (system + CPU + RAM + disk only) |
| `--no-net` | Skip all network tests (offline) |
| `--json FILE` | Write machine-readable JSON report |
| `--html FILE` | Write standalone HTML report with composite score |
| `--share` | Upload JSON to bashupload.com and print URL (requires `--json`) |
| `--score` | Show summary score only at end |
| `-h`, `--help` | Show usage |

## Recommended (optional) tools

`bench-plus` works out of the box, but installing these makes results richer:

```bash
# Debian / Ubuntu
sudo apt-get install -y sysbench fio speedtest-cli dnsutils smartmontools zstd lz4 lm-sensors

# RHEL / Fedora
sudo dnf install -y sysbench fio speedtest-cli bind-utils smartmontools zstd lz4 lm_sensors

# Alpine
sudo apk add sysbench fio speedtest-cli bind-tools smartmontools zstd lz4 lm-sensors bash
```

Each missing tool just causes its section to fall back or be skipped.

## Why?

The original `bench.sh` hasn't moved much in years. `bench-plus` adds:
- multi-block-size disk benchmark (4k = IOPS / 1M = throughput → both matter)
- network *quality* (jitter, DNS, HTTP), not just raw speedtest numbers
- crypto + compression (often the actual bottleneck for backups & TLS)
- GPU / sensors / battery (useful on dev machines + edge nodes)
- machine-readable output for automation
- composite score for quick A/B comparison

## License

MIT

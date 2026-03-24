# Argus
My attempt at a red team recon framework.

A modular, automated external reconnaissance framework for authorized red team engagements. Chains together open source tooling to perform subdomain enumeration, live host discovery, technology fingerprinting, and OSINT — then writes everything to a structured Markdown report.

This tool is designed to give you a lay of the land quickly, but use your judgment to seek out other resources to find available information. This should not be used as the final source of truth. 

> **Legal Notice:** This tool is intended for use only against systems you own or have explicit written authorization to test. Unauthorized use is illegal and unethical.

---

## Features

- **Subdomain enumeration** via `subfinder`, `assetfinder`, and certificate transparency logs (crt.sh)
- **Live host discovery** and **technology fingerprinting** via `httpx`
- **DNS resolution** via `dnsx`
- **Cloud/CDN filtering** — skips AWS, GCP, Azure, Cloudflare, Akamai, and Fastly-hosted infrastructure to reduce noise and stay in scope
- **Endpoint and JS discovery** via `katana`
- **Screenshot capture** via `gowitness`
- **Azure tenant discovery** via OpenID configuration lookup
- **OSINT collection** — WHOIS and DNS records
- **Structured output** — all findings organized into a per-domain project directory with a Markdown summary report

---

## Prerequisites

### Required

- **Go** (1.21+) — [https://go.dev/dl/](https://go.dev/dl/)
- **curl**, **jq**, **whois**, **dig** — installed via setup.sh script if not installed

### Auto-installed Go tools

The script will automatically install any missing tools using go install contained in the setup.sh script:

| Tool | Source |
|------|--------|
| `subfinder` | projectdiscovery/subfinder |
| `assetfinder` | tomnomnom/assetfinder |
| `naabu` | projectdiscovery/naabu |
| `nuclei` | projectdiscovery/nuclei |
| `httpx` | projectdiscovery/httpx |
| `dnsx` | projectdiscovery/dnsx |
| `katana` | projectdiscovery/katana |
| `gowitness` | sensepost/gowitness |

> **Note:** First-run installs can take several minutes depending on your connection speed.

---

## Installation

```bash
git clone https://github.com/jleejohn2570/Argus.git
cd Argus
chmod +x argus.sh
chmod +x setup.sh
```

Ensure `~/go/bin` is in your `PATH`:

```bash
export PATH=$PATH:$HOME/go/bin
```

Add the above to your `~/.bashrc` or `~/.zshrc` to persist it.

---

## Usage

```bash
./argus.sh -d <domain> [-t <threads>]
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `-d` | Target domain (required) | — |
| `-t` | Thread count for concurrent tools | `20` |
| `-h` | Show help and exit | — |

### Examples

```bash
# Basic scan with default threads
./argus.sh -d example.com

# Increase threads for faster scanning
./argus.sh -d example.com -t 50
```

---

## Output Structure

All output is written to a `recon-<domain>/` directory:

```
recon-example.com/
├── subdomains/
│   ├── subfinder.txt        # Subfinder results
│   ├── assetfinder.txt      # Assetfinder results
│   ├── crt.txt              # Certificate transparency results
│   └── all.txt              # Deduplicated combined list
├── hosts/
│   ├── live_hosts_full.txt  # Live hosts with protocol
│   ├── live_hosts.txt       # Bare hostnames
│   ├── resolved_hosts.txt   # Hosts with resolved IPs
│   └── scan_targets.txt     # Non-CDN hosts eligible for scanning
├── tech/
│   └── technologies.txt     # Technology fingerprinting results
├── js/
│   └── endpoints.txt        # Katana crawl results
├── screenshots/             # Gowitness screenshot database and images
├── osint/
│   ├── whois.txt            # WHOIS record
│   ├── dns.txt              # DNS records
│   └── azure.json           # Azure tenant OpenID config (if applicable)
└── report.md                # Executive summary report
```

---

## Report

At the end of each run, the framework generates `recon-<domain>/report.md` containing:

- Scan date and total runtime
- Subdomain and live host counts
- Detected technologies
- Non-cloud targets
- Entra Tenant Information
- DNS Records

---

## Troubleshooting

**`jq: parse error` from crt.sh**
crt.sh occasionally returns a non-JSON response (rate limiting, empty results, or a transient error). The script handles this gracefully by validating the response before parsing. If CT log results are empty, check your connection to `crt.sh` manually:
```bash
curl -s "https://crt.sh/?q=%.example.com&output=json" | head -c 200
```

**Tools not found after install**
Ensure `~/go/bin` is in your `PATH`. Run `export PATH=$PATH:$HOME/go/bin` or add it to your shell profile.


**Screenshots directory is empty**
`gowitness` requires a working Chrome or Chromium installation. Install it with:
```bash
sudo apt install chromium-browser -y
```

---

## Contributing

Pull requests are welcome. Please open an issue first to discuss significant changes. All contributions must be scoped to legitimate defensive research and authorized red team use cases.

---

## License

MIT License. See [LICENSE](LICENSE) for details.

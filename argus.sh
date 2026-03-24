#!/bin/bash
set -euo pipefail

# --- Configuration & Colors ---
RED='\033[1;31m'
GREEN='\033[1;32m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

START_TIME=$SECONDS
threads=20
domain=""

# --- CLI Arguments ---
while getopts "d:t:h" opt; do
  case ${opt} in
    d ) domain=$OPTARG ;;
    t ) threads=$OPTARG ;;
    h ) echo "Usage: $0 -d domain [-t threads]"; exit 0 ;;
    * ) exit 1 ;;
  esac
done

# --- Input Validation ---
if [ -z "$domain" ]; then
  echo -e "${RED}[-] Error: Provide a domain with -d${NC}"
  exit 1
fi

if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
  echo -e "${RED}[-] Invalid domain format: $domain${NC}"
  exit 1
fi

# --- Dependency Gatekeeper ---
function check_env() {
  local requirements=(subfinder assetfinder httpx dnsx katana gowitness jq whois dig)
  for tool in "${requirements[@]}"; do
    if ! command -v "$tool" &> /dev/null; then
      echo -e "${RED}[-] Missing tool: $tool. Please run ./setup.sh first.${NC}"
      exit 1
    fi
  done
}

check_env
export PATH=$PATH:$HOME/go/bin

# --- Project Initialization ---
project="recon-$(basename "$domain")"
mkdir -p "$project"/{subdomains,hosts,osint,screenshots,js,tech}
cd "$project" || exit 1

echo -e "${BLUE}======================================"
echo "      Argus Recon: $domain"
echo -e "======================================${NC}"

# --- Subdomain Enumeration ---
echo -e "${BLUE}[+] Subdomain enumeration...${NC}"
subfinder -d "$domain" -silent > subdomains/subfinder.txt &
assetfinder --subs-only "$domain" > subdomains/assetfinder.txt &
wait

# --- Certificate Transparency ---
echo -e "${BLUE}[+] Checking CT logs (crt.sh)...${NC}"
crt_response=$(curl -s --max-time 30 "https://crt.sh/?q=%25.$domain&output=json" || echo "[]")
if echo "$crt_response" | jq -e . >/dev/null 2>&1; then
  echo "$crt_response" | jq -r '.[].name_value' | sed 's/\*\.//g' | sort -u > subdomains/crt_raw.txt
else
  touch subdomains/crt_raw.txt
fi
grep -E '^[a-zA-Z0-9._-]+\.[a-zA-Z]{2,}$' subdomains/crt_raw.txt | sort -u > subdomains/crt.txt || true

# --- Combine & Clean ---
touch subdomains/subfinder.txt subdomains/assetfinder.txt subdomains/crt.txt
cat subdomains/subfinder.txt subdomains/assetfinder.txt subdomains/crt.txt | sort -u > subdomains/all.txt
subcount=$(wc -l < subdomains/all.txt)
echo -e "${GREEN}[+] Unique Subdomains: $subcount${NC}"

# --- Live Host Discovery & Tech Fingerprinting ---
echo -e "${BLUE}[+] Probing live hosts & detecting technologies...${NC}"
~/go/bin/httpx -l subdomains/all.txt -tech-detect -silent -o hosts/live_hosts_full.txt
sed 's|https\?://||' hosts/live_hosts_full.txt | sort -u > hosts/live_hosts.txt
livecount=$(wc -l < hosts/live_hosts.txt)

# --- Technology Extraction ---
echo -e "${BLUE}[+] Extracting technology tags...${NC}"
grep -oP '\[.*?\]' hosts/live_hosts_full.txt | tr -d '[]' | tr ',' '\n' | sed 's/^ *//' | sort -u > tech/technologies.txt || true
techcount=$(wc -l < tech/technologies.txt || echo 0)
echo -e "${GREEN}[+] Unique technologies identified: $techcount${NC}"

# --- Enrichment & Analysis ---
echo -e "${BLUE}[+] Crawling & Screenshotting...${NC}"
katana -list hosts/live_hosts.txt -c "$threads" -silent -o js/endpoints.txt &
gowitness scan file -f hosts/live_hosts.txt --screenshot-path screenshots/ --write-db &
wait

# --- Cloud Filtering Logic ---
echo -e "${BLUE}[+] Filtering Cloud Providers out...${NC}"
dnsx -l hosts/live_hosts.txt -resp -silent -o hosts/resolved_hosts.txt || echo "[!] dnsx found no resolutions"

grep -i "WordPress" hosts/live_hosts_full.txt | awk '{print $1}' | sed 's|https\?://||' | sort -u > hosts/wordpress_sites.txt || true

> hosts/scan_targets.txt

if [ -s hosts/resolved_hosts.txt ]; then
  while IFS=' ' read -r host ip; do
    if [ -s hosts/wordpress_sites.txt ] && grep -q "$host" hosts/wordpress_sites.txt; then
      echo -e "${YELLOW}[*] Skipping $host - WordPress CMS detected${NC}"
      continue
    fi

    asn_info=$(curl -s --max-time 5 "https://ipinfo.io/$ip/org" || echo "Unknown")

    if echo "$asn_info" | grep -qiE "Amazon|Google|Microsoft|Cloudflare|Akamai|Fastly|WordPress|Automattic|WP Engine"; then
      echo -e "${YELLOW}[*] Skipping $host ($ip) - Managed/Cloud Provider: $asn_info${NC}"
    else
      echo "$host" >> hosts/scan_targets.txt
    fi
  done < hosts/resolved_hosts.txt
else
  echo -e "${RED}[-] No hosts were resolved to IPs.${NC}"
fi

scancount=$(wc -l < hosts/scan_targets.txt || echo 0)
echo -e "${GREEN}[+] Non-cloud targets identified: $scancount${NC}"

# --- Azure Tenant Discovery ---
echo -e "${BLUE}[+] Azure tenant discovery...${NC}"
azure_oidc=$(curl -s --max-time 10 "https://login.microsoftonline.com/$domain/.well-known/openid-configuration" || echo "{}")
if echo "$azure_oidc" | jq -e '.token_endpoint' >/dev/null 2>&1; then
  tenant_id=$(echo "$azure_oidc" | jq -r '.token_endpoint' | grep -oP '[0-9a-f-]{36}' | head -1)
  issuer=$(echo "$azure_oidc" | jq -r '.issuer // "N/A"')
  echo -e "${GREEN}[+] Azure tenant found: $tenant_id${NC}"
  {
    echo "Tenant ID : $tenant_id"
    echo "Issuer    : $issuer"
    echo ""
    echo "$azure_oidc" | jq .
  } > osint/azure_tenant.txt
else
  echo -e "${YELLOW}[*] No Azure tenant detected for $domain${NC}"
  echo "No Azure tenant detected." > osint/azure_tenant.txt
fi

# --- OSINT: WHOIS & DNS ---
echo -e "${BLUE}[+] Collecting WHOIS & DNS records...${NC}"
{
  echo "=== WHOIS ==="
  whois "$domain" 2>/dev/null || echo "WHOIS lookup failed"
} > osint/whois.txt

{
  echo "=== A Records ==="
  dig +short A "$domain" 2>/dev/null

  echo ""
  echo "=== MX Records ==="
  dig +short MX "$domain" 2>/dev/null

  echo ""
  echo "=== TXT Records ==="
  dig +short TXT "$domain" 2>/dev/null

  echo ""
  echo "=== NS Records ==="
  dig +short NS "$domain" 2>/dev/null

  echo ""
  echo "=== SOA Record ==="
  dig +short SOA "$domain" 2>/dev/null

  echo ""
  echo "=== CNAME Records ==="
  dig +short CNAME "$domain" 2>/dev/null
} > osint/dns_records.txt

echo -e "${GREEN}[+] OSINT collection complete${NC}"

# --- Final Report ---
RUNTIME=$(( SECONDS - START_TIME ))
report="report.md"
{
  echo "# Recon Report: $domain"
  echo "## Summary"
  echo "- Date: $(date -u)"
  echo "- Runtime: ${RUNTIME}s"
  echo "- Found: $subcount subdomains / $livecount live hosts"
  echo "- Non-cloud targets: $scancount"
  echo "- Technologies identified: $techcount"
  echo ""
  echo "## Azure Tenant"
  echo '```'
  cat osint/azure_tenant.txt
  echo '```'
  echo ""
  echo "## DNS Records"
  echo '```'
  cat osint/dns_records.txt
  echo '```'
} > "$report"

echo -e "${GREEN}[+] Recon Complete! Report saved to $project/$report${NC}"
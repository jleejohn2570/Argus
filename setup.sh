#!/bin/bash
set -euo pipefail

# Colors
GREEN='\033[1;32m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}Starting Argus Dependency Setup${NC}"

# 1. System Packages
echo -e "${YELLOW}Installing System Dependencies (Requires sudo)...${NC}"
sudo apt-get update && sudo apt-get install -y jq nmap whois dnsutils curl

# 2. Go Packages
echo -e "${YELLOW}Installing Go-based Security Tools...${NC}"

go_tools=(
    "github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
    "github.com/tomnomnom/assetfinder@latest"
    "github.com/projectdiscovery/httpx/cmd/httpx@latest"
    "github.com/projectdiscovery/dnsx/cmd/dnsx@latest"
    "github.com/projectdiscovery/katana/cmd/katana@latest"
    "github.com/sensepost/gowitness@latest"
)

for tool in "${go_tools[@]}"; do
    echo -e "${BLUE}Installing: $tool${NC}"
    go install "$tool"
done

echo -e "${GREEN}[+ Setup Complete! Ensure ~/go/bin is in your PATH. ]${NC}"
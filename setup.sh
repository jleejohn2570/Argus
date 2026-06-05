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
sudo apt-get update && sudo apt-get install -y jq nmap whois dnsutils curl wget

# 2. Go Installation
GO_MIN_VERSION="1.21"

install_go() {
    echo -e "${YELLOW}Fetching latest Go version...${NC}"
    GO_VERSION=$(curl -s https://go.dev/VERSION?m=text | head -1)
    GO_ARCHIVE="${GO_VERSION}.linux-amd64.tar.gz"
    echo -e "${BLUE}Downloading ${GO_VERSION}...${NC}"
    wget -q "https://go.dev/dl/${GO_ARCHIVE}" -O /tmp/"${GO_ARCHIVE}"
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf /tmp/"${GO_ARCHIVE}"
    rm /tmp/"${GO_ARCHIVE}"
    export PATH=$PATH:/usr/local/go/bin
    echo -e "${GREEN}Go ${GO_VERSION} installed.${NC}"
}

version_gte() {
    # Returns 0 (true) if $1 >= $2 (semver comparison)
    printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

if command -v go &>/dev/null; then
    CURRENT_GO=$(go version | awk '{print $3}' | sed 's/go//')
    if version_gte "$CURRENT_GO" "$GO_MIN_VERSION"; then
        echo -e "${GREEN}Go ${CURRENT_GO} already installed — skipping.${NC}"
    else
        echo -e "${YELLOW}Go ${CURRENT_GO} is below minimum ${GO_MIN_VERSION}. Upgrading...${NC}"
        install_go
    fi
else
    echo -e "${YELLOW}Go not found. Installing...${NC}"
    install_go
fi

# 3. Go Packages
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

echo -e "${YELLOW}Installing Go binaries to /usr/local/bin...${NC}"

GOBIN_DIR="${GOBIN:-$HOME/go/bin}"

for binary in "$GOBIN_DIR"/*; do
    if [ -f "$binary" ]; then
        sudo install -m 755 "$binary" /usr/local/bin/
    fi
done

echo -e "${GREEN}[+ Setup Complete! Ensure ~/go/bin is in your PATH. ]${NC}"

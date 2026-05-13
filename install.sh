#!/bin/bash
# ==========================================================
# IMAGITECH VPN AUTOSCRIPT
# Component: Master Orchestrator (install.sh)
# ==========================================================

GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

# REPLACE THIS with your actual GitHub Raw URL
REPO_URL="https://raw.githubusercontent.com/dexteree11/imagitech-vpn/main"

clear
echo -e "${CYAN}======================================================${NC}"
echo -e "${GREEN}      IMAGITECH ENTERPRISE DEPLOYMENT PIPELINE        ${NC}"
echo -e "${CYAN}======================================================${NC}"

if [ "${EUID}" -ne 0 ]; then
    echo -e "${RED}[FATAL] Please run as root.${NC}"
    exit 1
fi

echo -e "${CYAN}[*] Bootstrapping Deployment Directory...${NC}"
mkdir -p /root/imagitech-install
cd /root/imagitech-install

# Define the exact execution order
MODULES=(
    "setup.sh"
    "01-shield.sh"
    "02-xray.sh"
    "03-ssh-udp.sh"
    "04-db.sh"
    "05-menu.sh"
)

# Download all modules
echo -e "${CYAN}[*] Fetching Architecture Modules from Repository...${NC}"
for MODULE in "${MODULES[@]}"; do
    echo "  -> Downloading $MODULE"
    curl -sS -o "$MODULE" "$REPO_URL/modules/$MODULE"
    chmod +x "$MODULE"
done

# Execute the pipeline sequentially
echo -e "\n${GREEN}[*] Initiating Execution Pipeline...${NC}"

for MODULE in "${MODULES[@]}"; do
    echo -e "\n${CYAN}>>> Executing: $MODULE <<<${NC}"
    ./"$MODULE"
    
    # Check if the module failed
    if [ $? -ne 0 ]; then
        echo -e "${RED}[FATAL] $MODULE failed to execute properly. Halting installation.${NC}"
        exit 1
    fi
done

# Cleanup
cd /root
rm -rf /root/imagitech-install

echo -e "\n${CYAN}======================================================${NC}"
echo -e "${GREEN}      IMAGITECH DEPLOYMENT COMPLETE                   ${NC}"
echo -e "${CYAN}======================================================${NC}"
echo -e "Type ${GREEN}menu${NC} to access your enterprise dashboard."

#!/bin/bash
# ==========================================================
# IMAGITECH VPN AUTOSCRIPT (ISP BYPASS EDITION)
# Component: Master Orchestrator (install.sh)
# ==========================================================

GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

# ==========================================================
# ⚠️ CRITICAL: CHANGE 'dexteree11' TO YOUR GITHUB USERNAME
# IF YOU CHANGED YOUR REPOSITORY NAME, UPDATE IT HERE TOO.
# ==========================================================
REPO_URL="https://raw.githubusercontent.com/dexteree11/imagitech-vpn/main"

clear
echo -e "${CYAN}======================================================${NC}"
echo -e "${GREEN}      IMAGITECH ISP BYPASS DEPLOYMENT PIPELINE        ${NC}"
echo -e "${CYAN}======================================================${NC}"

if [ "${EUID}" -ne 0 ]; then
    echo -e "${RED}[FATAL] Please run as root. (Type: sudo su -)${NC}"
    exit 1
fi

echo -e "${CYAN}[*] Bootstrapping Deployment Directory...${NC}"
mkdir -p /root/imagitech-install
cd /root/imagitech-install

# Define the exact execution order for the ISP Bypass Stack
MODULES=(
    "01-setup.sh"
    "02-routing.sh"
    "03-sidecars.sh"
    "04-db.sh"
    "05-menu.sh"
)

# Download all modules
echo -e "${CYAN}[*] Fetching Architecture Modules from Repository...${NC}"
for MODULE in "${MODULES[@]}"; do
    echo "  -> Downloading $MODULE"
    # Using the /modules/ path as established in your repo structure
    curl -sS -o "$MODULE" "$REPO_URL/modules/$MODULE"
    
    if [ ! -s "$MODULE" ] || grep -q "404: Not Found" "$MODULE"; then
        echo -e "${RED}[FATAL] Failed to download $MODULE. Check your GitHub URL and folder structure.${NC}"
        exit 1
    fi
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

# Move the Menu to its permanent location BEFORE cleanup
cp 05-menu.sh /usr/local/sbin/menu
chmod +x /usr/local/sbin/menu

# Cleanup and Menu Binding
cd /root
# Move the menu directly into the global bin folder before deleting the temp files
mv /root/imagitech-install/05-menu.sh /usr/bin/menu
chmod +x /usr/bin/menu

rm -rf /root/imagitech-install

echo -e "\n${CYAN}======================================================${NC}"
echo -e "${GREEN}      IMAGITECH DEPLOYMENT COMPLETE                   ${NC}"
echo -e "${CYAN}======================================================${NC}"
echo -e "Type ${GREEN}menu${NC} to access your enterprise dashboard."

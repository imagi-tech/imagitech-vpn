#!/bin/bash
# ==========================================================
# IMAGITECH VPN AUTOSCRIPT
# Component: Master Setup & Pre-Flight OS Fixer
# ==========================================================

# --- 1. Color Palette & UI Variables ---
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

clear
echo -e "${CYAN}┌────────────────────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│${NC} ${BOLD}${GREEN}        IMAGITECH VPN AUTOSCRIPT INSTALLER         ${NC} ${CYAN}│${NC}"
echo -e "${CYAN}│${NC} ${ORANGE}        Enterprise Infrastructure Deployment       ${NC} ${CYAN}│${NC}"
echo -e "${CYAN}└────────────────────────────────────────────────────────┘${NC}"
echo ""

# --- 2. Execution Constraints ---
if [ "${EUID}" -ne 0 ]; then
    echo -e "${RED}[FATAL] This script must be executed as the root user.${NC}"
    exit 1
fi

if [ ! -f /etc/os-release ]; then
    echo -e "${RED}[FATAL] Unsupported OS. Only Ubuntu/Debian are supported.${NC}"
    exit 1
fi

# --- 3. The Lock Breaker (Aggressive OS Cleanup) ---
echo -e "${CYAN}[*] Initiating Aggressive Pre-Flight OS Cleanup...${NC}"

# Stop background automated upgrades that lock the package manager
systemctl stop apt-daily.timer 2>/dev/null
systemctl stop apt-daily-upgrade.timer 2>/dev/null

# Forcefully remove stuck apt/dpkg locks
rm -f /var/lib/apt/lists/lock
rm -f /var/cache/apt/archives/lock
rm -f /var/lib/dpkg/lock
rm -f /var/lib/dpkg/lock-frontend

# Repair broken dpkg configurations silently
dpkg --configure -a > /dev/null 2>&1

# --- 4. Package Synchronization & Core Dependencies ---
echo -e "${CYAN}[*] Synchronizing Repositories & Forcing Dependencies...${NC}"

DEBIAN_FRONTEND=noninteractive apt-get update -y --fix-missing

# Unsilenced installation so we can guarantee dependencies install
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends --fix-broken \
    curl wget jq cron iptables lsof tar unzip uuid-runtime \
    software-properties-common ca-certificates openssl

DEBIAN_FRONTEND=noninteractive apt-get update -y > /dev/null 2>&1

# Install the absolute baseline tools required for the rest of the modules
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    curl wget jq cron iptables lsof tar unzip uuid-runtime \
    software-properties-common ca-certificates > /dev/null 2>&1

# --- 5. Interactive Infrastructure Data Collection ---
echo -e "\n${ORANGE}--- DOMAIN & DNS CONFIGURATION ---${NC}"
echo -e "Please provide your routing domains. Do not include 'http://'."

# Loop until a valid A record is provided
while true; do
    read -p "Primary VPN Domain (A Record) [e.g., vpn.imagitech.online]: " DOMAIN
    if [[ -z "$DOMAIN" ]]; then
        echo -e "${RED}[!] Domain cannot be empty.${NC}"
    else
        break
    fi
done

# Loop until a valid NS record is provided (No hardcoding as requested)
while true; do
    read -p "Nameserver Domain (NS Record for DNSTT) [e.g., ns.imagitech.online]: " NS_DOMAIN
    if [[ -z "$NS_DOMAIN" ]]; then
        echo -e "${RED}[!] Nameserver Domain cannot be empty.${NC}"
    else
        break
    fi
done

# --- 6. Scaffolding the Local Architecture ---
echo -e "\n${CYAN}[*] Building Imagitech Architecture Directories...${NC}"

# Core directories for our modular script ecosystem
mkdir -p /etc/imagitech/{core,modules,conf,tls,db}
mkdir -p /var/log/imagitech
mkdir -p /usr/local/sbin

# Save user inputs to secure configuration files for downstream modules
echo "$DOMAIN" > /etc/imagitech/conf/domain.txt
echo "$NS_DOMAIN" > /etc/imagitech/conf/ns_domain.txt

echo -e "${GREEN}[+] Imagitech scaffolding complete.${NC}"
echo -e "${GREEN}[+] Primary Domain mapped to : $DOMAIN${NC}"
echo -e "${GREEN}[+] NS Domain mapped to      : $NS_DOMAIN${NC}"
echo -e "\n${ORANGE}[*] Pre-flight checks passed. Ready to initiate protocol modules...${NC}"

# ==========================================================
# Future Execution Pipeline goes here:
# e.g., curl -sL https://.../01-haproxy.sh | bash
# ==========================================================

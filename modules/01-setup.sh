#!/bin/bash
# ==========================================================
# IMAGITECH VPN AUTOSCRIPT (ISP BYPASS EDITION)
# Component: 01 - Master Setup & Dependencies
# ==========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

clear
echo -e "${CYAN}======================================================${NC}"
echo -e "${GREEN}${BOLD}     IMAGITECH PREMIUM SSH & WS DEPLOYMENT            ${NC}"
echo -e "${CYAN}======================================================${NC}"
echo ""

if [ "${EUID}" -ne 0 ]; then
    echo -e "${RED}[FATAL] This script must be executed as the root user.${NC}"
    exit 1
fi

# --- 1. Aggressive OS Cleanup ---
echo -e "${CYAN}[*] Breaking apt locks and cleaning OS...${NC}"
systemctl stop apt-daily.timer 2>/dev/null
systemctl stop apt-daily-upgrade.timer 2>/dev/null
rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend
dpkg --configure -a > /dev/null 2>&1

# --- 2. Core Dependencies (The Premium Stack) ---
echo -e "${CYAN}[*] Installing ISP Bypass Dependencies (Stunnel, Dante, Python)...${NC}"
DEBIAN_FRONTEND=noninteractive apt-get update -y --fix-missing > /dev/null 2>&1

DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends --fix-broken \
    curl wget cron iptables lsof tar unzip uuid-runtime \
    software-properties-common ca-certificates openssl \
    dropbear stunnel4 dante-server python3 make cmake gcc g++ build-essential > /dev/null 2>&1

# --- 3. Domain Collection ---
echo -e "\n${ORANGE}--- DOMAIN & DNS CONFIGURATION ---${NC}"
while true; do
    read -p "Primary VPN Domain (e.g., mtn.imagitech.online): " DOMAIN
    if [[ -n "$DOMAIN" ]]; then break; fi
done

while true; do
    read -p "Nameserver Domain (e.g., ns-mtn.imagitech.online): " NS_DOMAIN
    if [[ -n "$NS_DOMAIN" ]]; then break; fi
done

# --- 4. Directory Scaffolding ---
echo -e "\n${CYAN}[*] Building Imagitech Directories...${NC}"
mkdir -p /etc/imagitech/{conf,tls,db}
mkdir -p /usr/local/sbin
mkdir -p /etc/stunnel
mkdir -p /etc/systemd/system

echo "$DOMAIN" > /etc/imagitech/conf/domain.txt
echo "$NS_DOMAIN" > /etc/imagitech/conf/ns_domain.txt

# --- 5. Request Let's Encrypt Certificate (For Stunnel 443) ---
echo -e "${CYAN}[*] Requesting TLS Certificate for $DOMAIN...${NC}"
systemctl stop nginx 2>/dev/null
systemctl stop apache2 2>/dev/null

curl -sL https://get.acme.sh | sh -s email=admin@${DOMAIN} > /dev/null 2>&1
/root/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone --keylength ec-256 --force > /dev/null 2>&1
/root/.acme.sh/acme.sh --installcert -d "$DOMAIN" --ecc \
    --fullchain-file /etc/imagitech/tls/fullchain.cer \
    --key-file /etc/imagitech/tls/private.key > /dev/null 2>&1

# Stunnel requires a combined PEM file
cat /etc/imagitech/tls/fullchain.cer /etc/imagitech/tls/private.key > /etc/imagitech/tls/stunnel.pem
chmod 600 /etc/imagitech/tls/stunnel.pem

echo "/bin/false" >> /etc/shells

# --- 6. Apply TCP BBR (Crucial for HTTP Injector Speeds) ---
echo -e "${CYAN}[*] Optimizing Kernel with TCP BBR...${NC}"
cat <<EOF >> /etc/sysctl.conf
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
sysctl -p > /dev/null 2>&1

echo -e "\n${GREEN}[+] Setup Complete. Ready for Protocol Modules.${NC}"

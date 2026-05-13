#!/bin/bash
# ==========================================================
# IMAGITECH VPN AUTOSCRIPT (ISP BYPASS EDITION)
# Component: 05 - Master Dashboard & Payload Generator
# ==========================================================

DB_PATH="/etc/imagitech/db/imagitech.db"
DOMAIN=$(cat /etc/imagitech/conf/domain.txt 2>/dev/null || echo "Unknown")
NS_DOMAIN=$(cat /etc/imagitech/conf/ns_domain.txt 2>/dev/null || echo "Unknown")
PUB_KEY=$(cat /etc/imagitech/conf/dnstt_pub.txt 2>/dev/null || echo "Unknown")
IP_ADDR=$(curl -sS ipv4.icanhazip.com)

# --- 1. ANSI Color Palette & Box Drawing ---
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

draw_top() { echo -e "${CYAN}┌────────────────────────────────────────────────────────┐${NC}"; }
draw_mid() { echo -e "${CYAN}├────────────────────────────────────────────────────────┤${NC}"; }
draw_bot() { echo -e "${CYAN}└────────────────────────────────────────────────────────┘${NC}"; }

# --- 2. Live Data Harvesters ---
get_system_stats() {
    OS_INFO=$(cat /etc/os-release | grep -w PRETTY_NAME | cut -d= -f2 | tr -d '"')
    UPTIME=$(uptime -p | sed 's/up //')
    RAM_USED=$(free -m | awk 'NR==2{print $3}')
    RAM_TOTAL=$(free -m | awk 'NR==2{print $2}')
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}')
}

get_db_stats() {
    TOTAL_USERS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users;")
    ACTIVE_USERS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users WHERE status='ACTIVE';")
    EXPIRED_USERS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users WHERE status='EXPIRED';")
}

check_service() {
    if systemctl is-active --quiet "$1"; then
        echo -e "${GREEN}[ON]${NC}"
    else
        echo -e "${RED}[OFF]${NC}"
    fi
}

# --- 3. The Interactive Dashboard (HUD) ---
show_dashboard() {
    clear
    get_system_stats
    get_db_stats

    draw_top
    echo -e "${CYAN}│${NC} ${BOLD}${GREEN}          IMAGITECH ISP BYPASS DASHBOARD          ${NC} ${CYAN}│${NC}"
    draw_mid
    echo -e "  ${ORANGE}✦ Server Uptime${NC}   : ${GREEN}${UPTIME}${NC}"
    echo -e "  ${ORANGE}✦ Operating Sys${NC}   : ${CYAN}${OS_INFO}${NC}"
    echo -e "  ${ORANGE}✦ RAM / CPU Load${NC}  : ${GREEN}${RAM_USED}MB / ${RAM_TOTAL}MB${NC}  |  ${CYAN}${CPU_USAGE}${NC}"
    echo -e "  ${ORANGE}✦ Primary Domain${NC}  : ${GREEN}${DOMAIN}${NC}"
    draw_mid
    
    # ISP Bypass Status Matrix
    printf "  ${CYAN}WS-Proxy: %b   Stunnel : %b   Dropbear: %b${NC}\n" "$(check_service ws-proxy)" "$(check_service stunnel4)" "$(check_service dropbear)"
    printf "  ${CYAN}Dante   : %b   BadVPN  : %b   DNSTT   : %b${NC}\n" "$(check_service danted)" "$(check_service badvpn-7100)" "$(check_service dnstt)"
    draw_mid
    
    # The Database Overview
    echo -e "  ${CYAN}[ Database Overview ]${NC}"
    echo -e "  Active Users : ${GREEN}${ACTIVE_USERS}${NC} / ${TOTAL_USERS}    Expired : ${RED}${EXPIRED_USERS}${NC}"
    draw_mid
    
    echo -e "  ${CYAN}[01]${NC} Create VPN Account    ${CYAN}[04]${NC} View Online Users"
    echo -e "  ${CYAN}[02]${NC} Delete VPN Account    ${CYAN}[05]${NC} Restart Services"
    echo -e "  ${CYAN}[03]${NC} Renew Expiry          ${CYAN}[00]${NC} Exit"
    draw_bot
    echo ""
    read -p " Select Option : " opt

    case $opt in
        1) execute_add_user ;;
        2) execute_del_user ;;
        5) execute_restart ;;
        0) exit 0 ;;
        *) show_dashboard ;;
    esac
}

# --- 4. Sub-Routines (Headless Capabilities) ---
execute_add_user() {
    clear
    echo -e "${CYAN}=== CREATE ISP BYPASS ACCOUNT ===${NC}"
    read -p "Username: " USERNAME
    read -p "Password: " PASSWORD
    read -p "Duration (Days): " DAYS

    EXP_DATE=$(date -d "+${DAYS} days" +"%Y-%m-%d %H:%M:%S")

    # 1. Create Linux PAM User (Dropbear / SOCKS5 / DNSTT)
    useradd -e "$(date -d "+${DAYS} days" +"%Y-%m-%d")" -s /bin/false -M "$USERNAME" >/dev/null 2>&1
    echo "$USERNAME:$PASSWORD" | chpasswd

    # 2. Insert to SQLite Database
    sqlite3 "$DB_PATH" "INSERT INTO users (username, password, expiry_date) VALUES ('$USERNAME', '$PASSWORD', '$EXP_DATE');"

    clear
    
    echo -e "${GREEN}Account Provisioned Successfully!${NC}"
    echo -e "Copy the details below for your client:"
    echo -e "\n${CYAN}IP            :${NC} ${IP_ADDR}"
    echo -e "${CYAN}Host          :${NC} ${DOMAIN}"
    echo -e "${CYAN}Nameserver    :${NC} ${NS_DOMAIN}"
    echo -e "${CYAN}PubKey        :${NC} ${PUB_KEY}"
    echo -e "${CYAN}OpenSSH       :${NC} 22"
    echo -e "${CYAN}SSH-WS        :${NC} 80"
    echo -e "${CYAN}Custom SSH    :${NC} 8880"
    echo -e "${CYAN}SSH-SSL-WS    :${NC} 443"
    echo -e "${CYAN}Dropbear      :${NC} 109, 143"
    echo -e "${CYAN}UDPGW         :${NC} 7100-7300"
    echo -e "${CYAN}SOCKS5        :${NC} 1080"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}SSH-80        :${NC} ${DOMAIN}:80@${USERNAME}:${PASSWORD}"
    echo -e "${CYAN}SSH-8880      :${NC} ${DOMAIN}:8880@${USERNAME}:${PASSWORD}"
    echo -e "${CYAN}SSH-443       :${NC} ${DOMAIN}:443@${USERNAME}:${PASSWORD}"
    echo -e "${CYAN}SOCKS5        :${NC} ${DOMAIN}:1080:${USERNAME}:${PASSWORD}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${ORANGE}(Payload WSS)${NC}"
    echo -e "GET wss://bug.com [protocol][crlf]Host: ${DOMAIN}[crlf]Upgrade: websocket[crlf][crlf]"
    echo -e "\n${ORANGE}(Payload WS - Port 80)${NC}"
    echo -e "GET / HTTP/1.1[crlf]Host: ${DOMAIN}[crlf]Upgrade: websocket[crlf][crlf]"
    echo -e "\n${ORANGE}(Payload Custom Bypass - Port 8880)${NC}"
    echo -e "GET http://${DOMAIN}:8880 HTTP/1.1[crlf]Host: [ISP_BUG_HOST][crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]"
    echo -e "\n${CYAN}Expires On    :${NC} ${EXP_DATE}"
    
    echo ""
    read -n 1 -s -r -p "Press any key to return to dashboard..."
    show_dashboard
}

execute_del_user() {
    clear
    echo -e "${CYAN}=== DELETE VPN ACCOUNT ===${NC}"
    read -p "Username: " USERNAME
    
    userdel -f "$USERNAME" >/dev/null 2>&1
    sqlite3 "$DB_PATH" "DELETE FROM users WHERE username='$USERNAME';"
    
    echo -e "${GREEN}[+] User $USERNAME deleted from system and database.${NC}"
    sleep 2
    show_dashboard
}

execute_restart() {
    echo -e "\n${CYAN}[*] Gracefully restarting routing engine and sidecars...${NC}"
    systemctl restart dropbear ws-proxy stunnel4 danted dnstt badvpn-7100 badvpn-7200 badvpn-7300
    echo -e "${GREEN}[+] Services optimized and reloaded.${NC}"
    sleep 2
    show_dashboard
}

# --- 5. The Dual-Mode CLI Router ---
if [[ -n "$1" ]]; then
    case "$1" in
        add) execute_add_user ;;
        del) execute_del_user ;;
        restart) execute_restart ;;
        *) echo -e "${RED}Unknown command. Valid options: add, del, restart${NC}" ;;
    esac
else
    show_dashboard
fi

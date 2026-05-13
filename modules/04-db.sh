#!/bin/bash
# ==========================================================
# IMAGITECH VPN AUTOSCRIPT (ISP BYPASS EDITION)
# Component: 04 - Database & Expiry Automation
# ==========================================================

CYAN='\033[0;36m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${CYAN}[*] Phase 4: Deploying SQLite Database & Automation Enforcer...${NC}"

# --- 1. Install SQLite3 ---
DEBIAN_FRONTEND=noninteractive apt-get install -y sqlite3 > /dev/null 2>&1

DB_PATH="/etc/imagitech/db/imagitech.db"

# --- 2. Initialize the Relational Schema ---
echo -e "${CYAN}  -> Initializing Identity Database...${NC}"

sqlite3 "$DB_PATH" <<EOF
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    password TEXT NOT NULL,
    expiry_date TEXT NOT NULL,
    status TEXT DEFAULT 'ACTIVE',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
EOF

chmod 600 "$DB_PATH"

# --- 3. Build the Expiration Enforcer ---
# This script locks the Linux account so they cannot use Dropbear or SOCKS5
echo -e "${CYAN}  -> Compiling Account Enforcer Daemon...${NC}"

cat <<'EOF' > /usr/local/sbin/imagitech-enforcer
#!/bin/bash
DB_PATH="/etc/imagitech/db/imagitech.db"
TODAY=$(date +%s)

# Read all active users from SQLite
sqlite3 -separator '|' "$DB_PATH" "SELECT username, expiry_date FROM users WHERE status='ACTIVE';" | while read -r line; do
    USERNAME=$(echo "$line" | awk -F'|' '{print $1}')
    EXPIRY=$(echo "$line" | awk -F'|' '{print $2}')
    
    EXP_SEC=$(date -d "$EXPIRY" +%s)

    # Check Date Expiry
    if [ "$TODAY" -ge "$EXP_SEC" ]; then
        # 1. Lock the Linux PAM account (Blocks SSH, WS, and SOCKS5)
        usermod -L "$USERNAME" >/dev/null 2>&1
        
        # 2. Change shell to prevent any terminal access
        usermod -s /bin/false "$USERNAME" >/dev/null 2>&1
        
        # 3. Kill any active SSH/Dropbear sessions immediately
        pkill -u "$USERNAME" >/dev/null 2>&1
        
        # 4. Update Database Status
        sqlite3 "$DB_PATH" "UPDATE users SET status='EXPIRED' WHERE username='$USERNAME';"
    fi
done
EOF

chmod +x /usr/local/sbin/imagitech-enforcer

# --- 4. Automate via Cron ---
echo -e "${CYAN}  -> Injecting Automation into System Cron...${NC}"

crontab -l 2>/dev/null | grep -v "imagitech-enforcer" > /tmp/cron.bak
# Run the enforcer every hour on the hour
echo "0 * * * * /usr/local/sbin/imagitech-enforcer >/dev/null 2>&1" >> /tmp/cron.bak
crontab /tmp/cron.bak
rm /tmp/cron.bak

echo -e "${GREEN}[+] Database & Automation Engine Deployed.${NC}"
echo -e "  - SQLite Schema  : Active"
echo -e "  - Cron Enforcer  : Running strictly every hour"

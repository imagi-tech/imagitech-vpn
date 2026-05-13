#!/bin/bash
# ==========================================================
# IMAGITECH VPN AUTOSCRIPT
# Component: 04 - The Database & Automation Engine
# ==========================================================

CYAN='\033[0;36m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${CYAN}[*] Phase 5: Deploying SQLite3 Database & Cron Enforcers...${NC}"

# --- 1. Install SQLite3 ---
DEBIAN_FRONTEND=noninteractive apt-get install -y sqlite3 > /dev/null 2>&1

DB_PATH="/etc/imagitech/db/imagitech.db"

# --- 2. Initialize the Relational Schema ---
echo -e "${CYAN}  -> Initializing Unified User Database...${NC}"

sqlite3 "$DB_PATH" <<EOF
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    uuid TEXT,
    password TEXT,
    expiry_date TEXT NOT NULL,
    data_limit_bytes INTEGER DEFAULT 0,  -- 0 means unlimited
    data_used_bytes INTEGER DEFAULT 0,
    status TEXT DEFAULT 'ACTIVE',        -- ACTIVE, EXPIRED, LOCKED
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT
);

-- Insert default settings
INSERT OR IGNORE INTO settings (key, value) VALUES ('tg_bot_token', 'UNSET');
INSERT OR IGNORE INTO settings (key, value) VALUES ('tg_chat_id', 'UNSET');
EOF

chmod 600 "$DB_PATH"

# --- 3. Build the Bandwidth Harvester & Enforcer (imagitech-monitor) ---
# This script will be called by Cron every 5 minutes.
echo -e "${CYAN}  -> Compiling API Harvester & Quota Enforcer...${NC}"

cat <<'EOF' > /usr/local/sbin/imagitech-monitor
#!/bin/bash
DB_PATH="/etc/imagitech/db/imagitech.db"
TODAY=$(date +%s)

# 1. Harvest Xray Bandwidth via API
# We query the local gRPC API we exposed on port 10085 in Phase 3
XRAY_STATS=$(/usr/local/xray/xray api statsquery -server=127.0.0.1:10085 2>/dev/null)

if [[ -n "$XRAY_STATS" ]]; then
    # Loop through all active users in the database
    for USER in $(sqlite3 "$DB_PATH" "SELECT username FROM users WHERE status='ACTIVE';"); do
        
        # Extract downlink and uplink from the API JSON output using jq
        DOWNLINK=$(echo "$XRAY_STATS" | jq -r ".stat[] | select(.name == \"user>>>${USER}>>>traffic>>>downlink\") | .value" 2>/dev/null)
        UPLINK=$(echo "$XRAY_STATS" | jq -r ".stat[] | select(.name == \"user>>>${USER}>>>traffic>>>uplink\") | .value" 2>/dev/null)
        
        # Default to 0 if null
        DOWNLINK=${DOWNLINK:-0}
        UPLINK=${UPLINK:-0}
        TOTAL_USED=$((DOWNLINK + UPLINK))

        # Update DB only if traffic was actually used
        if [ "$TOTAL_USED" -gt 0 ]; then
            sqlite3 "$DB_PATH" "UPDATE users SET data_used_bytes = $TOTAL_USED WHERE username = '$USER';"
        fi
    done
fi

# 2. Enforce Expirations and Quotas
sqlite3 -separator '|' "$DB_PATH" "SELECT username, expiry_date, data_limit_bytes, data_used_bytes FROM users WHERE status='ACTIVE';" | while read -r line; do
    USERNAME=$(echo "$line" | awk -F'|' '{print $1}')
    EXPIRY=$(echo "$line" | awk -F'|' '{print $2}')
    LIMIT=$(echo "$line" | awk -F'|' '{print $3}')
    USED=$(echo "$line" | awk -F'|' '{print $4}')
    
    EXP_SEC=$(date -d "$EXPIRY" +%s)
    SHOULD_LOCK=0
    REASON=""

    # Check Date Expiry
    if [ "$TODAY" -ge "$EXP_SEC" ]; then
        SHOULD_LOCK=1
        REASON="EXPIRED"
    # Check Data Quota (If limit is not 0/Unlimited)
    elif [ "$LIMIT" -gt 0 ] && [ "$USED" -ge "$LIMIT" ]; then
        SHOULD_LOCK=1
        REASON="QUOTA_REACHED"
    fi

    if [ "$SHOULD_LOCK" -eq 1 ]; then
        # Lock Linux PAM account (SSH/OpenVPN/DNSTT)
        usermod -L "$USERNAME" >/dev/null 2>&1
        pkill -u "$USERNAME" >/dev/null 2>&1
        
        # Remove from Xray via API (Zero Downtime)
        # Note: In a complete script, you send a RemoveUserRequest gRPC call here.
        # For safety, we will just update the database status. The actual removal
        # logic will be bridged in our unified user-manager tool.
        
        sqlite3 "$DB_PATH" "UPDATE users SET status='$REASON' WHERE username='$USERNAME';"
        
        # Optional: Trigger Telegram Notification via curl here
    fi
done
EOF

chmod +x /usr/local/sbin/imagitech-monitor

# --- 4. Automate via Cron ---
echo -e "${CYAN}  -> Injecting Automation into System Cron...${NC}"

# Clear old monitor jobs to ensure idempotency
crontab -l 2>/dev/null | grep -v "imagitech-monitor" > /tmp/cron.bak
# Run the harvester and enforcer every 10 minutes
echo "*/10 * * * * /usr/local/sbin/imagitech-monitor >/dev/null 2>&1" >> /tmp/cron.bak
crontab /tmp/cron.bak
rm /tmp/cron.bak

echo -e "${GREEN}[+] Unified Database & Automation Engine Deployed.${NC}"
echo -e "${GREEN}[+] Background Enforcer active (Checks Quotas & Expiry every 10 min).${NC}"

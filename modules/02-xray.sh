#!/bin/bash
# ==========================================================
# IMAGITECH VPN AUTOSCRIPT
# Component: 02 - The Xray Engine (Reality, WS, gRPC)
# ==========================================================

CYAN='\033[0;36m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${CYAN}[*] Phase 3: Deploying Xray-Core & VLESS-Reality...${NC}"

# --- 1. Download and Install Xray-Core ---
mkdir -p /usr/local/xray
mkdir -p /etc/xray
mkdir -p /var/log/xray

echo -e "${CYAN}  -> Fetching latest Xray release...${NC}"
# Bypassing jq entirely for maximum compatibility
XRAY_VERSION=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

if [[ -z "$XRAY_VERSION" ]]; then
    XRAY_VERSION="v1.8.4" # Hardcoded safety fallback
fi

wget -q -O /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-64.zip"
unzip -q /tmp/xray.zip -d /tmp/xray_extract
mv /tmp/xray_extract/xray /usr/local/xray/xray
mv /tmp/xray_extract/geoip.dat /usr/local/xray/geoip.dat
mv /tmp/xray_extract/geosite.dat /usr/local/xray/geosite.dat
chmod +x /usr/local/xray/xray
rm -rf /tmp/xray*

# --- 2. Generate VLESS-Reality Keys ---
# Reality uses x25519 cryptographic keys instead of standard TLS certs.
echo -e "${CYAN}  -> Generating Reality Cryptographic Keys...${NC}"

# Generate Private and Public Key
KEYS=$(/usr/local/xray/xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | awk '/Private key:/ {print $3}')
PUBLIC_KEY=$(echo "$KEYS" | awk '/Public key:/ {print $3}')

# Generate a random 8-character hex Short ID
SHORT_ID=$(openssl rand -hex 8)

# Save the public key and short ID so our dashboard can show them to users later
echo "$PUBLIC_KEY" > /etc/imagitech/conf/reality_pub.txt
echo "$SHORT_ID" > /etc/imagitech/conf/reality_short.txt

# --- 3. Build the Master config.json ---
echo -e "${CYAN}  -> Compiling API-Enabled JSON Configuration...${NC}"

cat <<EOF > /etc/xray/config.json
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "warning"
  },
  "api": {
    "services": [
      "HandlerService",
      "StatsService",
      "LoggerService"
    ],
    "tag": "api"
  },
  "stats": {},
  "policy": {
    "levels": {
      "0": {
        "statsUserUplink": true,
        "statsUserDownlink": true
      }
    },
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true
    }
  },
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": 10085,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1"
      },
      "tag": "api"
    },
    {
      "listen": "127.0.0.1",
      "port": 10001,
      "protocol": "vless",
      "tag": "inbound-vless-reality",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "www.microsoft.com:443",
          "xver": 0,
          "serverNames": [
            "www.microsoft.com"
          ],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": [
            "$SHORT_ID"
          ]
        },
        "sockopt": {
          "acceptProxyProtocol": true
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 10003,
      "protocol": "vmess",
      "tag": "inbound-vmess-ws",
      "settings": {
        "clients": []
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vmessws"
        }
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 10004,
      "protocol": "trojan",
      "tag": "inbound-trojan-ws",
      "settings": {
        "clients": []
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/trojanws"
        }
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 10005,
      "protocol": "vless",
      "tag": "inbound-vless-grpc",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {
          "serviceName": "vless-grpc"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "rules": [
      {
        "inboundTag": ["api"],
        "outboundTag": "api",
        "type": "field"
      },
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "blocked"
      }
    ]
  }
}
EOF

# --- 4. Create the Systemd Service ---
cat <<EOF > /etc/systemd/system/xray.service
[Unit]
Description=Xray Engine (IMAGITECH)
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/xray/xray run -config /etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

# --- 5. Finalize ---
systemctl daemon-reload
systemctl enable xray > /dev/null 2>&1
systemctl restart xray

echo -e "${GREEN}[+] Xray-Core deployed successfully.${NC}"
echo -e "${GREEN}[+] Inbounds Activated: Reality (10001), VMESS WS (10003), Trojan WS (10004), VLESS gRPC (10005).${NC}"
echo -e "${GREEN}[+] gRPC API listening on 10085 for zero-downtime injection.${NC}"

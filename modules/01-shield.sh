#!/bin/bash
# ==========================================================
# IMAGITECH VPN AUTOSCRIPT
# Component: 01 - The Shield (HAProxy & Let's Encrypt)
# ==========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}[*] Phase 1: Deploying The Shield (HAProxy & TLS)...${NC}"

# Read the domain we saved during setup.sh
DOMAIN=$(cat /etc/imagitech/conf/domain.txt)
EMAIL="admin@${DOMAIN}"

# --- 1. Install HAProxy & Cert dependencies ---
DEBIAN_FRONTEND=noninteractive apt-get install -y haproxy socat > /dev/null 2>&1

# Stop HAProxy temporarily so Port 80 is free for Let's Encrypt
systemctl stop haproxy

# --- 2. Acquire TLS Certificate (acme.sh) ---
echo -e "${CYAN}[*] Requesting SSL/TLS Certificate for $DOMAIN...${NC}"

# Install acme.sh safely
if [ ! -f "/root/.acme.sh/acme.sh" ]; then
    curl -sL https://get.acme.sh | sh -s email=$EMAIL > /dev/null 2>&1
fi

# Issue Cert using Standalone HTTP-01 challenge on Port 80
/root/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone \
    --keylength ec-256 --force > /dev/null 2>&1

# Install Certs to our custom directory
/root/.acme.sh/acme.sh --installcert -d "$DOMAIN" --ecc \
    --fullchain-file /etc/imagitech/tls/fullchain.cer \
    --key-file /etc/imagitech/tls/private.key > /dev/null 2>&1

# --- EMERGENCY TLS FALLBACK ---
# If acme.sh failed (DNS not propagated), the pem file will be empty or missing.
if [ ! -s "/etc/imagitech/tls/haproxy.pem" ]; then
    echo -e "${RED}[!] Let's Encrypt failed (DNS not propagated?). Generating Fallback Cert...${NC}"
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/imagitech/tls/private.key \
        -out /etc/imagitech/tls/fullchain.cer \
        -subj "/C=US/ST=NY/L=NY/O=Imagitech/CN=$DOMAIN" > /dev/null 2>&1
    
    cat /etc/imagitech/tls/fullchain.cer /etc/imagitech/tls/private.key > /etc/imagitech/tls/haproxy.pem
fi

# HAProxy requires the public and private keys to be merged into one .pem file
cat /etc/imagitech/tls/fullchain.cer /etc/imagitech/tls/private.key > /etc/imagitech/tls/haproxy.pem
chmod 600 /etc/imagitech/tls/haproxy.pem

# --- 3. Build HAProxy Configuration ---
echo -e "${CYAN}[*] Compiling Layer 4/Layer 7 HAProxy Configuration...${NC}"

cat <<EOF > /etc/haproxy/haproxy.cfg
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon
    maxconn 100000

defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server  50000

# ==========================================
# STAGE 1: Layer 4 (TCP Front Door)
# ==========================================
frontend public_443
    bind *:443
    mode tcp
    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }

    # If SNI matches your domain, send to Stage 2 (Internal SSL Terminator)
    use_backend internal_layer7 if { req_ssl_sni -i $DOMAIN }
    
    # Otherwise, it must be a VLESS-Reality probe (Foreign SNI). Send to Xray.
    default_backend xray_reality

backend xray_reality
    mode tcp
    server xray_core 127.0.0.1:10001 send-proxy

backend internal_layer7
    mode tcp
    server local_layer7 127.0.0.1:8443

# ==========================================
# STAGE 2: Layer 7 (HTTP/WebSocket Multiplexer)
# ==========================================
frontend internal_8443
    bind 127.0.0.1:8443 ssl crt /etc/imagitech/tls/haproxy.pem alpn h2,http/1.1
    mode http
    option httplog
    
    # WebSocket Path Routing
    acl is_ssh path_beg /sshws
    acl is_vmess path_beg /vmessws
    acl is_trojan path_beg /trojanws
    
    # gRPC Routing (ALPN h2)
    acl is_grpc ssl_fc_alpn -i h2
    
    use_backend ssh_ws_backend if is_ssh
    use_backend vmess_ws_backend if is_vmess
    use_backend trojan_ws_backend if is_trojan
    use_backend grpc_backend if is_grpc
    
    # If no paths match, serve a fake 403 Forbidden page
    default_backend camouflage_web

# --- Backend Definitions ---
backend ssh_ws_backend
    mode http
    server ssh_ws 127.0.0.1:10002

backend vmess_ws_backend
    mode http
    server vmess_ws 127.0.0.1:10003

backend trojan_ws_backend
    mode http
    server trojan_ws 127.0.0.1:10004

backend grpc_backend
    mode http
    server xray_grpc 127.0.0.1:10005 h2

backend camouflage_web
    mode http
    errorfile 403 /etc/haproxy/errors/403.http
EOF

# Ensure error directory exists for the camouflage
mkdir -p /etc/haproxy/errors
echo -e "HTTP/1.1 403 Forbidden\r\n\r\n<h1>403 Forbidden</h1><hr>nginx" > /etc/haproxy/errors/403.http

# --- 4. Start Services ---
systemctl restart haproxy
systemctl enable haproxy > /dev/null 2>&1

echo -e "${GREEN}[+] HAProxy Dual-Layer Shield deployed successfully.${NC}"
echo -e "${GREEN}[+] TLS Certificate generated for $DOMAIN.${NC}"

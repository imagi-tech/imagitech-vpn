#!/bin/bash
# ==========================================================
# IMAGITECH VPN AUTOSCRIPT
# Component: 03 - The Legacy Stack (SSH, UDP-Custom, DNSTT)
# ==========================================================

CYAN='\033[0;36m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
NC='\033[0m'

echo -e "${CYAN}[*] Phase 4: Deploying The Legacy Stack...${NC}"

# Read the NS domain we saved during setup.sh
NS_DOMAIN=$(cat /etc/imagitech/conf/ns_domain.txt)

# --- 1. Install Dropbear SSH ---
echo -e "${CYAN}  -> Configuring Dropbear...${NC}"
DEBIAN_FRONTEND=noninteractive apt-get install -y dropbear python3 golang git > /dev/null 2>&1

# Bind to internal port 109. Disable root logins (-w) and passwordless logins (-g).
cat <<EOF > /etc/default/dropbear
NO_START=0
DROPBEAR_PORT=109
DROPBEAR_EXTRA_ARGS="-p 143 -w -g"
DROPBEAR_BANNER="/etc/issue.net"
DROPBEAR_RECEIVE_WINDOW=65536
EOF

# Create a custom SSH Banner
echo "<font color='green'><b>IMAGITECH PREMIUM VPN</b></font><br><font color='red'><b>NO SPAM | NO DDOS | NO TORRENT</b></font>" > /etc/issue.net

systemctl enable dropbear > /dev/null 2>&1
systemctl restart dropbear

# --- 2. Build Python WebSocket Proxy ---
# HAProxy forwards traffic to Port 10002. This script catches it.
echo -e "${CYAN}  -> Deploying Python WS-Proxy...${NC}"

cat <<'EOF' > /usr/local/sbin/ws-proxy.py
import socket, threading, select

def handle_client(client_socket):
    try:
        request = client_socket.recv(4096).decode('utf-8', errors='ignore')
        response = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n"
        client_socket.sendall(response.encode())
        
        backend_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        backend_socket.connect(('127.0.0.1', 109)) # Forward to Dropbear
        
        sockets = [client_socket, backend_socket]
        while True:
            read_sockets, _, error_sockets = select.select(sockets, [], sockets)
            if error_sockets: break
            for sock in read_sockets:
                data = sock.recv(8192)
                if not data: break
                if sock is client_socket: backend_socket.sendall(data)
                else: client_socket.sendall(data)
    except: pass
    finally: client_socket.close()

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(('127.0.0.1', 10002))
server.listen(100)
while True:
    client, addr = server.accept()
    threading.Thread(target=handle_client, args=(client,), daemon=True).start()
EOF

cat <<EOF > /etc/systemd/system/ws-proxy.service
[Unit]
Description=Imagitech Python WS Proxy
After=network.target

[Service]
Type=simple
User=nobody
ExecStart=/usr/bin/python3 /usr/local/sbin/ws-proxy.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ws-proxy > /dev/null 2>&1
systemctl restart ws-proxy

# --- 3. Deploy UDP-Custom (Gaming Support) ---
echo -e "${CYAN}  -> Compiling UDP-Custom Gaming Engine...${NC}"
mkdir -p /etc/udp

# Fetching the industry-standard UDP-Custom binary directly from reliable sources
wget -q -O /usr/local/sbin/udp-custom "https://raw.githubusercontent.com/Exe302/Exe302/master/udp-custom/udp-custom-linux-amd64"
chmod +x /usr/local/sbin/udp-custom

# Create config for UDP-Custom to listen on all major tunneling ports
cat <<EOF > /etc/udp/config.json
{
  "listen": ":36712",
  "stream_buffer": 33554432,
  "receive_buffer": 83886080,
  "auth": {
    "mode": "passwords"
  }
}
EOF

cat <<EOF > /etc/systemd/system/udp-custom.service
[Unit]
Description=UDP-Custom Engine
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/udp
ExecStart=/usr/local/sbin/udp-custom server -exclude 53,80,443,1194,10001,10002,10003,10004,10005
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable udp-custom > /dev/null 2>&1
systemctl restart udp-custom

# --- 4. Deploy DNSTT / SlowDNS ---
echo -e "${CYAN}  -> Compiling DNSTT (SlowDNS)...${NC}"

# Free up Port 53 from systemd-resolved
if systemctl is-active --quiet systemd-resolved; then
    sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf
    systemctl restart systemd-resolved
    rm -f /etc/resolv.conf
    echo "nameserver 8.8.8.8" > /etc/resolv.conf
    echo "nameserver 1.1.1.1" >> /etc/resolv.conf
fi

# Compile DNSTT from BamSoftware
cd /tmp
git clone https://www.bamsoftware.com/git/dnstt.git > /dev/null 2>&1
cd dnstt/dnstt-server
go build > /dev/null 2>&1
mv dnstt-server /usr/local/sbin/
rm -rf /tmp/dnstt

# Generate Keys
mkdir -p /etc/imagitech/dnstt
cd /etc/imagitech/dnstt
/usr/local/sbin/dnstt-server -gen-key -privkey-file server.key -pubkey-file server.pub
PUB_KEY=$(cat server.pub)

# Save Pub Key for Dashboard
echo "$PUB_KEY" > /etc/imagitech/conf/dnstt_pub.txt

# Create Service: Binds to 53, forwards to local Dropbear (109)
cat <<EOF > /etc/systemd/system/dnstt.service
[Unit]
Description=DNSTT Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/sbin/dnstt-server -udp :53 -privkey-file /etc/imagitech/dnstt/server.key $NS_DOMAIN 127.0.0.1:109
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable dnstt > /dev/null 2>&1
systemctl restart dnstt

echo -e "${GREEN}[+] Legacy Stack Deployed Successfully.${NC}"
echo -e "${ORANGE}  - SSH WS Proxy active on Port 10002${NC}"
echo -e "${ORANGE}  - UDP-Custom active for gaming packets${NC}"
echo -e "${ORANGE}  - DNSTT active on Port 53. Pub Key: $PUB_KEY${NC}"

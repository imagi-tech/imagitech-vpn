#!/bin/bash
# ==========================================================
# IMAGITECH VPN AUTOSCRIPT (ISP BYPASS EDITION)
# Component: 02 - The Routing Engine (WS Proxy, Dropbear, Stunnel)
# ==========================================================

CYAN='\033[0;36m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${CYAN}[*] Phase 2: Deploying Routing Engine (WS Proxy & Stunnel)...${NC}"

DOMAIN=$(cat /etc/imagitech/conf/domain.txt 2>/dev/null || echo "localhost")

# --- 1. Configure Dropbear SSH ---
echo -e "${CYAN}  -> Hardening and Binding Dropbear Backend...${NC}"

# Configure Dropbear to listen on 109 & 143. Disable root logins for security.
cat <<EOF > /etc/default/dropbear
NO_START=0
DROPBEAR_PORT=109
DROPBEAR_EXTRA_ARGS="-p 143 -w -g"
DROPBEAR_BANNER="/etc/issue.net"
DROPBEAR_RECEIVE_WINDOW=65536
EOF

# Create the Premium Banner shown in the HTTP Injector Logs
echo "<font color='green'><b>IMAGITECH ISP BYPASS VPN</b></font><br><font color='red'><b>NO SPAM | NO DDOS | NO TORRENT</b></font>" > /etc/issue.net

systemctl enable dropbear > /dev/null 2>&1
systemctl restart dropbear

# --- 2. Build the Custom Python WebSocket Multiplexer ---
echo -e "${CYAN}  -> Compiling Custom Payload Multi-Port Proxy...${NC}"

cat <<'EOF' > /usr/local/sbin/ws-proxy.py
import socket, threading, select, sys

def handle_client(client_socket):
    try:
        # Receive the initial payload from HTTP Injector/Custom
        request = client_socket.recv(8192)
        if not request:
            client_socket.close()
            return

        req_str = request.decode('utf-8', errors='ignore')
        
        # If the packet looks like an HTTP/WS request, send the 101 Response to trick the ISP
        if "HTTP/" in req_str or "Upgrade:" in req_str or "upgrade:" in req_str:
            response = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n"
            client_socket.sendall(response.encode())
        
        # Connect internally to the Dropbear SSH backend
        backend_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        backend_socket.connect(('127.0.0.1', 109))
        
        # If it wasn't an HTTP request (pure SSH direct), forward the original packet
        if "HTTP/" not in req_str:
            backend_socket.sendall(request)

        # Bi-directional tunnel loop
        sockets = [client_socket, backend_socket]
        while True:
            read_sockets, _, error_sockets = select.select(sockets, [], sockets)
            if error_sockets: break
            for sock in read_sockets:
                data = sock.recv(8192)
                if not data: break
                if sock is client_socket: backend_socket.sendall(data)
                else: client_socket.sendall(data)
    except Exception as e:
        pass
    finally:
        client_socket.close()

def start_server(port):
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('0.0.0.0', port))
    server.listen(100)
    while True:
        client, addr = server.accept()
        threading.Thread(target=handle_client, args=(client,), daemon=True).start()

if __name__ == '__main__':
    # Thread 1: Port 80 (Standard WS)
    threading.Thread(target=start_server, args=(80,), daemon=True).start()
    # Thread 2: Port 8880 (Custom ISP Bypass WS)
    threading.Thread(target=start_server, args=(8880,), daemon=True).start()
    
    # Keep daemon alive
    import time
    while True: time.sleep(100)
EOF

# Create the Systemd Service for the Python Proxy
cat <<EOF > /etc/systemd/system/ws-proxy.service
[Unit]
Description=Imagitech WS Multiplexer
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /usr/local/sbin/ws-proxy.py
Restart=always
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ws-proxy > /dev/null 2>&1
systemctl restart ws-proxy

# --- 3. Configure Stunnel4 (Port 443 to 80 Bridge) ---
echo -e "${CYAN}  -> Configuring Stunnel SSL Decryption Layer...${NC}"

cat <<EOF > /etc/stunnel/stunnel.conf
pid = /var/run/stunnel.pid
cert = /etc/imagitech/tls/stunnel.pem
client = no
socket = a:SO_REUSEADDR=1
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1

[ssh-ws-ssl]
accept = 443
connect = 127.0.0.1:80
EOF

# Enable Stunnel to start on boot
sed -i 's/ENABLED=0/ENABLED=1/g' /etc/default/stunnel4

systemctl enable stunnel4 > /dev/null 2>&1
systemctl restart stunnel4

echo -e "${GREEN}[+] Routing Engine Deployed Successfully.${NC}"
echo -e "  - OpenSSH Core : Dropbear [109, 143]"
echo -e "  - SSH-WS       : Python Proxy [80]"
echo -e "  - SSH-WS Custom: Python Proxy [8880]"
echo -e "  - SSH-WS SSL   : Stunnel -> Python Proxy [443]"

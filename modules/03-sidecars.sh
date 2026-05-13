#!/bin/bash
# ==========================================================
# IMAGITECH VPN AUTOSCRIPT (ISP BYPASS EDITION)
# Component: 03 - The Sidecars (Dante, BadVPN, DNSTT)
# ==========================================================

CYAN='\033[0;36m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
NC='\033[0m'

echo -e "${CYAN}[*] Phase 3: Deploying Sidecar Protocols...${NC}"

NS_DOMAIN=$(cat /etc/imagitech/conf/ns_domain.txt 2>/dev/null || echo "ns.imagitech.online")
IFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)

# --- 1. Compile & Deploy BadVPN-UDPGW (Gaming Support) ---
echo -e "${CYAN}  -> Compiling BadVPN for UDP Forwarding...${NC}"
cd /tmp
git clone https://github.com/ambrop72/badvpn.git > /dev/null 2>&1
cd badvpn
mkdir build && cd build
cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 > /dev/null 2>&1
make install > /dev/null 2>&1
rm -rf /tmp/badvpn

# Create multiple UDPGW instances for load balancing (7100, 7200, 7300)
for PORT in 7100 7200 7300; do
cat <<EOF > /etc/systemd/system/badvpn-${PORT}.service
[Unit]
Description=BadVPN UDPGW on port ${PORT}
After=network.target

[Service]
Type=simple
User=nobody
ExecStart=/usr/local/bin/badvpn-udpgw --listen-addr 127.0.0.1:${PORT} --max-clients 500 --max-connections-for-client 10
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable badvpn-${PORT} > /dev/null 2>&1
systemctl restart badvpn-${PORT}
done

# --- 2. Configure Dante SOCKS5 Proxy ---
echo -e "${CYAN}  -> Configuring Dante SOCKS5 Server...${NC}"

cat <<EOF > /etc/danted.conf
logoutput: syslog
user.privileged: root
user.unprivileged: nobody

# Bind to Port 1080 natively
internal: 0.0.0.0 port = 1080
external: ${IFACE}

# Require standard PAM SSH User/Pass authentication
socksmethod: username
clientmethod: none

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error
}
EOF

systemctl enable danted > /dev/null 2>&1
systemctl restart danted

# --- 3. Compile & Deploy DNSTT (SlowDNS) ---
echo -e "${CYAN}  -> Compiling DNSTT (SlowDNS)...${NC}"

# Free up Port 53 from Ubuntu's systemd-resolved
if systemctl is-active --quiet systemd-resolved; then
    sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf
    systemctl restart systemd-resolved
    rm -f /etc/resolv.conf
    echo "nameserver 8.8.8.8" > /etc/resolv.conf
    echo "nameserver 1.1.1.1" >> /etc/resolv.conf
fi

# Install Go compiler and build DNSTT
DEBIAN_FRONTEND=noninteractive apt-get install -y golang git > /dev/null 2>&1
cd /tmp
git clone https://www.bamsoftware.com/git/dnstt.git > /dev/null 2>&1
cd dnstt/dnstt-server
go build > /dev/null 2>&1
mv dnstt-server /usr/local/sbin/
rm -rf /tmp/dnstt

# Generate DNSTT Keys
mkdir -p /etc/imagitech/tls
cd /etc/imagitech/tls
/usr/local/sbin/dnstt-server -gen-key -privkey-file dnstt.key -pubkey-file dnstt.pub
PUB_KEY=$(cat dnstt.pub)
echo "$PUB_KEY" > /etc/imagitech/conf/dnstt_pub.txt

# Create DNSTT Systemd Service (Binding to 53 and 5300)
cat <<EOF > /etc/systemd/system/dnstt.service
[Unit]
Description=DNSTT Server
After=network.target

[Service]
Type=simple
User=root
# We bind to 5300 here, and use iptables to route 53 to 5300
ExecStart=/usr/local/sbin/dnstt-server -udp :5300 -privkey-file /etc/imagitech/tls/dnstt.key ${NS_DOMAIN} 127.0.0.1:109
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Route Port 53 to 5300 natively via iptables
iptables -I INPUT -p udp --dport 5300 -j ACCEPT
iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300
# Save iptables so it persists across reboots
DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent > /dev/null 2>&1
netfilter-persistent save > /dev/null 2>&1

systemctl daemon-reload
systemctl enable dnstt > /dev/null 2>&1
systemctl restart dnstt

echo -e "${GREEN}[+] Sidecar Protocols Deployed Successfully.${NC}"
echo -e "  - UDPGW        : BadVPN [7100, 7200, 7300]"
echo -e "  - SOCKS5       : Dante [1080]"
echo -e "  - SlowDNS      : DNSTT [53, 5300] -> ${NS_DOMAIN}"
echo -e "  - DNSTT PubKey : ${ORANGE}${PUB_KEY}${NC}"

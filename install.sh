#!/bin/bash
# SMART PORTAL V6 PRODUCTION INSTALLER
# Fixes: Forces Docker to rebuild missing iptables chains by deleting docker0 bridge.
# Usage: sudo bash install.sh

if [ "$EUID" -ne 0 ]; then echo "Run as root."; exit 1; fi

APP_DIR="/opt/smart-portal"
echo "--- INSTALLING SMART PORTAL V6 ---"

# 1. Install System Dependencies
echo "[1/7] Installing System Packages..."
apt-get update -q
apt-get install -y build-essential curl git hostapd dnsmasq iptables-persistent docker.io conntrack iproute2 nodejs npm openssl

# 2. Setup Directory
echo "[2/7] Setting up Directory..."
mkdir -p $APP_DIR
cp -r . $APP_DIR/
cd $APP_DIR

# 3. Install Node Modules
echo "[3/7] Installing Node Modules..."
npm install
# npm audit fix --force || true 

# 4. Generate Secrets & Config
echo "[4/7] Configuring Secrets..."
if [ ! -f .env ]; then
    DB_PASS=$(openssl rand -hex 12)
    SESSION_SECRET=$(openssl rand -hex 32)
    
    cat > .env <<EOF
DB_USER=portal_admin
DB_HOST=127.0.0.1
DB_NAME=smart_portal
DB_PASS=$DB_PASS
DB_PORT=5432
SESSION_SECRET=$SESSION_SECRET
GATEWAY_IP=192.168.10.1
DOMAIN=portal.wifi
WLAN_IFACE=wlan0
ADMIN_USER=jeffery-uhrick
EOF
    echo "Generated new .env file."
fi
source .env

# 5. Configure Networking
echo "[5/7] Configuring Network..."
systemctl unmask NetworkManager
systemctl enable NetworkManager
systemctl start NetworkManager
mkdir -p /etc/NetworkManager/conf.d
echo -e "[keyfile]\nunmanaged-devices=interface-name:wlan0" > /etc/NetworkManager/conf.d/99-portal.conf
systemctl reload NetworkManager

cp config/hostapd.conf /etc/hostapd/hostapd.conf
cp config/dnsmasq.conf /etc/dnsmasq.conf
sed -i 's|#DAEMON_CONF=""|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-portal.conf
sysctl -p /etc/sysctl.d/99-portal.conf

# 6. Database Setup
echo "[6/7] Starting Database..."

# --- NUCLEAR NETWORK FIX ---
echo "Repairing Docker Network Stack..."
systemctl stop docker
# Force delete the bridge so Docker MUST recreate it + firewall rules
ip link del docker0 2>/dev/null || true
systemctl start docker

echo "Waiting for Docker Firewall Chains..."
# Loop until the firewall chain actually exists
for i in {1..10}; do
    if iptables -L DOCKER >/dev/null 2>&1; then
        echo "Docker Chain detected."
        break
    fi
    echo "Waiting for Docker network... ($i/10)"
    sleep 2
done
# ---------------------------

docker stop portal_db 2>/dev/null || true
docker rm portal_db 2>/dev/null || true
docker volume rm portal_data 2>/dev/null || true

# Launch Database
docker run -d --name portal_db --restart always \
  -e POSTGRES_PASSWORD=$DB_PASS \
  -e POSTGRES_USER=$DB_USER \
  -e POSTGRES_DB=$DB_NAME \
  -p 5432:5432 \
  -v portal_data:/var/lib/postgresql/data \
  postgres:alpine

echo "Waiting for Database to initialize..."
sleep 10 

# Run Schema Init
node src/init_db.js

# 7. Service Setup
echo "[7/7] Enabling Service..."
chmod +x src/startup.sh
cp config/smart-portal.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable smart-portal
systemctl start smart-portal

echo "--- INSTALL COMPLETE ---"
echo "Admin User: jeffery-uhrick"
echo "Admin Pass: Jeffery#3218"
echo "URL:        http://portal.wifi"
echo "Wifi SSID:  Uhrick-Home-Wifi"
echo "You can check status with: sudo bash verify_install.sh"
#!/bin/bash
# SMART PORTAL V6 PRODUCTION INSTALLER
# Fixes: Auto-generates secrets BEFORE starting DB to prevent password mismatch.
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

# 4. Generate Secrets & Config (The Fix)
echo "[4/7] Configuring Secrets..."
if [ ! -f .env ]; then
    # Generate random passwords if .env doesn't exist
    DB_PASS=$(openssl rand -hex 12)
    ADMIN_PASS="Jeffery#3218" # Default admin password
    SESSION_SECRET=$(openssl rand -hex 32)
    
    cat > .env <<EOF
DB_USER=portal_admin
DB_HOST=127.0.0.1
DB_NAME=smart_portal
DB_PASS=$DB_PASS
DB_PORT=5432
SESSION_SECRET=$SESSION_SECRET
GATEWAY_IP=192.168.10.1
DOMAIN=home.local
WLAN_IFACE=wlan0
ADMIN_USER=jeffery-uhrick
EOF
    echo "Generated new .env file."
fi

# Load the secrets immediately so Docker uses them
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
# Cleanup old containers to ensure fresh start
docker stop portal_db 2>/dev/null || true
docker rm portal_db 2>/dev/null || true
# Launch with the LOADED password
docker run -d --name portal_db --restart always \
  -e POSTGRES_PASSWORD=$DB_PASS \
  -e POSTGRES_USER=$DB_USER \
  -e POSTGRES_DB=$DB_NAME \
  -p 5432:5432 \
  -v portal_data:/var/lib/postgresql/data \
  postgres:alpine

echo "Waiting for Database to initialize..."
sleep 10 # Wait for Postgres to actually boot

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
echo "Wifi SSID:  Uhrick-Home-Wifi"
echo "You can check status with: sudo bash verify_install.sh"
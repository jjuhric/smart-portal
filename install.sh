#!/bin/bash
# SMART PORTAL V6 INSTALLER
# Usage: sudo bash install.sh

if [ "$EUID" -ne 0 ]; then echo "Run as root."; exit 1; fi

APP_DIR="/opt/smart-portal"
echo "--- INSTALLING SMART PORTAL V6 ---"

# 1. Install System Dependencies
echo "[1/6] Installing System Packages..."
apt-get update -q
apt-get install -y build-essential curl git hostapd dnsmasq iptables-persistent docker.io conntrack iproute2 nodejs npm

# 2. Setup Directory
echo "[2/6] Setting up Directory..."
mkdir -p $APP_DIR
# Copy everything from current folder to /opt/smart-portal
cp -r . $APP_DIR/
cd $APP_DIR

# 3. Install Node Modules
echo "[3/6] Installing Node Modules..."
npm install

# 4. Configure Networking
echo "[4/6] Configuring Network..."
# Stop interfering services
systemctl unmask NetworkManager
systemctl enable NetworkManager
systemctl start NetworkManager
# Tell NetworkManager to ignore wlan0
mkdir -p /etc/NetworkManager/conf.d
echo -e "[keyfile]\nunmanaged-devices=interface-name:wlan0" > /etc/NetworkManager/conf.d/99-portal.conf
systemctl reload NetworkManager

# Copy Configs
cp config/hostapd.conf /etc/hostapd/hostapd.conf
cp config/dnsmasq.conf /etc/dnsmasq.conf
# Point HostAPD to config
sed -i 's|#DAEMON_CONF=""|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
# Enable Forwarding
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-portal.conf
sysctl -p /etc/sysctl.d/99-portal.conf

# 5. Database Setup
echo "[5/6] Starting Database..."
docker stop portal_db 2>/dev/null || true
docker rm portal_db 2>/dev/null || true
# Note: We use the password from .env if available, else default
if [ -f .env ]; then source .env; else DB_PASS="dbpassword"; fi
docker run -d --name portal_db --restart always \
  -e POSTGRES_PASSWORD=$DB_PASS \
  -e POSTGRES_USER=portal_admin \
  -e POSTGRES_DB=smart_portal \
  -p 5432:5432 \
  -v portal_data:/var/lib/postgresql/data \
  postgres:alpine

# Wait for DB then Init Schema
sleep 5
npm run init-db

# 6. Service Setup
echo "[6/6] Enabling Service..."
chmod +x src/startup.sh
cp config/smart-portal.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable smart-portal
systemctl start smart-portal

echo "--- INSTALL COMPLETE ---"
echo "1. Edit /opt/smart-portal/.env with your real secrets."
echo "2. Reboot."
#!/bin/bash
# SMART PORTAL UNINSTALLER
# Restores the Raspberry Pi to normal networking state.
# Usage: sudo bash uninstall.sh

if [ "$EUID" -ne 0 ]; then echo "Run as root (sudo)."; exit 1; fi

echo "=============================================="
echo "   WARNING: SMART PORTAL UNINSTALLER"
echo "=============================================="
echo "This will DELETE the database and restore Wi-Fi."
read -p "Are you sure? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then exit 1; fi

echo "--- 1. STOPPING SERVICES ---"
systemctl stop smart-portal 2>/dev/null
systemctl stop hostapd 2>/dev/null
systemctl stop dnsmasq 2>/dev/null
systemctl disable smart-portal 2>/dev/null
rm /etc/systemd/system/smart-portal.service 2>/dev/null
systemctl daemon-reload

echo "--- 2. REMOVING DATABASE ---"
if command -v docker &> /dev/null; then
    docker stop portal_db 2>/dev/null
    docker rm portal_db 2>/dev/null
    # CRITICAL: Delete the volume so next install is fresh
    docker volume rm portal_data 2>/dev/null
fi

echo "--- 3. RESTORING NETWORK CONFIG ---"
rm -f /etc/NetworkManager/conf.d/99-portal.conf
rm -f /etc/sysctl.d/99-portal.conf
sed -i 's|DAEMON_CONF="/etc/hostapd/hostapd.conf"|#DAEMON_CONF=""|' /etc/default/hostapd
rm -f /etc/hostapd/hostapd.conf
rm -f /etc/dnsmasq.conf

iptables -F
iptables -t nat -F
tc qdisc del dev wlan0 root 2>/dev/null

echo "--- 4. REMOVING APPLICATION FILES ---"
rm -rf /opt/smart-portal

echo "--- 5. RESTORING CONNECTIVITY ---"
ip addr flush dev wlan0
systemctl restart NetworkManager

echo "UNINSTALL COMPLETE. Reboot recommended."
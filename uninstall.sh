#!/bin/bash
# SMART PORTAL UNINSTALLER
# Restores the Raspberry Pi to normal networking state.
# Usage: sudo bash uninstall.sh

if [ "$EUID" -ne 0 ]; then echo "Run as root (sudo)."; exit 1; fi

echo "=============================================="
echo "   WARNING: SMART PORTAL UNINSTALLER"
echo "=============================================="
echo "This will:"
echo "1. DELETE the 'smart_portal' database and all user logs."
echo "2. REMOVE the application files."
echo "3. RESTORE standard Wi-Fi networking (Client Mode)."
echo ""
read -p "Are you sure? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstall cancelled."
    exit 1
fi

echo "--- 1. STOPPING SERVICES ---"
systemctl stop smart-portal 2>/dev/null
systemctl stop hostapd 2>/dev/null
systemctl stop dnsmasq 2>/dev/null
systemctl disable smart-portal 2>/dev/null
rm /etc/systemd/system/smart-portal.service 2>/dev/null
systemctl daemon-reload

echo "--- 2. REMOVING DATABASE ---"
# Check if docker exists first
if command -v docker &> /dev/null; then
    docker stop portal_db 2>/dev/null
    docker rm portal_db 2>/dev/null
    docker volume rm portal_data 2>/dev/null
fi

echo "--- 3. RESTORING NETWORK CONFIG ---"
# Remove the "Ignore wlan0" rule so NetworkManager takes over again
rm -f /etc/NetworkManager/conf.d/99-portal.conf
rm -f /etc/sysctl.d/99-portal.conf

# Revert HostAPD default config pointer
sed -i 's|DAEMON_CONF="/etc/hostapd/hostapd.conf"|#DAEMON_CONF=""|' /etc/default/hostapd

# Remove config files we placed
rm -f /etc/hostapd/hostapd.conf
rm -f /etc/dnsmasq.conf

# Flush Firewall Rules (Captive Portal Traps)
iptables -F
iptables -t nat -F
# Clear Traffic Control (Speed Limits)
tc qdisc del dev wlan0 root 2>/dev/null

echo "--- 4. REMOVING APPLICATION FILES ---"
rm -rf /opt/smart-portal

echo "--- 5. RESTORING CONNECTIVITY ---"
# Flush the static IP (192.168.10.1)
ip addr flush dev wlan0
# Restart NetworkManager to auto-connect to home Wi-Fi
systemctl restart NetworkManager

echo "=============================================="
echo "   UNINSTALL COMPLETE"
echo "=============================================="
echo "The system is now a standard Raspberry Pi."
echo "You may need to reboot to ensure all network states are clean."
#!/bin/bash
cd /opt/smart-portal
if [ -f .env ]; then source .env; fi

# Default Fallbacks
WLAN=${WLAN_IFACE:-wlan0}
GATEWAY=${GATEWAY_IP:-192.168.10.1}

# 1. IP Setup
ip link set dev $WLAN down
ip addr flush dev $WLAN
ip addr add $GATEWAY/24 dev $WLAN
ip link set dev $WLAN up

# 2. Restart Services
systemctl restart hostapd
systemctl restart dnsmasq

# 3. Firewall Plumbing
iptables -F
iptables -t nat -F
echo 1 > /proc/sys/net/ipv4/ip_forward

# Auto-detect Internet Interface
INTERNET=$(ip route | grep default | awk '{print $5}' | head -n1)
[ -z "$INTERNET" ] && INTERNET="end0"
iptables -t nat -A POSTROUTING -o $INTERNET -j MASQUERADE

# Captive Portal Traps
iptables -A FORWARD -p udp --dport 53 -j ACCEPT
iptables -A FORWARD -p tcp --dport 53 -j ACCEPT
iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -t nat -A PREROUTING -i $WLAN -p tcp --dport 80 -j DNAT --to-destination $GATEWAY:80
iptables -A FORWARD -i $WLAN -p tcp --dport 443 -j REJECT --reject-with tcp-reset
iptables -A FORWARD -i $WLAN -j DROP

# 4. Traffic Control Root
tc qdisc del dev $WLAN root 2>/dev/null
tc qdisc add dev $WLAN root handle 1: htb default 10
tc class add dev $WLAN parent 1: classid 1:1 htb rate 100mbit
tc class add dev $WLAN parent 1:1 classid 1:10 htb rate 95mbit ceil 100mbit

# 5. Start App
/usr/bin/node src/server.js
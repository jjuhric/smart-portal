#!/bin/bash
# ==============================================================================
# SMART PORTAL - DEEP SYSTEM VERIFICATION SUITE
# Checks: Dependencies, Services, Network, Firewall, Database Schema, Web App, TC
# Usage: sudo bash verify_install.sh
# ==============================================================================

if [ "$EUID" -ne 0 ]; then echo "❌ Error: Run as root (sudo)."; exit 1; fi

# --- CONFIGURATION & COLORS ---
ENV_FILE="/opt/smart-portal/.env"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Load Environment Variables
if [ -f "$ENV_FILE" ]; then
    source $ENV_FILE
else
    echo -e "${RED}[CRITICAL] Missing .env file at $ENV_FILE${NC}"
    exit 1
fi

# Helper Functions
pass() { echo -e "[ ${GREEN}PASS${NC} ] $1"; }
fail() { echo -e "[ ${RED}FAIL${NC} ] $1"; }
warn() { echo -e "[ ${YELLOW}WARN${NC} ] $1"; }
info() { echo -e "${BLUE}ℹ $1${NC}"; }

echo -e "\n${BLUE}=== PHASE 1: SYSTEM DEPENDENCIES ===${NC}"
# Check if critical binaries exist in PATH
DEPS=("node" "npm" "docker" "hostapd" "dnsmasq" "iptables" "tc" "git" "curl")
MISSING_DEPS=0
for cmd in "${DEPS[@]}"; do
    if command -v $cmd &> /dev/null; then
        pass "Dependency found: $cmd"
    else
        fail "Missing dependency: $cmd"
        ((MISSING_DEPS++))
    fi
done
[ $MISSING_DEPS -gt 0 ] && exit 1

echo -e "\n${BLUE}=== PHASE 2: SERVICES STATUS ===${NC}"
# Check Systemd Services
SERVICES=("smart-portal" "hostapd" "dnsmasq" "docker" "NetworkManager")
for svc in "${SERVICES[@]}"; do
    STATUS=$(systemctl is-active $svc)
    if [ "$STATUS" == "active" ]; then
        pass "Service active: $svc"
    else
        fail "Service $svc is $STATUS"
    fi
done

echo -e "\n${BLUE}=== PHASE 3: NETWORK INTERFACE ===${NC}"
# Check Interface Existence
if ip link show $WLAN_IFACE &> /dev/null; then
    pass "Interface $WLAN_IFACE exists"
else
    fail "Interface $WLAN_IFACE NOT found"
fi

# Check Static IP Assignment
CURRENT_IP=$(ip -4 addr show $WLAN_IFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)
if [ "$CURRENT_IP" == "$GATEWAY_IP" ]; then
    pass "IP Address Correct: $CURRENT_IP"
else
    fail "IP Address Mismatch. Expected $GATEWAY_IP, found $CURRENT_IP"
fi

# Check IP Forwarding (Kernel Level)
FWD=$(cat /proc/sys/net/ipv4/ip_forward)
if [ "$FWD" == "1" ]; then
    pass "Kernel IP Forwarding is ON"
else
    fail "Kernel IP Forwarding is OFF (Clients will have no internet)"
fi

echo -e "\n${BLUE}=== PHASE 4: FIREWALL & ROUTING ===${NC}"
# Check Masquerade (NAT)
NAT_RULES=$(iptables -t nat -S POSTROUTING)
if echo "$NAT_RULES" | grep -q "MASQUERADE"; then
    pass "NAT Masquerading Rule Found"
else
    fail "Missing NAT Rule (Internet sharing broken)"
fi

# Check Captive Portal Trap (DNAT)
DNAT_RULES=$(iptables -t nat -S PREROUTING)
if echo "$DNAT_RULES" | grep -q "DNAT.*:80"; then
    pass "Captive Portal HTTP Trap (Port 80 -> Local) Found"
else
    fail "Captive Portal Trap Missing (Users won't be redirected)"
fi

# Check DNS Allow Rule
FWD_RULES=$(iptables -S FORWARD)
if echo "$FWD_RULES" | grep -q "udp.*dpt:53.*ACCEPT"; then
    pass "DNS Traffic Allowed"
else
    fail "DNS Traffic Blocked (Clients can't resolve URLs)"
fi

echo -e "\n${BLUE}=== PHASE 5: DATABASE INTEGRITY ===${NC}"
# Check Container Running
if docker ps | grep -q "portal_db"; then
    pass "Postgres Container Running"
    
    # Check Connection & Tables
    TABLES=$(docker exec -i portal_db psql -U $DB_USER -d $DB_NAME -t -c "SELECT table_name FROM information_schema.tables WHERE table_schema='public';")
    
    REQUIRED_TABLES=("users" "devices" "logs" "vouchers")
    for table in "${REQUIRED_TABLES[@]}"; do
        if echo "$TABLES" | grep -q "$table"; then
            pass "Table exists: $table"
        else
            fail "Missing Table: $table"
        fi
    done
else
    fail "Postgres Container NOT Running"
fi

echo -e "\n${BLUE}=== PHASE 6: TRAFFIC CONTROL (SPEED LIMITS) ===${NC}"
# Check Root Qdisc
TC_OUT=$(tc qdisc show dev $WLAN_IFACE)
if echo "$TC_OUT" | grep -q "htb 1: root"; then
    pass "Root HTB Qdisc Active"
else
    fail "Root Traffic Control Missing (Speed limits won't work)"
fi

# Check Default Classes
TC_CLASSES=$(tc class show dev $WLAN_IFACE)
if echo "$TC_CLASSES" | grep -q "class htb 1:1 "; then
    pass "Parent Class (1:1) Exists"
else
    fail "Parent Class Missing"
fi

echo -e "\n${BLUE}=== PHASE 7: WEB APPLICATION ===${NC}"
# Check Node Process
if pgrep -f "node src/server.js" > /dev/null; then
    pass "Node.js Process Running"
else
    fail "Node.js Process NOT Found"
fi

# Check HTTP Response
HTTP_TEST=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:80)
if [ "$HTTP_TEST" == "200" ]; then
    pass "Web Server responding 200 OK"
    
    # Content Check
    CONTENT=$(curl -s http://localhost:80)
    if echo "$CONTENT" | grep -q "Uhrick"; then
        pass "Login Page Content Verified ('Uhrick' found)"
    else
        warn "Login Page Content Mismatch (Could not find 'Uhrick')"
    fi
elif [ "$HTTP_TEST" == "302" ]; then
    pass "Web Server Redirecting (302) - Normal for Captive Portal"
else
    fail "Web Server Error (HTTP $HTTP_TEST)"
fi

echo -e "\n${BLUE}=== PHASE 8: DNS RESOLUTION ===${NC}"
# Check Dnsmasq Config Syntax
if dnsmasq --test &> /dev/null; then
    pass "Dnsmasq Config Syntax OK"
else
    fail "Dnsmasq Config Error"
fi

# Verify Local Domain (Dynamic Check)
# We use the domain defined in .env
RESOLVED_IP=$(getent hosts $DOMAIN | awk '{ print $1 }')
if [ "$RESOLVED_IP" == "$GATEWAY_IP" ]; then
    pass "Domain $DOMAIN resolves to $RESOLVED_IP"
else
    fail "Domain Resolution Failed (Expected $GATEWAY_IP, Got: '$RESOLVED_IP')"
fi

echo -e "\n=============================================="
echo -e "   VERIFICATION COMPLETE"
echo -e "=============================================="
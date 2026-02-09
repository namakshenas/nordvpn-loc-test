#!/usr/bin/env bash
#
# IKEv2 UDP Relay Setup for NordVPN
# ==================================
# Forwards IKEv2 traffic (UDP 500/4500) through your VPS to bypass ISP DPI.
#
# Architecture:
#   Android (strongSwan) ──UDP 500/4500──▶ YOUR VPS ──UDP 500/4500──▶ NordVPN Server
#                                          (this script)              (213.232.87.131)
#
# Usage:
#   chmod +x ikev2-relay-setup.sh
#   sudo ./ikev2-relay-setup.sh
#
# To remove:
#   sudo ./ikev2-relay-setup.sh --remove
#

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
NORDVPN_IP="213.232.87.131"          # nl900.nordvpn.com
NORDVPN_HOST="nl900.nordvpn.com"     # For reference
PORTS=(500 4500)                      # IKEv2 ports
IPTABLES_COMMENT="ikev2-nordvpn-relay"
# ──────────────────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }

# ── Check root ────────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root (sudo)"
    exit 1
fi

# ── Detect VPS public IP and main interface ───────────────────────────────────
detect_network() {
    VPS_IP=$(ip -4 route get 8.8.8.8 | awk '{print $7; exit}')
    VPS_IFACE=$(ip -4 route get 8.8.8.8 | awk '{print $5; exit}')

    if [[ -z "$VPS_IP" || -z "$VPS_IFACE" ]]; then
        err "Could not detect VPS public IP or interface"
        exit 1
    fi

    info "VPS public IP : $VPS_IP"
    info "VPS interface : $VPS_IFACE"
    info "Relay target  : $NORDVPN_HOST ($NORDVPN_IP)"
}

# ── Remove existing rules ────────────────────────────────────────────────────
remove_rules() {
    info "Removing existing relay rules..."

    # Remove iptables rules containing our comment
    for table in nat filter; do
        for chain in $(iptables -t "$table" -L -n --line-numbers 2>/dev/null | grep "^Chain" | awk '{print $2}'); do
            while true; do
                line=$(iptables -t "$table" -L "$chain" -n --line-numbers 2>/dev/null \
                    | grep "$IPTABLES_COMMENT" | head -1 | awk '{print $1}')
                [[ -z "$line" ]] && break
                iptables -t "$table" -D "$chain" "$line" 2>/dev/null || true
            done
        done
    done

    # Remove from PREROUTING and POSTROUTING (nat table)
    for chain in PREROUTING POSTROUTING; do
        while true; do
            line=$(iptables -t nat -L "$chain" -n --line-numbers 2>/dev/null \
                | grep "$IPTABLES_COMMENT" | head -1 | awk '{print $1}')
            [[ -z "$line" ]] && break
            iptables -t nat -D "$chain" "$line" 2>/dev/null || true
        done
    done

    log "Existing relay rules removed"
}

# ── Install rules ────────────────────────────────────────────────────────────
install_rules() {
    info "Setting up IP forwarding..."

    # Enable IP forwarding
    sysctl -w net.ipv4.ip_forward=1 > /dev/null
    # Make persistent
    if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
    log "IP forwarding enabled"

    info "Installing iptables relay rules..."

    for PORT in "${PORTS[@]}"; do
        # DNAT: Incoming UDP on port → forward to NordVPN server
        iptables -t nat -A PREROUTING \
            -i "$VPS_IFACE" \
            -p udp --dport "$PORT" \
            -m comment --comment "$IPTABLES_COMMENT" \
            -j DNAT --to-destination "${NORDVPN_IP}:${PORT}"

        # SNAT/MASQUERADE: So NordVPN sees packets from VPS IP (and sends replies back)
        iptables -t nat -A POSTROUTING \
            -p udp --dport "$PORT" \
            -d "$NORDVPN_IP" \
            -m comment --comment "$IPTABLES_COMMENT" \
            -j MASQUERADE

        log "Port $PORT/udp → ${NORDVPN_IP}:${PORT}"
    done

    # Allow forwarded traffic through
    iptables -A FORWARD \
        -p udp -d "$NORDVPN_IP" \
        -m multiport --dports 500,4500 \
        -m comment --comment "$IPTABLES_COMMENT" \
        -j ACCEPT

    iptables -A FORWARD \
        -p udp -s "$NORDVPN_IP" \
        -m multiport --sports 500,4500 \
        -m comment --comment "$IPTABLES_COMMENT" \
        -j ACCEPT

    log "FORWARD rules installed"
}

# ── Persist rules across reboots ─────────────────────────────────────────────
persist_rules() {
    info "Making rules persistent across reboots..."

    if command -v netfilter-persistent &> /dev/null; then
        netfilter-persistent save
        log "Rules saved via netfilter-persistent"
    elif command -v iptables-save &> /dev/null; then
        # Install iptables-persistent if not present
        if ! dpkg -l iptables-persistent &> /dev/null 2>&1; then
            warn "Installing iptables-persistent for rule persistence..."
            DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent > /dev/null 2>&1 || true
        fi
        iptables-save > /etc/iptables/rules.v4 2>/dev/null || \
            iptables-save > /etc/iptables.rules 2>/dev/null || true
        log "Rules saved"
    else
        warn "Could not auto-persist rules. Add this script to boot or save manually."
    fi
}

# ── Verify ───────────────────────────────────────────────────────────────────
verify() {
    echo ""
    info "Current NAT rules:"
    echo "─────────────────────────────────────────────────────────"
    iptables -t nat -L -n -v | grep -E "(PREROUTING|POSTROUTING|$IPTABLES_COMMENT|$NORDVPN_IP)" || true
    echo "─────────────────────────────────────────────────────────"
    echo ""
    info "Current FORWARD rules:"
    echo "─────────────────────────────────────────────────────────"
    iptables -L FORWARD -n -v | grep -E "(FORWARD|$IPTABLES_COMMENT|$NORDVPN_IP)" || true
    echo "─────────────────────────────────────────────────────────"
}

# ── Test connectivity ─────────────────────────────────────────────────────────
test_relay() {
    echo ""
    info "Testing relay connectivity..."

    # Test if VPS can reach NordVPN server
    if ping -c 1 -W 3 "$NORDVPN_IP" > /dev/null 2>&1; then
        log "VPS → NordVPN server ($NORDVPN_IP): reachable"
    else
        err "VPS → NordVPN server ($NORDVPN_IP): unreachable!"
        err "Check VPS firewall or network."
        return 1
    fi

    # Quick UDP test with timeout
    if command -v nc &> /dev/null; then
        if echo -n "" | nc -u -w 2 "$NORDVPN_IP" 500 2>/dev/null; then
            log "UDP/500 to NordVPN: OK"
        fi
    fi

    log "Relay is active and ready"
}

# ── Print client instructions ────────────────────────────────────────────────
print_instructions() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "  ${GREEN}RELAY IS ACTIVE${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo -e "  ${CYAN}strongSwan Configuration on Android:${NC}"
    echo ""
    echo "  ┌─────────────────────────────────────────────────────┐"
    echo "  │  Server          :  $VPS_IP                         "
    echo "  │  VPN Type        :  IKEv2 EAP (Username/Password)  │"
    echo "  │  Username        :  <your NordVPN username>         │"
    echo "  │  Password        :  <your NordVPN password>         │"
    echo "  │  CA Certificate  :  Select automatically            │"
    echo "  │                                                     │"
    echo "  │  ⚠️  CRITICAL — tap 'Show advanced settings':       │"
    echo "  │                                                     │"
    echo "  │  Server Identity :  nl900.nordvpn.com               │"
    echo "  │                                                     │"
    echo "  └─────────────────────────────────────────────────────┘"
    echo ""
    echo -e "  ${YELLOW}The 'Server Identity' field is essential!${NC}"
    echo "  strongSwan connects to your VPS IP, but the NordVPN server"
    echo "  presents a certificate for 'nl900.nordvpn.com'. Without"
    echo "  setting Server Identity, certificate validation will fail"
    echo "  because the hostname won't match."
    echo ""
    echo "  Traffic flow:"
    echo "  Phone → ${VPS_IP}:500/4500 → (relay) → ${NORDVPN_IP}:500/4500"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║      IKEv2 UDP Relay Setup for NordVPN                  ║"
    echo "║      Bypasses ISP DPI by relaying through VPS           ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""

    if [[ "${1:-}" == "--remove" ]]; then
        detect_network
        remove_rules
        echo ""
        log "Relay removed. Direct connections restored."
        echo ""
        exit 0
    fi

    detect_network
    echo ""

    # Clean slate
    remove_rules
    echo ""

    # Install new rules
    install_rules
    echo ""

    # Persist
    persist_rules
    echo ""

    # Verify
    verify

    # Test
    test_relay

    # Instructions
    print_instructions
}

main "$@"

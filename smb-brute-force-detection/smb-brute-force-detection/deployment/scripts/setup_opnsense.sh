#!/bin/bash
# OPNsense bootstrap reference script
# Run these manually via the OPNsense console or Web GUI after initial boot

echo "========================================"
echo "OPNsense Post-Install Configuration"
echo "========================================"

# Note: OPNsense is FreeBSD-based (tcsh by default). This script is a reference
# checklist only. All actual configuration is done via the Web GUI or console menu.

echo "[*] WAN interface: 192.168.57.254/24"
echo "[*] LAN interface: 192.168.56.254/24"
echo ""
echo "Web GUI Access:"
echo "  Default: https://192.168.56.254 (LAN interface only)"
echo "  WAN access is blocked by default and requires an explicit allow rule"
echo ""
echo "Web GUI Configuration Steps:"
echo "  1. Interfaces -> WAN -> UNCHECK 'Block private networks'"
echo "  2. Interfaces -> WAN -> UNCHECK 'Block bogon networks'"
echo "  3. Firewall -> Rules -> WAN -> Add pass rules for ICMP and SMB (TCP 445)"
echo "     Destination: 192.168.56.102 (DC) or 192.168.56.0/24"
echo "  4. Firewall -> Rules -> LAN -> Allow any to any (default, verify it exists)"
echo "  5. System -> Settings -> Logging -> Remote"
echo "     Enable: checked"
echo "     Target: 192.168.56.106"
echo "     Port: 514"
echo "     Protocol: UDP (4)"
echo ""
echo "Optional for full AD functionality:"
echo "  - Add pass rules for DNS (TCP/UDP 53) and LDAP (TCP 389)"
echo ""
echo "CRITICAL: WAN rules must be ordered ABOVE the 'Default deny all' rule"
echo "========================================"

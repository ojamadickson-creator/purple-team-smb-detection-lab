#!/bin/bash
# OPNsense bootstrap commands
# Run these manually via the OPNsense console or Web GUI after initial boot

echo "========================================"
echo "OPNsense Post-Install Configuration"
echo "========================================"

# Note: OPNsense is FreeBSD-based. Most configuration is done via Web GUI.
# Access at https://192.168.57.254 after initial setup.

echo "[*] Ensure WAN interface is configured with 192.168.57.254/24"
echo "[*] Ensure LAN interface is configured with 192.168.56.254/24"
echo ""
echo "Web GUI Configuration Steps:"
echo "  1. Interfaces -> WAN -> UNCHECK 'Block private networks'"
echo "  2. Interfaces -> WAN -> UNCHECK 'Block bogon networks'"
echo "  3. Firewall -> Rules -> WAN -> Add pass rules for ICMP and SMB"
echo "  4. Firewall -> Rules -> LAN -> Allow any to any (or restrict as needed)"
echo "  5. Services -> Syslog -> Forward to 192.168.56.106:514 (UDP)"
echo ""
echo "Critical: Rules must be ordered ABOVE the 'Default deny all' rule"
echo "========================================"

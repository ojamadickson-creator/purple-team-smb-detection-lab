#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "========================================"
echo "SMB Brute Force Detection Lab"
echo "Automated Deployment Script"
echo "========================================"

# Check prerequisites
echo "[*] Checking prerequisites..."

if ! command -v VBoxManage &> /dev/null; then
    echo -e "${RED}[!] VirtualBox is not installed. Please install VirtualBox 7.0+ first.${NC}"
    exit 1
fi

if ! command -v vagrant &> /dev/null; then
    echo -e "${RED}[!] Vagrant is not installed. Please install Vagrant 2.4+ first.${NC}"
    exit 1
fi

echo -e "${GREEN}[*] Prerequisites verified${NC}"

# Create Host-Only networks if they don't exist
echo "[*] Configuring VirtualBox host-only networks..."

if ! VBoxManage list hostonlyifs | grep -q "192.168.56.1"; then
    echo "[*] Creating vboxnet0 for LAN segment..."
    VBoxManage hostonlyif create ipconfig vboxnet0 --ip 192.168.56.1 --netmask 255.255.255.0 || true
fi

if ! VBoxManage list hostonlyifs | grep -q "192.168.57.1"; then
    echo "[*] Creating vboxnet1 for WAN segment..."
    VBoxManage hostonlyif create ipconfig vboxnet1 --ip 192.168.57.1 --netmask 255.255.255.0 || true
fi

echo -e "${GREEN}[*] Network adapters configured${NC}"

# Deploy VMs
echo "[*] Starting VM deployment with Vagrant..."
echo "    This will provision: OPNsense, DC, Splunk, REMnux, and Win10"
echo ""

cd "$(dirname "$0")"
vagrant up

echo ""
echo "========================================"
echo -e "${GREEN}Deployment Complete!${NC}"
echo "========================================"
echo ""
echo "Access your lab environment:"
echo "  Splunk SIEM:     http://192.168.56.106:8000"
echo "  OPNsense GUI:    https://192.168.57.254"
echo "  DC (RDP):        192.168.56.102"
echo "  REMnux (SSH):    vagrant ssh remnux"
echo ""
echo "Next steps:"
echo "  1. Complete OPNsense initial setup via Web GUI"
echo "  2. Ensure Splunk is receiving logs from the DC"
echo "  3. Import the dashboard from dashboards/brute_force_dashboard.xml"
echo "  4. From REMnux, run: hydra -l vagrant -P /tmp/passwordlist smb://192.168.56.102"
echo ""
echo "========================================"

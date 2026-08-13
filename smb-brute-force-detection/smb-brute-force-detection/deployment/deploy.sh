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

# LAN segment: 192.168.56.0/24
if ! VBoxManage list hostonlyifs | grep -q "Name:            vboxnet0"; then
    echo "[*] Creating vboxnet0 for LAN segment..."
    VBoxManage hostonlyif create 2>/dev/null || true
fi
VBoxManage hostonlyif ipconfig vboxnet0 --ip 192.168.56.1 --netmask 255.255.255.0 2>/dev/null || true

# WAN segment: 192.168.57.0/24
if ! VBoxManage list hostonlyifs | grep -q "Name:            vboxnet1"; then
    echo "[*] Creating vboxnet1 for WAN segment..."
    VBoxManage hostonlyif create 2>/dev/null || true
fi
VBoxManage hostonlyif ipconfig vboxnet1 --ip 192.168.57.1 --netmask 255.255.255.0 2>/dev/null || true

echo -e "${GREEN}[*] Network adapters configured${NC}"

# Verify Vagrantfile exists in this directory
if [ ! -f "Vagrantfile" ]; then
    echo -e "${YELLOW}[!] No Vagrantfile found in $(pwd).${NC}"
    echo -e "${YELLOW}    Ensure deploy.sh and Vagrantfile are in the same directory.${NC}"
    exit 1
fi

# Deploy VMs
echo "[*] Starting VM deployment with Vagrant..."
echo "    This will provision: OPNsense, DC, Splunk, REMnux, and Win10"
echo ""

vagrant up

echo ""
echo "========================================"
echo -e "${GREEN}Deployment Complete!${NC}"
echo "========================================"
echo ""
echo "Access your lab environment:"
echo "  Splunk SIEM:        http://192.168.56.106:8000"
echo "  OPNsense GUI:       https://192.168.56.254  (LAN interface)"
echo "  OPNsense WAN:       192.168.57.254  (no GUI access by default)"
echo "  DC (RDP):           192.168.56.102"
echo "  REMnux (SSH):       vagrant ssh remnux"
echo ""
echo "Next steps:"
echo "  1. Complete OPNsense initial setup via Web GUI on LAN"
echo "  2. Assign interfaces: vtnet1 = WAN, vtnet2 = LAN"
echo "  3. Uncheck 'Block private networks' on WAN interface"
echo "  4. Ensure Splunk is receiving logs from the DC"
echo "  5. Import the dashboard from dashboards/brute_force_dashboard.xml"
echo "  6. From REMnux, run: hydra -l vagrant -P /tmp/passwordlist smb://192.168.56.102"
echo ""
echo "========================================"

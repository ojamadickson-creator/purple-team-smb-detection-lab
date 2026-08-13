#!/bin/bash
set -e

echo "========================================"
echo "Splunk Enterprise 10.4.2 Installation"
echo "========================================"

# Update system
apt-get update -y
apt-get install -y wget curl net-tools

# Disable Ubuntu firewall so OPNsense syslog can reach UDP 514
ufw disable || true

# NOTE: Splunk Enterprise requires a valid license.
# Download the .deb from https://www.splunk.com and place it at:
# /vagrant/splunk-10.4.2-linux-2.6-amd64.deb

SPLUNK_DEB="/vagrant/splunk-10.4.2-linux-2.6-amd64.deb"

if [ -f "$SPLUNK_DEB" ]; then
    dpkg -i "$SPLUNK_DEB"
    apt-get install -f -y || true  # Fix any dependency issues just in case

    /opt/splunk/bin/splunk enable boot-start --accept-license --answer-yes --no-prompt

    # Configure inputs in ONE write (both TCP 9997 and UDP 514)
    mkdir -p /opt/splunk/etc/apps/search/local
    cat > /opt/splunk/etc/apps/search/local/inputs.conf << 'EOF'
[splunktcp://9997]
disabled = 0
connection_host = ip

[udp://514]
disabled = 0
sourcetype = syslog
index = main
EOF

    # Restart Splunk
    /opt/splunk/bin/splunk restart

    echo "========================================"
    echo "Splunk installed successfully"
    echo "Access at http://192.168.56.106:8000"
    echo ""
    echo "CRITICAL NEXT STEP:"
    echo "Install the Splunk Add-on for Microsoft Windows (Windows TA)"
    echo "from Splunkbase. Without it, Linux Splunk cannot parse"
    echo "Windows EventCode fields from the Universal Forwarder."
    echo "========================================"
else
    echo "WARNING: Splunk .deb not found at $SPLUNK_DEB"
    echo "Please download Splunk Enterprise and place it in the deployment directory"
fi

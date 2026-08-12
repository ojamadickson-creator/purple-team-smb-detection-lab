#!/bin/bash
set -e

echo "========================================"
echo "Splunk Enterprise 10.4.2 Installation"
echo "========================================"

# Update system
apt-get update -y
apt-get install -y wget curl net-tools

# NOTE: Splunk Enterprise requires a valid license.
# Download the .deb from https://www.splunk.com and place it at:
# /vagrant/splunk-10.4.2-linux-2.6-amd64.deb

SPLUNK_DEB="/vagrant/splunk-10.4.2-linux-2.6-amd64.deb"

if [ -f "$SPLUNK_DEB" ]; then
    dpkg -i "$SPLUNK_DEB"
    /opt/splunk/bin/splunk enable boot-start --accept-license --answer-yes --no-prompt

    # Configure Splunk to receive Universal Forwarder data on 9997
    cat > /opt/splunk/etc/apps/search/local/inputs.conf << 'EOF'
[splunktcp://9997]
disabled = 0
EOF

    # Configure syslog input for OPNsense firewall logs
    cat > /opt/splunk/etc/apps/search/local/inputs.conf << 'EOF'
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
    echo "========================================"
else
    echo "WARNING: Splunk .deb not found at $SPLUNK_DEB"
    echo "Please download Splunk Enterprise and place it in the deployment directory"
fi

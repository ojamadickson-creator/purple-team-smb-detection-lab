#!/bin/bash
set -e

echo "========================================"
echo "REMnux Attack Platform Configuration"
echo "========================================"

# Update and install tools
sudo apt-get update -y
sudo apt-get install -y hydra net-tools iputils-ping

# Configure Host-Only adapter (enp0s8)
sudo ip link set enp0s8 up
sudo ip addr add 192.168.57.12/24 dev enp0s8 || true

# Add static route to DC subnet via OPNsense LAN IP
sudo ip route add 192.168.56.0/24 via 192.168.57.254 dev enp0s8 || true

# Copy password list to /tmp
if [ -f /vagrant/password_lists/top_100.txt ]; then
    cp /vagrant/password_lists/top_100.txt /tmp/passwordlist
    echo "[*] Password list copied from vagrant mount"
else
    echo "[!] Password list not found at /vagrant/password_lists/top_100.txt"
    echo "    Generating default list..."
    cat > /tmp/passwordlist << 'EOF'
password123
admin123
letmein
qwerty
123456
password
12345678
qwerty123
123456789
iloveyou
admin
welcome
monkey
login
abc123
111111
123123
password1
dragon
master
sunshine
princess
baseball
shadow
cookie
michael
jesus
superman
mustang
access
love
696969
qwertyuiop
1234567890
adobe123
letmein1
photoshop
ashley
bailey
qazwsx
maggie
buster
danielle
thomas
jordan
mike
liverpool
1q2w3e4r
harley
ranger
iwantu
jennifer
computer
joshua
mama
startrek
thunder
merlin
dallas
heather
banana
chelsea
summer
pepper
zxcvbn
zxcvbnm
nicole
killer
matrix
george
asshole
silver
hannah
jasmine
orange
555555
maverick
corvette
scooby
brandon
apples
flower
jackson
butter
booboo
tigger
soccer
rachel
purple
fuckyou
peanut
taylor
hockey
diamond
football
batman
trustno1
hello123
welcome1
vagrant
EOF
fi

echo "========================================"
echo "REMnux Configuration Complete"
echo ""
echo "To launch the attack:"
echo "  hydra -l vagrant -P /tmp/passwordlist smb://192.168.56.102"
echo "========================================"

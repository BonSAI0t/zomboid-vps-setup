#!/bin/bash
# Minimal Project Zomboid Server One-Punch Installer
# Usage: bash minimal-zomboid-setup.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Variables
GAMESERVER_USER="pzserver"
INSTALL_DIR="/home/$GAMESERVER_USER"

echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}Project Zomboid Server - Minimal Installer${NC}"
echo -e "${GREEN}================================================${NC}"

# Check if root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root (use sudo)${NC}"
    exit 1
fi

# Step 1: Security first - Install fail2ban
echo -e "${GREEN}[1/5] Installing fail2ban...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y fail2ban
systemctl enable fail2ban
systemctl start fail2ban
echo -e "${GREEN}✓ fail2ban active${NC}"

# Step 2: System updates and dependencies
echo -e "${GREEN}[2/5] Installing dependencies...${NC}"
dpkg --add-architecture i386

# Configure needrestart to auto-restart without prompting
mkdir -p /etc/needrestart/conf.d/
echo "\$nrconf{restart} = 'a';" > /etc/needrestart/conf.d/auto.conf

apt-get update
apt-get upgrade -y
apt-get install -y \
    curl wget tar bzip2 gzip unzip \
    python3 tmux bc jq git netcat \
    bsdmainutils pigz rng-tools5 \
    lib32gcc-s1 lib32stdc++6 \
    libsdl2-2.0-0:i386 \
    openjdk-17-jre-headless

# SteamCMD license acceptance
echo steamcmd steam/question select "I AGREE" | debconf-set-selections
echo steamcmd steam/license note '' | debconf-set-selections

# Step 3: Create user
echo -e "${GREEN}[3/5] Creating $GAMESERVER_USER user...${NC}"
if ! id "$GAMESERVER_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$GAMESERVER_USER"
fi

# Step 4: Configure firewall
echo -e "${GREEN}[4/5] Configuring firewall...${NC}"
if command -v ufw &> /dev/null; then
    ufw --force enable
    ufw allow 22/tcp
    ufw allow 16261/udp comment 'PZ Game'
    ufw allow 16262/udp comment 'PZ Query'
fi

# Step 5: Install LGSM and server
echo -e "${GREEN}[5/5] Installing LinuxGSM and Project Zomboid...${NC}"

# Give FULL sudo temporarily for installation
echo "pzserver ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/pzserver-temp
chmod 440 /etc/sudoers.d/pzserver-temp

su - "$GAMESERVER_USER" << 'USEREOF'
# Download LGSM
wget -O linuxgsm.sh https://linuxgsm.sh
chmod +x linuxgsm.sh
bash linuxgsm.sh pzserver

# Configure for unstable branch
mkdir -p ~/lgsm/config-lgsm/pzserver
cat > ~/lgsm/config-lgsm/pzserver/pzserver.cfg << 'CFGEOF'
branch="unstable"
betapassword=""
CFGEOF

# Install server
./pzserver auto-install

# Start server to create database
./pzserver start &
sleep 15

# Wait for password prompt and send it
LOG_FILE="$HOME/log/console/pzserver-console.log"
timeout 120 bash -c "
tail -f '$LOG_FILE' 2>/dev/null | while read line; do
    if echo \"\$line\" | grep -q 'Enter new administrator password:'; then
        ./pzserver send 'ChangeThisPassword123'
        sleep 2
    fi
    if echo \"\$line\" | grep -q 'Confirm the password:'; then
        ./pzserver send 'ChangeThisPassword123'
        sleep 2
        break
    fi
done
" || true

# Stop server
sleep 5
./pzserver stop || pkill -9 java

echo ""
echo "✓ Installation complete!"
echo ""
echo "Admin credentials:"
echo "  Username: admin"
echo "  Password: ChangeThisPassword123"
echo ""
echo "Start server: ./pzserver start"
USEREOF

# Remove full sudo access
rm -f /etc/sudoers.d/pzserver-temp

# Add limited sudo for ongoing LGSM operations
cat > /etc/sudoers.d/pzserver-lgsm << 'EOF'
pzserver ALL=(ALL) NOPASSWD: /usr/bin/dpkg
pzserver ALL=(ALL) NOPASSWD: /usr/bin/apt
pzserver ALL=(ALL) NOPASSWD: /usr/bin/apt-get
EOF
chmod 440 /etc/sudoers.d/pzserver-lgsm

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo -e "${YELLOW}Switch to game server user:${NC}"
echo "  su - $GAMESERVER_USER"
echo ""
echo -e "${YELLOW}Start the server:${NC}"
echo "  ./pzserver start"
echo ""
echo -e "${YELLOW}Admin credentials:${NC}"
echo "  Username: admin"
echo "  Password: ChangeThisPassword123"
echo "  ⚠️  CHANGE THIS PASSWORD!"
echo ""
echo -e "${YELLOW}Server ports:${NC}"
echo "  Game: 16261/udp"
echo "  Query: 16262/udp"
echo ""

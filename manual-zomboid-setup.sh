#!/bin/bash
# Project Zomboid Server - Manual Install (No LGSM)
# Based on official PZ wiki instructions
# Usage: bash manual-zomboid-setup.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Variables
GAMESERVER_USER="pzserver"
INSTALL_DIR="/home/$GAMESERVER_USER"
PZ_DIR="$INSTALL_DIR/pzserver"

echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}Project Zomboid Server - Manual Install${NC}"
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

# SteamCMD license acceptance
echo steamcmd steam/question select "I AGREE" | debconf-set-selections
echo steamcmd steam/license note '' | debconf-set-selections

apt-get update
apt-get upgrade -y
apt-get install -y steamcmd

echo -e "${GREEN}✓ Dependencies installed${NC}"

# Step 3: Create user
echo -e "${GREEN}[3/5] Creating $GAMESERVER_USER user...${NC}"
if ! id "$GAMESERVER_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$GAMESERVER_USER"
fi

# Step 4: Configure firewall
echo -e "${GREEN}[4/5] Configuring firewall...${NC}"
if command -v ufw &> /dev/null; then
    ufw allow 22/tcp
    ufw allow 16261/udp comment 'PZ Game'
    ufw allow 16262/udp comment 'PZ Query'
    ufw --force enable
fi

# Step 5: Install Project Zomboid Server
echo -e "${GREEN}[5/5] Installing Project Zomboid Server...${NC}"

su - "$GAMESERVER_USER" << 'USEREOF'
# Create installation directory
mkdir -p ~/pzserver
cd ~/pzserver

# Install via SteamCMD
echo "Installing Project Zomboid (unstable branch) via SteamCMD..."
steamcmd +force_install_dir ~/pzserver +login anonymous +app_update 380870 -beta unstable validate +quit

# Create start script
cat > ~/start-server.sh << 'STARTEOF'
#!/bin/bash
cd ~/pzserver
screen -dmS pzserver ./start-server.sh -servername pzserver
STARTEOF

chmod +x ~/start-server.sh

# Create stop script  
cat > ~/stop-server.sh << 'STOPEOF'
#!/bin/bash
screen -S pzserver -X quit
STOPEOF

chmod +x ~/stop-server.sh

# Start the server for first-time setup
echo "Starting server for first-time initialization..."
cd ~/pzserver
screen -dmS pzserver ./start-server.sh -servername pzserver

# Wait for server to start and create database
sleep 60

# Set admin password via screen
screen -S pzserver -X stuff "ChangeThisPassword123^M"

sleep 1

screen -S pzserver -X stuff "ChangeThisPassword123^M"

sleep 5

echo ""
echo "✓ Server installed and running!"
echo ""
echo "Admin credentials:"
echo "  Username: admin"
echo "  Password: ChangeThisPassword123"
echo ""
echo "Manage server:"
echo "  screen -r pzserver   - Attach to console"
echo "  ~/stop-server.sh     - Stop server"
echo "  ~/start-server.sh    - Start server"
USEREOF

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}✓ Server is running!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo -e "${YELLOW}Switch to game server user:${NC}"
echo "  su - $GAMESERVER_USER"
echo ""
echo -e "${YELLOW}Connect to your server:${NC}"
echo "  IP: $(curl -s ifconfig.me):16261"
echo ""
echo -e "${YELLOW}Admin credentials:${NC}"
echo "  Username: admin"
echo "  Password: ChangeThisPassword123"
echo "  ⚠️  CHANGE THIS PASSWORD!"
echo ""
echo -e "${YELLOW}Manage the server:${NC}"
echo "  screen -r pzserver   - Attach to console (Ctrl+A then D to detach)"
echo "  ~/stop-server.sh     - Stop server"
echo "  ~/start-server.sh    - Start server"
echo ""
echo -e "${YELLOW}Server files:${NC}"
echo "  Game: $PZ_DIR"
echo "  Config: $INSTALL_DIR/Zomboid/Server/pzserver.ini"
echo ""

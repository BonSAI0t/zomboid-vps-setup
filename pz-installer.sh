#!/bin/bash
# Project Zomboid Server - Ultra-Minimal Installer
# Relies on LGSM to handle all dependencies
# Works on Ubuntu 22.04 and 24.04
#
# Installation:
# curl -sSL https://raw.githubusercontent.com/BonSAI0t/zomboid-vps-setup/main/pz-installer.sh | sudo bash
#
# Usage: sudo bash pz-installer.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Variables
GAMESERVER_USER="pzserver"

echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}Project Zomboid Server - Ultra-Minimal Installer${NC}"
echo -e "${GREEN}================================================${NC}"

# Check if root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root (use sudo)${NC}"
    exit 1
fi

# Step 1: Basic security (fail2ban only)
echo -e "${GREEN}[1/4] Installing fail2ban...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y fail2ban

systemctl enable fail2ban
systemctl start fail2ban

echo -e "${GREEN}✓ fail2ban installed and active${NC}"

# Step 2: Create user
echo -e "${GREEN}[2/4] Creating $GAMESERVER_USER user...${NC}"
if ! id "$GAMESERVER_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$GAMESERVER_USER"
fi

# Step 3: Configure firewall (game ports only)
echo -e "${GREEN}[3/4] Configuring firewall for game ports...${NC}"
if command -v ufw &> /dev/null; then
    ufw --force enable
    ufw allow 22/tcp comment 'SSH'
    ufw allow 16261/udp comment 'PZ Game'
    ufw allow 16262/udp comment 'PZ Query'
fi

# Step 4: Give temporary full sudo for LGSM installation
echo -e "${GREEN}[4/4] Installing LinuxGSM and Project Zomboid...${NC}"
echo -e "${YELLOW}Granting temporary sudo for installation...${NC}"
echo ""
echo -e "${YELLOW}⚠️  IMPORTANT: SteamCMD Error is Normal${NC}"
echo "You will see: 'Error! Installing pzserver: SteamCMD: Unknown error occurred'"
echo "This is a known issue - ***IGNORE IT*** and just wait."
echo "LGSM will auto-retry and it will work within 30-60 seconds."
echo "Sit on your hands and count to 5 minutes if needed."
echo ""
echo "pzserver ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/pzserver-temp
chmod 440 /etc/sudoers.d/pzserver-temp

su - "$GAMESERVER_USER" << 'USEREOF'
# Download LGSM
wget -O linuxgsm.sh https://linuxgsm.sh
chmod +x linuxgsm.sh
bash linuxgsm.sh pzserver

# Configure for unstable branch (B42)
mkdir -p ~/lgsm/config-lgsm/pzserver
cat > ~/lgsm/config-lgsm/pzserver/pzserver.cfg << 'CFGEOF'
branch="unstable"
betapassword=""
CFGEOF

echo "Installing server (LGSM will handle all dependencies)..."
./pzserver auto-install

# Start server to initialize database
./pzserver start

# Wait for admin password prompt
echo "Waiting for server to initialize..."
LOG_FILE="$HOME/log/console/pzserver-console.log"

timeout 180 bash -c '
tail -f "$LOG_FILE" 2>/dev/null | while read line; do
    if echo "$line" | grep -q "Enter new administrator password:"; then
        ./pzserver send "ChangeThisPassword123"
        sleep 2
    fi
    if echo "$line" | grep -q "Confirm the password:"; then
        ./pzserver send "ChangeThisPassword123"
        sleep 2
        break
    fi
done
' || true

sleep 3

echo ""
echo "✓ Installation complete!"
echo ""
echo "Admin credentials:"
echo "  Username: admin"
echo "  Password: ChangeThisPassword123"
echo "  ⚠️  CHANGE THIS PASSWORD!"
echo ""
USEREOF

# Remove full sudo, add limited sudo for LGSM operations
rm -f /etc/sudoers.d/pzserver-temp

cat > /etc/sudoers.d/pzserver-lgsm << 'EOF'
pzserver ALL=(ALL) NOPASSWD: /usr/bin/dpkg
pzserver ALL=(ALL) NOPASSWD: /usr/bin/apt
pzserver ALL=(ALL) NOPASSWD: /usr/bin/apt-get
EOF
chmod 440 /etc/sudoers.d/pzserver-lgsm

# Add helpful info to root's bashrc
cat >> /root/.bashrc << 'BASHEOF'

# Project Zomboid Server Commands
# Switch to game server user: su - pzserver
# Then use:
#   ./pzserver start    - Start server
#   ./pzserver stop     - Stop server
#   ./pzserver restart  - Restart server
#   ./pzserver console  - Attach to console (Ctrl+B then D to detach)
#   ./pzserver details  - Server info
#   ./pzserver update   - Update server
BASHEOF

echo ""
echo -e "${YELLOW}Admin credentials (CHANGE THESE!):${NC}"
echo "  Username: admin"
echo "  Password: ChangeThisPassword123"
echo ""
echo -e "${YELLOW}Server details:${NC}"
echo "  IP: $(curl -s ifconfig.me):16261"
echo ""
sleep 5
echo ""
echo -e "${YELLOW}================================================${NC}"
echo -e "${YELLOW}SSH Security Hardening${NC}"
echo -e "${YELLOW}================================================${NC}"
echo ""
echo -e "${YELLOW}⚠️  WARNING: SSH Port 22 Performance Issue${NC}"
echo ""
echo "Bots constantly scan the entire internet looking for open SSH ports."
echo "They hammer port 22 with login attempts, which can cause severe lag."
echo ""
echo "Changing to port 2222 eliminates most of this noise."
echo ""
read -p "When you have finished reading the instructions above, enter y to continue: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    SSH_PORT=2222
    
    echo -e "${GREEN}Hardening SSH security...${NC}"
    
    # Backup SSH config
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
    
    # Change SSH port only (keep root login enabled for safety)
    sed -i "s/^#*Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config
    
    # Configure fail2ban for new port
    cat > /etc/fail2ban/jail.local << 'F2BEOF'
[sshd]
enabled = true
port = ssh,2222
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600
F2BEOF
    
    systemctl restart fail2ban
    
    # Update firewall
    ufw allow $SSH_PORT/tcp comment 'SSH-Hardened'
    
    # Restart SSH
    systemctl restart sshd
    
    echo ""
    echo -e "${GREEN}✓ SSH port changed to $SSH_PORT${NC}"
    echo ""
    echo "Connect on port $SSH_PORT now in another terminal:"
    echo "  ssh -p $SSH_PORT $(whoami)@$(curl -s ifconfig.me)"
    echo ""
    read -p "Come back here and press Enter when successfully connected on port $SSH_PORT: " -r
    echo ""
    echo -e "${GREEN}Closing port 22...${NC}"
    ufw delete allow 22/tcp
    echo -e "${GREEN}Done. This connection will drop. Reconnect on port $SSH_PORT${NC}"
    sleep 1
fi
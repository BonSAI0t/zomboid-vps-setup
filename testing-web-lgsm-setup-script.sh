#!/bin/bash
#
# Web-LGSM Setup Script (Testing Version)
# Installs web-lgsm web interface for Project Zomboid server
#
# Prerequisites:
# - pz-installer.sh must be run first
#
# Installation:
#   wget https://raw.githubusercontent.com/BonSAI0t/zomboid-vps-setup/main/testing-web-lgsm-setup-script.sh
#   chmod +x testing-web-lgsm-setup-script.sh
#
# Usage:
#   sudo ./testing-web-lgsm-setup-script.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root (use sudo)${NC}"
    exit 1
fi

WEB_LGSM_PORT=12357

echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}Web-LGSM Installation${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo "Web-LGSM Port: $WEB_LGSM_PORT"
echo ""

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo -e "${RED}Cannot detect OS${NC}"
    exit 1
fi

# Verify pzserver user exists
if ! id "pzserver" &>/dev/null; then
    echo -e "${RED}Error: pzserver user not found${NC}"
    echo "Please run pz-installer.sh first."
    exit 1
fi

# Step 1: Install web-lgsm dependencies
echo -e "${GREEN}[1/4] Installing dependencies...${NC}"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    sqlite3 \
    git

# Step 2: Clone and install web-lgsm
echo -e "${GREEN}[2/4] Installing web-lgsm...${NC}"

# Clone web-lgsm as pzserver user
su - pzserver << 'CLONEEOF'
if [ ! -d ~/web-lgsm ]; then
    git clone https://github.com/BlueSquare23/web-lgsm.git
    echo "Web-LGSM cloned successfully"
else
    echo "web-lgsm directory already exists, skipping clone"
fi
CLONEEOF

# Give pzserver temporary sudo access for installation
echo "pzserver ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/pzserver-weblgsm-temp
chmod 440 /etc/sudoers.d/pzserver-weblgsm-temp

# Run web-lgsm installation as pzserver user (now has sudo)
su - pzserver << 'INSTALLEOF'
cd ~/web-lgsm
bash install.sh

# Auto-add pzserver to web-lgsm database
echo "Adding pzserver to web-lgsm..."
/opt/web-lgsm/bin/python3 << 'PYEOF'
import sys
sys.path.insert(0, '/home/pzserver/web-lgsm')
from app import main, db
from app.models import GameServer

app = main()
with app.app_context():
    # Check if pzserver already exists
    existing = GameServer.query.filter_by(install_name='pzserver').first()
    if not existing:
        server = GameServer(
            install_name='pzserver',
            install_path='/home/pzserver',
            script_name='pzserver',
            username='pzserver',
            is_container=False,
            install_type='local',
            install_finished=True,
            install_failed=False
        )
        db.session.add(server)
        db.session.commit()
        print("✓ pzserver added to web-lgsm")
    else:
        print("✓ pzserver already in database")
PYEOF
INSTALLEOF

# Remove temporary sudo access
rm -f /etc/sudoers.d/pzserver-weblgsm-temp

echo -e "${GREEN}Web-LGSM installation complete${NC}"

# Step 3: Configure web-lgsm to listen on all interfaces
echo -e "${GREEN}[3/4] Configuring web-lgsm to accept external connections...${NC}"

sed -i 's/host = 127.0.0.1/host = 0.0.0.0/' /home/pzserver/web-lgsm/main.conf

echo -e "${GREEN}Web-LGSM configured to listen on 0.0.0.0${NC}"

# Step 4: Create systemd service for web-lgsm
echo -e "${GREEN}[4/4] Creating web-lgsm systemd service...${NC}"

cat > /etc/systemd/system/web-lgsm.service << 'SERVICEEOF'
[Unit]
Description=Web-LGSM Web Interface
After=network.target

[Service]
Type=forking
User=pzserver
WorkingDirectory=/home/pzserver/web-lgsm
Environment="TERM=xterm"
ExecStart=/home/pzserver/web-lgsm/web-lgsm.py
ExecStop=/home/pzserver/web-lgsm/web-lgsm.py --stop
RemainAfterExit=yes
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICEEOF

systemctl daemon-reload
systemctl enable web-lgsm
systemctl start web-lgsm

echo -e "${GREEN}Web-LGSM service created and started${NC}"

# Configure firewall for web-lgsm
if command -v ufw &> /dev/null; then
    ufw allow $WEB_LGSM_PORT/tcp comment 'Web-LGSM'
fi

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}Web-LGSM Installation Complete${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo -e "${YELLOW}Web-LGSM is available at:${NC}"
echo "  http://$(curl -s ifconfig.me):$WEB_LGSM_PORT"
echo ""
echo -e "${YELLOW}First time setup:${NC}"
echo "  1. Navigate to the URL above"
echo "  2. Create your admin account"
echo "  3. Log in and manage your server"
echo ""
echo -e "${YELLOW}Security Note:${NC}"
echo "  Web-LGSM is running on HTTP (not HTTPS)"
echo "  Consider setting up SSL with Nginx for production use"
echo ""
echo -e "${YELLOW}Useful Commands:${NC}"
echo "  sudo systemctl status web-lgsm     - Check service status"
echo "  sudo systemctl restart web-lgsm    - Restart service"
echo "  sudo systemctl stop web-lgsm       - Stop service"
echo ""

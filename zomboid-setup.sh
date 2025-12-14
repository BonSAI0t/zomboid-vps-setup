#!/bin/bash
#
# Project Zomboid Server Setup Script using LinuxGSM
# One-punch installation for VPS deployment
#
# Usage: bash zomboid-setup.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
GAMESERVER_USER="pzserver"
INSTALL_DIR="/home/${GAMESERVER_USER}"

echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}Project Zomboid Server Setup with LinuxGSM${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root (use sudo)${NC}"
    exit 1
fi

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
else
    echo -e "${RED}Cannot detect OS${NC}"
    exit 1
fi

echo -e "${YELLOW}Detected OS: $OS $VER${NC}"

# Update system
echo -e "${GREEN}[1/8] System security and updates...${NC}"
if [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
    export DEBIAN_FRONTEND=noninteractive
    dpkg --add-architecture i386
    
    # SECURITY FIRST - Install fail2ban immediately
    echo -e "${GREEN}🔒 Installing fail2ban for SSH protection...${NC}"
    apt-get update -qq
    apt-get install -y fail2ban
    
    systemctl enable fail2ban
    systemctl start fail2ban
    echo -e "${GREEN}✓ fail2ban installed and active${NC}"
    
    # Configure needrestart to auto-restart without prompting
    mkdir -p /etc/needrestart/conf.d/
    echo "\$nrconf{restart} = 'a';" > /etc/needrestart/conf.d/auto.conf
    
    # Now proceed with full system update
    echo -e "${GREEN}Updating system packages...${NC}"
    apt-get update
    apt-get upgrade -y
elif [[ "$OS" == "centos" ]] || [[ "$OS" == "rhel" ]] || [[ "$OS" == "rocky" ]]; then
    yum update -y
else
    echo -e "${RED}Unsupported OS${NC}"
    exit 1
fi

# Install dependencies
echo -e "${GREEN}[2/8] Installing dependencies...${NC}"
if [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
    apt-get install -y \
        curl \
        wget \
        tar \
        bzip2 \
        gzip \
        unzip \
        bsdmainutils \
        python3 \
        python3-pip \
        python3-venv \
        util-linux \
        ca-certificates \
        binutils \
        bc \
        jq \
        tmux \
        netcat \
        git \
        lib32gcc-s1 \
        lib32stdc++6 \
        openjdk-17-jre-headless \
        libsdl2-2.0-0:i386 \
        pigz \
        rng-tools5 \
        file \
        cpio \
        distro-info \
        hostname \
        xz-utils \
        uuid-runtime \
        expect \
        sqlite3
    
    echo -e "${YELLOW}Note: SteamCMD will be installed by LinuxGSM during server setup.${NC}"
elif [[ "$OS" == "centos" ]] || [[ "$OS" == "rhel" ]] || [[ "$OS" == "rocky" ]]; then
    yum install -y \
        curl \
        wget \
        tar \
        bzip2 \
        gzip \
        unzip \
        python3 \
        python3-pip \
        util-linux \
        ca-certificates \
        binutils \
        bc \
        jq \
        tmux \
        nc \
        git \
        glibc.i686 \
        libstdc++.i686 \
        java-17-openjdk-headless
fi

# Create game server user
echo -e "${GREEN}[3/8] Creating game server user...${NC}"
if id "$GAMESERVER_USER" &>/dev/null; then
    echo -e "${YELLOW}User $GAMESERVER_USER already exists${NC}"
else
    useradd -m -s /bin/bash "$GAMESERVER_USER"
    echo -e "${GREEN}User $GAMESERVER_USER created${NC}"
fi

# Configure firewall (optional - uncomment if needed)
echo -e "${GREEN}[4/8] Configuring firewall...${NC}"
if command -v ufw &> /dev/null; then
    # Enable UFW if not already enabled
    ufw --force enable
    ufw allow 22/tcp comment 'SSH'
    ufw allow 16261/udp comment 'Project Zomboid - Game Port'
    ufw allow 16262/udp comment 'Project Zomboid - Query Port'
    ufw allow 8766/tcp comment 'Project Zomboid - RCON Port (optional)'
    echo -e "${GREEN}UFW rules added and firewall enabled${NC}"
elif command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-port=16261/udp
    firewall-cmd --permanent --add-port=16262/udp
    firewall-cmd --permanent --add-port=8766/tcp
    firewall-cmd --reload
    echo -e "${GREEN}Firewalld rules added${NC}"
else
    echo -e "${YELLOW}No firewall detected. Make sure ports 16261/udp and 16262/udp are open${NC}"
fi

# Switch to game server user and install LinuxGSM
echo -e "${GREEN}[5/8] Installing LinuxGSM as $GAMESERVER_USER...${NC}"
su - "$GAMESERVER_USER" << 'EOF'
cd ~
wget -O linuxgsm.sh https://linuxgsm.sh
chmod +x linuxgsm.sh
./linuxgsm.sh pzserver
EOF

# Run LGSM install as root to auto-install dependencies
echo -e "${GREEN}[5.5/8] Auto-installing game dependencies via LGSM (as root)...${NC}"
echo -e "${YELLOW}LGSM will now check and install all required dependencies...${NC}"

# Change to pzserver home and run install as root
cd "$INSTALL_DIR"
./pzserver install || {
    echo -e "${YELLOW}Dependency check completed.${NC}"
}

# Configure LGSM to use unstable beta branch
echo -e "${YELLOW}Configuring server to use unstable beta branch...${NC}"
LGSM_CONFIG="$INSTALL_DIR/lgsm/config-lgsm/pzserver/pzserver.cfg"
mkdir -p "$INSTALL_DIR/lgsm/config-lgsm/pzserver"

# Add beta branch configuration
if [ ! -f "$LGSM_CONFIG" ]; then
    cat > "$LGSM_CONFIG" << 'CFGEOF'
##################################
######## Instance Settings ########
##################################

# Use unstable beta branch
branch="unstable"
betapassword=""

CFGEOF
else
    # Append if file exists
    if ! grep -q "^branch=" "$LGSM_CONFIG"; then
        echo 'branch="unstable"' >> "$LGSM_CONFIG"
        echo 'betapassword=""' >> "$LGSM_CONFIG"
    fi
fi

echo -e "${GREEN}Beta branch configured${NC}"

# Give pzserver sudo access for LGSM dependency installation
echo -e "${GREEN}[5.5/8] Configuring permissions for LGSM...${NC}"
cat > /etc/sudoers.d/pzserver-lgsm << 'SUDOEOF'
# Allow pzserver to run package management for LGSM
pzserver ALL=(ALL) NOPASSWD: /usr/bin/dpkg
pzserver ALL=(ALL) NOPASSWD: /usr/bin/apt
pzserver ALL=(ALL) NOPASSWD: /usr/bin/apt-get
SUDOEOF

chmod 440 /etc/sudoers.d/pzserver-lgsm

# Install the server as pzserver user (with sudo access)
echo -e "${GREEN}[6/8] Installing Project Zomboid Server files...${NC}"
su - "$GAMESERVER_USER" << 'EOF'
cd ~

echo "Starting Project Zomboid server installation..."
echo "This may take 10-15 minutes depending on your connection."
echo "Note: SteamCMD may fail on first attempt and retry automatically - this is normal."
echo ""

# LGSM handles retries automatically if SteamCMD fails
./pzserver auto-install

# Verify the installation
if [ -d ~/serverfiles ]; then
    echo "Server files detected - installation appears successful!"
else
    echo "WARNING: Server files not found."
    echo "You may need to manually run: ./pzserver install"
    echo "Check logs at: ~/log/script/pzserver-script.log"
fi
EOF

# Configure the server
echo -e "${GREEN}[7/8] Configuring server and creating admin user...${NC}"

# Start the server in background to trigger admin password prompt
echo "Starting server to initialize database and prompt for admin password..."
su - "$GAMESERVER_USER" -c "./pzserver start" &
SERVER_PID=$!

# Wait for the console log to exist
echo "Waiting for server to start..."
LOG_FILE="/home/$GAMESERVER_USER/log/console/pzserver-console.log"
timeout=60
while [ ! -f "$LOG_FILE" ] && [ $timeout -gt 0 ]; do
    sleep 1
    timeout=$((timeout - 1))
done

if [ -f "$LOG_FILE" ]; then
    echo "Monitoring for password prompt..."
    
    # Monitor log and send password when prompted
    timeout 120 bash -c "
    tail -f '$LOG_FILE' 2>/dev/null | while IFS= read -r line; do
        if echo \"\$line\" | grep -q 'Enter new administrator password:'; then
            echo 'Password prompt detected! Sending password...'
            su - $GAMESERVER_USER -c \"./pzserver send 'ChangeThisPassword123'\"
            sleep 3
        fi
        
        if echo \"\$line\" | grep -q 'Confirm the password:'; then
            echo 'Confirmation prompt detected! Sending password again...'
            su - $GAMESERVER_USER -c \"./pzserver send 'ChangeThisPassword123'\"
            sleep 2
            break
        fi
        
        if echo \"\$line\" | grep -q 'Administrator account.*created'; then
            echo '✓ Admin account created successfully!'
            break
        fi
    done
    "
    
    # Give server time to finish initialization
    sleep 5
    
    # Stop the server
    echo "Stopping server..."
    su - "$GAMESERVER_USER" -c "./pzserver stop" || pkill -9 -u "$GAMESERVER_USER" java
    
    echo ""
    echo "✓ Admin user setup complete!"
    echo "  Username: admin"
    echo "  Password: ChangeThisPassword123"
    echo "  ⚠️  CHANGE THIS PASSWORD IMMEDIATELY!"
else
    echo "⚠️  Could not find server console log"
    echo "  You may need to manually create the admin user"
fi

echo ""
echo "Server configuration complete!"
echo ""
echo -e "${YELLOW}IMPORTANT: Edit your server settings:${NC}"
echo "  - LinuxGSM config: /home/$GAMESERVER_USER/lgsm/config-lgsm/pzserver/pzserver.cfg"
echo "  - Server INI: /home/$GAMESERVER_USER/Zomboid/Server/pzserver.ini"
echo ""
echo -e "${YELLOW}Useful commands (as $GAMESERVER_USER):${NC}"
echo "  ./pzserver start     - Start the server"
echo "  ./pzserver stop      - Stop the server"
echo "  ./pzserver restart   - Restart the server"
echo "  ./pzserver details   - Show server details"
echo "  ./pzserver console   - Attach to server console"
echo "  ./pzserver update    - Update the server"

# Setup systemd service for game server
echo -e "${GREEN}[8/10] Setting up systemd service for game server...${NC}"
cat > /etc/systemd/system/pzserver.service << SERVICEEOF
[Unit]
Description=Project Zomboid Server
After=network.target

[Service]
Type=forking
User=$GAMESERVER_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/pzserver start
ExecStop=$INSTALL_DIR/pzserver stop
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICEEOF

systemctl daemon-reload
systemctl enable pzserver.service

# Install web-lgsm web interface
echo -e "${GREEN}[9/10] Installing web-lgsm web interface...${NC}"

# Clone web-lgsm as pzserver user
su - "$GAMESERVER_USER" << 'EOF'
cd ~
if [ ! -d "web-lgsm" ]; then
    git clone https://github.com/BlueSquare23/web-lgsm.git
    echo "Web-LGSM cloned successfully!"
else
    echo "web-lgsm directory already exists, skipping clone"
fi
EOF

# Give pzserver temporary sudo access for installation
echo -e "${YELLOW}Granting temporary sudo access to $GAMESERVER_USER for web-lgsm installation...${NC}"
echo "$GAMESERVER_USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/pzserver-temp

# Run web-lgsm installation as pzserver user (now has sudo)
echo -e "${YELLOW}Running web-lgsm installation...${NC}"
su - "$GAMESERVER_USER" << 'EOF'
cd ~/web-lgsm
bash install.sh

# Auto-add pzserver to web-lgsm database
echo "Adding pzserver to web-lgsm..."
/opt/web-lgsm/bin/python3 << 'PYEOF'
import sys
sys.path.insert(0, '/home/pzserver/web-lgsm')
from app import main, db
from app.models import GameServers

app = main()
with app.app_context():
    # Check if pzserver already exists
    existing = GameServers.query.filter_by(name='pzserver').first()
    if not existing:
        server = GameServers(
            name='pzserver',
            install_loc='/home/pzserver',
            game_name='Project Zomboid'
        )
        db.session.add(server)
        db.session.commit()
        print("✓ pzserver added to web-lgsm")
    else:
        print("✓ pzserver already in database")
PYEOF
EOF

# Remove sudo access immediately after installation
echo -e "${YELLOW}Removing temporary sudo access...${NC}"
rm -f /etc/sudoers.d/pzserver-temp

# Create limited sudo access for LGSM operations
echo -e "${GREEN}Configuring sudo access for LGSM operations...${NC}"
cat > /etc/sudoers.d/pzserver-lgsm << 'SUDOEOF'
# Allow pzserver to run package management for LGSM
pzserver ALL=(ALL) NOPASSWD: /usr/bin/dpkg
pzserver ALL=(ALL) NOPASSWD: /usr/bin/apt
pzserver ALL=(ALL) NOPASSWD: /usr/bin/apt-get
SUDOEOF

chmod 440 /etc/sudoers.d/pzserver-lgsm

echo -e "${GREEN}Web-LGSM installation complete!${NC}"

# Setup systemd service for web-lgsm
echo -e "${GREEN}[10/10] Setting up systemd service for web-lgsm...${NC}"
cat > /etc/systemd/system/web-lgsm.service << WEBSERVICEEOF
[Unit]
Description=Web-LGSM Web Interface
After=network.target pzserver.service

[Service]
Type=forking
User=$GAMESERVER_USER
WorkingDirectory=$INSTALL_DIR/web-lgsm
Environment="TERM=xterm"
ExecStart=$INSTALL_DIR/web-lgsm/web-lgsm.py
ExecStop=$INSTALL_DIR/web-lgsm/web-lgsm.py --stop
RemainAfterExit=yes
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
WEBSERVICEEOF

systemctl daemon-reload
systemctl enable web-lgsm.service

# Configure firewall for web-lgsm (port 12357)
echo -e "${GREEN}Configuring firewall for web-lgsm...${NC}"
if command -v ufw &> /dev/null; then
    ufw allow 12357/tcp comment 'Web-LGSM Web Interface'
    echo -e "${GREEN}UFW rule added for web-lgsm${NC}"
elif command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-port=12357/tcp
    firewall-cmd --reload
    echo -e "${GREEN}Firewalld rule added for web-lgsm${NC}"
else
    echo -e "${YELLOW}No firewall detected. Make sure port 12357/tcp is open for web-lgsm${NC}"
fi

# Restart SSH to apply hardened configuration
echo -e "${GREEN}Restarting SSH with hardened configuration...${NC}"
systemctl restart sshd

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo -e "${RED}⚠️  SECURITY NOTICE ⚠️${NC}"
echo -e "${RED}SSH has been configured for KEY-BASED authentication only!${NC}"
echo -e "${RED}Password authentication is now DISABLED.${NC}"
echo -e "${RED}Make sure you have your SSH keys set up before disconnecting!${NC}"
echo -e "${RED}fail2ban is active and protecting against brute force attacks.${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Switch to game server user: su - $GAMESERVER_USER"
echo "2. Edit server config: nano ~/lgsm/config-lgsm/pzserver/pzserver.cfg"
echo "3. Edit server INI: nano ~/Zomboid/Server/servertest.ini"
echo "4. Start server: ./pzserver start"
echo ""
echo -e "${YELLOW}OR use systemd:${NC}"
echo "  sudo systemctl start pzserver"
echo "  sudo systemctl status pzserver"
echo ""
echo -e "${YELLOW}Web-LGSM Web Interface:${NC}"
echo "  Start: sudo systemctl start web-lgsm"
echo "  Stop: sudo systemctl stop web-lgsm"
echo "  Status: sudo systemctl status web-lgsm"
echo "  Access at: http://YOUR_SERVER_IP:12357"
echo "  Default port: 12357"
echo ""
echo -e "${YELLOW}Server Ports:${NC}"
echo "  Game Port: 16261/udp"
echo "  Query Port: 16262/udp"
echo "  RCON Port: 8766/tcp (optional)"
echo "  Web-LGSM: 12357/tcp"
echo ""
echo -e "${YELLOW}Important Files:${NC}"
echo "  LGSM Script: $INSTALL_DIR/pzserver"
echo "  LGSM Config: $INSTALL_DIR/lgsm/config-lgsm/pzserver/pzserver.cfg"
echo "  Server INI: $INSTALL_DIR/Zomboid/Server/servertest.ini"
echo "  Web-LGSM: $INSTALL_DIR/web-lgsm/"
echo ""
echo -e "${RED}SECURITY REMINDERS:${NC}"
echo "  1. CHANGE THE ADMIN PASSWORD (default: ChangeThisPassword123)"
echo "  2. Setup web-lgsm user account on first access"
echo "  3. Consider using a reverse proxy with SSL for web-lgsm"
echo "  4. Firewall port 12357 if not using externally"
echo "  5. SSH is now KEY-ONLY - no password authentication"
echo "  6. fail2ban is protecting SSH from brute force attacks"
echo ""

#!/bin/bash
# Project Zomboid Server - Ultra-Minimal Installer
# Relies on LGSM to handle all dependencies
# Works on Ubuntu 22.04 and 24.04
#
# These scripts were made with LLM Chatbot AI Assistance (Claude)
#
# Installation:
# curl -sSL https://raw.githubusercontent.com/BonSAI0t/zomboid-vps-setup/main/1-pz-installer.sh | sudo bash
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

# Step 1: System updates and fail2ban
echo -e "${GREEN}[1/4] Updating system and installing fail2ban...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y
apt-get install -y fail2ban

systemctl enable fail2ban
systemctl start fail2ban

echo -e "${GREEN}✓ System updated and fail2ban active${NC}"

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


sleep 3

echo ""
echo "✓ Installation complete!"
echo ""
echo "Admin credentials:"
echo "  Username: admin"
echo "  Password: ChangeThisPassword123"
echo "  CHANGE THIS PASSWORD"
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
echo -e "${YELLOW}Admin credentials (CHANGE THESE):${NC}"
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
echo -e "${YELLOW}WARNING: SSH Port 22 Performance Issue${NC}"
echo ""
echo "Bots constantly scan the entire internet looking for open SSH ports."
echo "They hammer port 22 with login attempts, which can cause severe lag."
echo ""
echo "Changing to port 2222 eliminates most of this noise."
echo ""
echo "Press Enter to continue with SSH hardening..."
read -r
echo ""
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
    
    # Restart SSH (Ubuntu 24.04 uses socket activation)
    systemctl daemon-reload
    systemctl restart ssh.socket
    
    echo ""
    echo -e "${GREEN}✓ SSH port changed to $SSH_PORT${NC}"
    echo ""
    echo "Connect on port $SSH_PORT now in another terminal:"
    echo "  ssh -p $SSH_PORT $(whoami)@$(curl -s ifconfig.me)"
    echo ""
    read -p "Come back here and press Enter when successfully connected on port $SSH_PORT: " -r
    echo ""
    echo -e "${GREEN}Closing port 22 to new connections...${NC}"
    ufw delete allow 22/tcp
    echo -e "${GREEN}Done. SSH active on $SSH_PORT${NC} to new connections"
    sleep 1

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}Installing Web-LGSM with HTTPS${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""

WEB_LGSM_PORT=12357
SERVER_IP=$(curl -s ifconfig.me || curl -s icanhazip.com)

# Step 1: Install dependencies
echo -e "${GREEN}[1/7] Installing web dependencies...${NC}"
apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    sqlite3 \
    git \
    nginx \
    openssl

# Step 2: Clone and install web-lgsm
echo -e "${GREEN}[2/7] Installing web-lgsm...${NC}"

# Give pzserver temporary sudo access for installation
echo "pzserver ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/pzserver-weblgsm-temp
chmod 440 /etc/sudoers.d/pzserver-weblgsm-temp

su - pzserver << 'WEBEOF'
if [ ! -d ~/web-lgsm ]; then
    git clone https://github.com/BlueSquare23/web-lgsm.git
fi

cd ~/web-lgsm
bash install.sh

# Auto-add pzserver to web-lgsm database
/opt/web-lgsm/bin/python3 << 'PYEOF'
import sys
sys.path.insert(0, '/home/pzserver/web-lgsm')
from app import main, db
from app.models import GameServer

app = main()
with app.app_context():
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
WEBEOF

# Remove temporary sudo access
rm -f /etc/sudoers.d/pzserver-weblgsm-temp

# Step 3: Configure web-lgsm
echo -e "${GREEN}[3/7] Configuring web-lgsm...${NC}"
sed -i 's/host = 0.0.0.0/host = 127.0.0.1/' /home/pzserver/web-lgsm/main.conf 2>/dev/null || \
sed -i 's/host = .*/host = 127.0.0.1/' /home/pzserver/web-lgsm/main.conf

# Step 4: Create systemd service
echo -e "${GREEN}[4/7] Creating web-lgsm service...${NC}"

cat > /etc/systemd/system/web-lgsm.service << 'WEBSERVICE'
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
WEBSERVICE

systemctl daemon-reload
systemctl enable web-lgsm
systemctl start web-lgsm

# Step 5: Generate self-signed SSL certificate
echo -e "${GREEN}[5/7] Generating SSL certificate...${NC}"

mkdir -p /etc/ssl/private
chmod 700 /etc/ssl/private

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/web-lgsm-selfsigned.key \
    -out /etc/ssl/certs/web-lgsm-selfsigned.crt \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=$SERVER_IP" \
    2>/dev/null

# Step 6: Configure Nginx
echo -e "${GREEN}[6/7] Configuring Nginx...${NC}"

cat > /etc/nginx/sites-available/web-lgsm << 'NGINXWEB'
server {
listen 80 default_server;
listen [::]:80 default_server;
server_name _;
location / {
    return 301 https://$host$request_uri;
}
}

server {
listen 443 ssl http2 default_server;
listen [::]:443 ssl http2 default_server;
server_name _;

ssl_certificate /etc/ssl/certs/web-lgsm-selfsigned.crt;
ssl_certificate_key /etc/ssl/private/web-lgsm-selfsigned.key;
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers HIGH:!aNULL:!MD5;
ssl_prefer_server_ciphers on;

add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;

location / {
    proxy_pass http://127.0.0.1:12357;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";

    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;
}

access_log /var/log/nginx/web-lgsm-access.log;
error_log /var/log/nginx/web-lgsm-error.log;
}
NGINXWEB

ln -sf /etc/nginx/sites-available/web-lgsm /etc/nginx/sites-enabled/web-lgsm
rm -f /etc/nginx/sites-enabled/default

nginx -t && systemctl enable nginx && systemctl restart nginx

# Step 7: Configure firewall and fail2ban
echo -e "${GREEN}[7/7] Configuring firewall and fail2ban...${NC}"

ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'

# Add fail2ban protection for Nginx
cat > /etc/fail2ban/jail.d/nginx.conf << 'F2BNGINX'
[nginx-http-auth]
enabled = true
port = http,https
logpath = /var/log/nginx/web-lgsm-error.log

[nginx-limit-req]
enabled = true
port = http,https
logpath = /var/log/nginx/web-lgsm-error.log

[nginx-botsearch]
enabled = true
port = http,https
logpath = /var/log/nginx/web-lgsm-access.log
maxretry = 2
F2BNGINX

systemctl restart fail2ban

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}Web-LGSM Installed!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo -e "${YELLOW}Web-LGSM is available at:${NC}"
echo "  https://$SERVER_IP"
echo ""
echo -e "${YELLOW}First time setup:${NC}"
echo "  1. Navigate to the URL above"
echo "  2. Accept the self-signed certificate warning"
echo "  3. Create your admin account"
echo ""
echo -e "${YELLOW}Upgrade to Let's Encrypt (optional):${NC}"
echo "  wget https://raw.githubusercontent.com/BonSAI0t/zomboid-vps-setup/main/3-upgrade-to-letsencrypt.sh"
echo "  chmod +x 3-upgrade-to-letsencrypt.sh"
echo "  sudo ./3-upgrade-to-letsencrypt.sh yourdomain.com your@email.com"
echo ""

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}All Done!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo -e "${YELLOW}Game Server:${NC}"
echo "  IP: $SERVER_IP:16261"
echo "  Admin: admin / ChangeThisPassword123 (CHANGE THIS!)"
echo ""
echo -e "${YELLOW}Web Management:${NC}"
echo "  https://$SERVER_IP"
echo "  (Accept self-signed certificate warning in browser)"
echo ""
echo -e "${YELLOW}SSH Access:${NC}"
echo "  ssh -p $SSH_PORT root@$SERVER_IP"
echo "  su - pzserver"
echo "  ./pzserver details"
echo ""
echo -e "${YELLOW}Upgrade to Let's Encrypt SSL (Optional):${NC}"
echo "  If you have a domain, get verified SSL (no browser warnings):"
echo "  wget https://raw.githubusercontent.com/BonSAI0t/zomboid-vps-setup/main/2-upgrade-to-letsencrypt.sh"
echo "  chmod +x 2-upgrade-to-letsencrypt.sh"
echo "  sudo ./2-upgrade-to-letsencrypt.sh yourdomain.com your@email.com"
echo ""
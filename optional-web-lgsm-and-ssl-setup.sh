#!/bin/bash
#
# Web-LGSM + SSL Setup
# Installs web-lgsm web interface and optionally sets up SSL with Nginx
#
# Prerequisites:
# - pz-installer.sh must be run first
# - For SSL: Domain name pointing to this server's IP
#
# Installation:
#   wget https://raw.githubusercontent.com/BonSAI0t/zomboid-vps-setup/main/optional-web-lgsm-and-ssl-setup.sh
#   chmod +x optional-web-lgsm-and-ssl-setup.sh
#
# Usage: 
#   sudo ./optional-web-lgsm-and-ssl-setup.sh                              # Install web-lgsm only
#   sudo ./optional-web-lgsm-and-ssl-setup.sh yourdomain.com your@email.com # Install web-lgsm + SSL
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

# Check arguments
DOMAIN=""
EMAIL=""
SETUP_SSL=false

if [ $# -eq 0 ]; then
    echo "Installing web-lgsm without SSL"
elif [ $# -eq 2 ]; then
    DOMAIN=$1
    EMAIL=$2
    SETUP_SSL=true
else
    echo -e "${RED}Usage:${NC}"
    echo "  sudo $0                              # Install web-lgsm only"
    echo "  sudo $0 <domain> <email>             # Install web-lgsm + SSL"
    echo ""
    echo "Example: sudo $0 zomboid.example.com admin@example.com"
    exit 1
fi

WEB_LGSM_PORT=12357

echo -e "${GREEN}================================================${NC}"
if [ "$SETUP_SSL" = true ]; then
    echo -e "${GREEN}Web-LGSM + SSL Setup${NC}"
else
    echo -e "${GREEN}Web-LGSM Installation${NC}"
fi
echo -e "${GREEN}================================================${NC}"
echo ""
if [ "$SETUP_SSL" = true ]; then
    echo "Domain: $DOMAIN"
    echo "Email: $EMAIL"
fi
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
echo -e "${GREEN}[1/3] Installing dependencies...${NC}"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y python3-pip git

# Step 2: Install web-lgsm
echo -e "${GREEN}[2/3] Installing web-lgsm...${NC}"

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
INSTALLEOF

# Remove temporary sudo access
rm -f /etc/sudoers.d/pzserver-weblgsm-temp

echo -e "${GREEN}Web-LGSM installation complete${NC}"

# Create systemd service for web-lgsm
echo -e "${GREEN}[3/3] Creating web-lgsm systemd service...${NC}"

cat > /etc/systemd/system/web-lgsm.service << 'SERVICEEOF'
[Unit]
Description=Web-LGSM Web Interface
After=network.target

[Service]
Type=simple
User=pzserver
WorkingDirectory=/home/pzserver/web-lgsm
ExecStart=/usr/bin/python3 /home/pzserver/web-lgsm/web-lgsm.py
Restart=always
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

if [ "$SETUP_SSL" = false ]; then
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
    echo "  For SSL/HTTPS, run this script again with domain and email:"
    echo "  sudo $0 yourdomain.com your@email.com"
    echo ""
    exit 0
fi

# Continue with SSL setup if domain provided
echo -e "${GREEN}[4/4] Setting up SSL...${NC}"

# Check if domain resolves to this server
echo -e "${YELLOW}[1/6] Checking DNS resolution...${NC}"
SERVER_IP=$(curl -s ifconfig.me || curl -s icanhazip.com)
DOMAIN_IP=$(dig +short $DOMAIN | tail -n1)

if [ -z "$DOMAIN_IP" ]; then
    echo -e "${RED}Warning: Domain $DOMAIN does not resolve to any IP!${NC}"
    echo "Please set up DNS first."
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
elif [ "$SERVER_IP" != "$DOMAIN_IP" ]; then
    echo -e "${YELLOW}Warning: Domain resolves to $DOMAIN_IP but server IP is $SERVER_IP${NC}"
    echo "SSL certificate may fail to validate."
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    echo -e "${GREEN}DNS looks good! Domain resolves to this server.${NC}"
fi

# Install Nginx
echo -e "${GREEN}[2/6] Installing Nginx...${NC}"
if [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
    apt-get update
    apt-get install -y nginx
elif [[ "$OS" == "centos" ]] || [[ "$OS" == "rhel" ]] || [[ "$OS" == "rocky" ]]; then
    yum install -y nginx
fi

# Install Certbot
echo -e "${GREEN}[3/6] Installing Certbot...${NC}"
if [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
    apt-get install -y certbot python3-certbot-nginx
elif [[ "$OS" == "centos" ]] || [[ "$OS" == "rhel" ]] || [[ "$OS" == "rocky" ]]; then
    yum install -y certbot python3-certbot-nginx
fi

# Stop Nginx temporarily for certificate generation
systemctl stop nginx

# Configure firewall for HTTP/HTTPS
echo -e "${GREEN}[4/6] Configuring firewall...${NC}"
if command -v ufw &> /dev/null; then
    ufw allow 80/tcp comment 'HTTP for SSL verification'
    ufw allow 443/tcp comment 'HTTPS'
    # Block direct access to web-lgsm port from outside
    ufw delete allow 12357/tcp 2>/dev/null || true
    ufw allow from 127.0.0.1 to any port 12357 proto tcp comment 'Web-LGSM local only'
    echo -e "${GREEN}UFW configured${NC}"
elif command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-service=http
    firewall-cmd --permanent --add-service=https
    firewall-cmd --permanent --remove-port=12357/tcp 2>/dev/null || true
    firewall-cmd --reload
    echo -e "${GREEN}Firewalld configured${NC}"
fi

# Obtain SSL certificate
echo -e "${GREEN}[5/6] Obtaining SSL certificate from Let's Encrypt...${NC}"
echo -e "${YELLOW}This will ask you to agree to Terms of Service...${NC}"

certbot certonly --standalone \
    --non-interactive \
    --agree-tos \
    --email "$EMAIL" \
    -d "$DOMAIN" || {
        echo -e "${RED}SSL certificate generation failed!${NC}"
        echo "Common issues:"
        echo "  - Domain doesn't point to this server"
        echo "  - Port 80 is blocked"
        echo "  - Rate limit hit (5 certs per domain per week)"
        exit 1
    }

echo -e "${GREEN}SSL certificate obtained successfully!${NC}"

# Create Nginx configuration
echo -e "${GREEN}[6/6] Creating Nginx configuration and starting services...${NC}"

cat > /etc/nginx/sites-available/web-lgsm << NGINXCONF
# Redirect HTTP to HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

# HTTPS server
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN;

    # SSL certificate files
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Proxy settings
    location / {
        proxy_pass http://127.0.0.1:$WEB_LGSM_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # WebSocket support for live console
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # Logging
    access_log /var/log/nginx/web-lgsm-access.log;
    error_log /var/log/nginx/web-lgsm-error.log;
}
NGINXCONF

# Enable site (Debian/Ubuntu)
if [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
    ln -sf /etc/nginx/sites-available/web-lgsm /etc/nginx/sites-enabled/web-lgsm
    # Remove default site
    rm -f /etc/nginx/sites-enabled/default
fi

# Test Nginx configuration
nginx -t || {
    echo -e "${RED}Nginx configuration test failed!${NC}"
    exit 1
}

# Start and enable services
systemctl enable nginx
systemctl start nginx
systemctl restart web-lgsm

# Set up automatic certificate renewal
echo -e "${GREEN}Setting up automatic certificate renewal...${NC}"
if ! grep -q "certbot renew" /etc/crontab 2>/dev/null; then
    echo "0 0,12 * * * root certbot renew --quiet --post-hook 'systemctl reload nginx'" >> /etc/crontab
fi

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}SSL Setup Complete!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo -e "${YELLOW}Web-LGSM is now available at:${NC}"
echo "  https://$DOMAIN"
echo ""
echo -e "${YELLOW}Important Notes:${NC}"
echo "  - HTTP (port 80) redirects to HTTPS (port 443)"
echo "  - Direct access to port 12357 is blocked from outside"
echo "  - SSL certificate auto-renews via cron"
echo "  - Certificate expires in 90 days but renews automatically"
echo ""
echo -e "${YELLOW}Certificate Information:${NC}"
certbot certificates
echo ""
echo -e "${YELLOW}Useful Commands:${NC}"
echo "  sudo certbot renew              - Manually renew certificate"
echo "  sudo certbot certificates       - View certificate info"
echo "  sudo nginx -t                   - Test Nginx config"
echo "  sudo systemctl status nginx     - Check Nginx status"
echo "  sudo tail -f /var/log/nginx/web-lgsm-error.log  - View logs"
echo ""
echo -e "${GREEN}Setup complete! Visit https://$DOMAIN to access your server.${NC}"
echo ""

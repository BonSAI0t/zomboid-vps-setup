#!/bin/bash
#
# Let's Encrypt Upgrade Script for Web-LGSM
# Upgrades from self-signed SSL to Let's Encrypt verified certificate
#
# These scripts were made with LLM Chatbot AI Assistance (Claude)
#
# Prerequisites:
# - 2-web-lgsm-setup-script.sh must be run first
# - Domain name pointing to this server's IP
# - DNS must be configured and propagated
#
# Installation:
#   wget https://raw.githubusercontent.com/BonSAI0t/zomboid-vps-setup/main/3-upgrade-to-letsencrypt.sh
#   chmod +x 3-upgrade-to-letsencrypt.sh
#
# Usage:
#   sudo ./3-upgrade-to-letsencrypt.sh yourdomain.com your@email.com
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
if [ $# -ne 2 ]; then
    echo -e "${RED}Usage:${NC}"
    echo "  sudo $0 <domain> <email>"
    echo ""
    echo "Example: sudo $0 zomboid.example.com admin@example.com"
    exit 1
fi

DOMAIN=$1
EMAIL=$2
WEB_LGSM_PORT=12357

echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}Let's Encrypt Upgrade for Web-LGSM${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo "Domain: $DOMAIN"
echo "Email: $EMAIL"
echo ""

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo -e "${RED}Cannot detect OS${NC}"
    exit 1
fi

# Verify prerequisites
if ! id "pzserver" &>/dev/null; then
    echo -e "${RED}Error: pzserver user not found${NC}"
    echo "Please run 1-pz-installer.sh first."
    exit 1
fi

if [ ! -f /etc/systemd/system/web-lgsm.service ]; then
    echo -e "${RED}Error: web-lgsm service not found${NC}"
    echo "Please run 2-web-lgsm-setup-script.sh first."
    exit 1
fi

if [ ! -f /etc/nginx/sites-available/web-lgsm ]; then
    echo -e "${RED}Error: Nginx not configured${NC}"
    echo "Please run 2-web-lgsm-setup-script.sh first."
    exit 1
fi

# Step 1: Check DNS resolution
echo -e "${GREEN}[1/4] Checking DNS resolution...${NC}"
SERVER_IP=$(curl -s ifconfig.me || curl -s icanhazip.com)
DOMAIN_IP=$(dig +short $DOMAIN | tail -n1)

if [ -z "$DOMAIN_IP" ]; then
    echo -e "${RED}Error: Domain $DOMAIN does not resolve to any IP!${NC}"
    echo "Please set up DNS first."
    exit 1
elif [ "$SERVER_IP" != "$DOMAIN_IP" ]; then
    echo -e "${YELLOW}Warning: Domain resolves to $DOMAIN_IP but server IP is $SERVER_IP${NC}"
    echo "SSL certificate will fail if DNS is not correct."
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    echo -e "${GREEN}DNS looks good! Domain resolves to this server.${NC}"
fi

# Step 2: Install Certbot
echo -e "${GREEN}[2/4] Installing Certbot...${NC}"
if [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
    apt-get update -qq
    apt-get install -y certbot python3-certbot-nginx
elif [[ "$OS" == "centos" ]] || [[ "$OS" == "rhel" ]] || [[ "$OS" == "rocky" ]]; then
    yum install -y certbot python3-certbot-nginx
fi

# Stop Nginx temporarily for certificate generation
systemctl stop nginx

# Step 3: Obtain Let's Encrypt certificate
echo -e "${GREEN}[3/4] Obtaining Let's Encrypt certificate...${NC}"
echo -e "${YELLOW}This will ask you to agree to Terms of Service...${NC}"

certbot certonly --standalone \
    --non-interactive \
    --agree-tos \
    --email "$EMAIL" \
    -d "$DOMAIN" || {
        echo -e "${RED}SSL certificate generation failed!${NC}"
        echo ""
        echo "Common issues:"
        echo "  - Domain doesn't point to this server (check DNS)"
        echo "  - Port 80 is blocked by firewall"
        echo "  - Rate limit hit (5 certs per domain per week)"
        echo ""
        echo "If rate limited, wait or use the self-signed certificate."
        echo "Restarting Nginx with self-signed certificate..."
        systemctl start nginx
        exit 1
    }

echo -e "${GREEN}SSL certificate obtained successfully!${NC}"

# Step 4: Update Nginx configuration
echo -e "${GREEN}[4/4] Updating Nginx configuration...${NC}"

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

# HTTPS server with Let's Encrypt
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN;

    # Let's Encrypt SSL certificates
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

# Test and reload Nginx
nginx -t || {
    echo -e "${RED}Nginx configuration test failed!${NC}"
    exit 1
}

systemctl start nginx

# Set up automatic certificate renewal
echo -e "${GREEN}Setting up automatic certificate renewal...${NC}"
if ! grep -q "certbot renew" /etc/crontab 2>/dev/null; then
    echo "0 0,12 * * * root certbot renew --quiet --post-hook 'systemctl reload nginx'" >> /etc/crontab
fi

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}Let's Encrypt Upgrade Complete!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo -e "${YELLOW}Web-LGSM is now available at:${NC}"
echo "  https://$DOMAIN"
echo ""
echo -e "${YELLOW}What Changed:${NC}"
echo "  ✓ Self-signed certificate replaced with Let's Encrypt"
echo "  ✓ No more browser security warnings"
echo "  ✓ Certificate verified and trusted by all browsers"
echo "  ✓ Auto-renewal configured (renews every 60 days)"
echo ""
echo -e "${YELLOW}Certificate Information:${NC}"
certbot certificates
echo ""
echo -e "${YELLOW}Useful Commands:${NC}"
echo "  sudo certbot renew              - Manually renew certificate"
echo "  sudo certbot certificates       - View certificate info"
echo "  sudo nginx -t                   - Test Nginx config"
echo "  sudo systemctl status nginx     - Check Nginx status"
echo "  sudo systemctl status web-lgsm  - Check Web-LGSM status"
echo ""
echo -e "${GREEN}Setup complete! Visit https://$DOMAIN to access your server.${NC}"
echo ""

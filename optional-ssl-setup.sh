#!/bin/bash
#
# Optional SSL Setup for Web-LGSM
# Sets up Nginx reverse proxy with Let's Encrypt SSL certificate
#
# Prerequisites:
# - zomboid-setup.sh must be run first
# - Domain name pointing to this server's IP
# - Ports 80 and 443 open in firewall
#
# Usage: sudo ./optional-ssl-setup.sh yourdomain.com your@email.com
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
if [ $# -lt 2 ]; then
    echo -e "${RED}Usage: sudo $0 <domain> <email>${NC}"
    echo "Example: sudo $0 zomboid.example.com admin@example.com"
    exit 1
fi

DOMAIN=$1
EMAIL=$2
WEB_LGSM_PORT=12357

echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}Web-LGSM SSL Setup with Nginx & Let's Encrypt${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo "Domain: $DOMAIN"
echo "Email: $EMAIL"
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

# Verify web-lgsm is installed
if [ ! -f /etc/systemd/system/web-lgsm.service ]; then
    echo -e "${RED}Error: web-lgsm is not installed!${NC}"
    echo "Please run zomboid-setup.sh first."
    exit 1
fi

# Check if domain resolves to this server
echo -e "${YELLOW}[1/8] Checking DNS resolution...${NC}"
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
echo -e "${GREEN}[2/8] Installing Nginx...${NC}"
if [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
    apt-get update
    apt-get install -y nginx
elif [[ "$OS" == "centos" ]] || [[ "$OS" == "rhel" ]] || [[ "$OS" == "rocky" ]]; then
    yum install -y nginx
fi

# Install Certbot
echo -e "${GREEN}[3/8] Installing Certbot...${NC}"
if [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
    apt-get install -y certbot python3-certbot-nginx
elif [[ "$OS" == "centos" ]] || [[ "$OS" == "rhel" ]] || [[ "$OS" == "rocky" ]]; then
    yum install -y certbot python3-certbot-nginx
fi

# Stop Nginx temporarily for certificate generation
systemctl stop nginx

# Configure firewall for HTTP/HTTPS
echo -e "${GREEN}[4/8] Configuring firewall...${NC}"
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
echo -e "${GREEN}[5/8] Obtaining SSL certificate from Let's Encrypt...${NC}"
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
echo -e "${GREEN}[6/8] Creating Nginx configuration...${NC}"

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
echo -e "${GREEN}[7/8] Testing Nginx configuration...${NC}"
nginx -t || {
    echo -e "${RED}Nginx configuration test failed!${NC}"
    exit 1
}

# Start and enable services
echo -e "${GREEN}[8/8] Starting services...${NC}"
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

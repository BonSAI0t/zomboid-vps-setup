# Web-LGSM Quick Start Guide

**Note:** These scripts and README were made with LLM Chatbot AI Assistance (Claude).

## What is Web-LGSM?

Web-LGSM is a web-based management interface for LinuxGSM servers. It provides an easy-to-use dashboard for managing your game servers through your browser instead of the command line.

## Features

- 🖥️ **Web Dashboard** - Manage servers from any browser
- 📊 **Server Monitoring** - Real-time status and performance metrics
- 🎮 **Easy Controls** - Start, stop, restart with a click
- 📝 **Config Editor** - Edit configuration files directly in the browser
- 📺 **Live Console** - View live server console output
- 🔧 **Multi-Server Support** - Manage multiple game servers from one interface

## Installation

### Step 1: Install Web-LGSM (HTTP)

```bash
curl -sSL https://raw.githubusercontent.com/BonSAI0t/zomboid-vps-setup/main/2-web-lgsm-setup-script.sh | sudo bash
```

### Step 2 (Optional): Add SSL/HTTPS

If you want to secure your web-lgsm with SSL (requires a domain name):

```bash
wget https://raw.githubusercontent.com/BonSAI0t/zomboid-vps-setup/main/3-ssl-setup-script.sh
chmod +x 3-ssl-setup-script.sh
sudo ./3-ssl-setup-script.sh yourdomain.com your@email.com
```

After installation, access web-lgsm at:

**Without SSL:**
```
http://YOUR_SERVER_IP:12357
```

**With SSL:**
```
https://yourdomain.com
```

## First Time Setup

### 1. Access the Web Interface

Open your browser and navigate to:
```
http://YOUR_SERVER_IP:12357
```

### 2. Create Admin Account

On first access, you'll see a setup page:
- Enter desired username
- Create a strong password
- Click "Create Account"

### 3. Login

After account creation, you'll be automatically logged in and redirected to the dashboard.

### 4. Your Server Should Appear

If you installed Project Zomboid using the script, it should automatically appear in the web-lgsm interface under "Installed Servers".

## Using Web-LGSM

### Dashboard Overview

The main dashboard shows:
- **Installed Servers** - List of all your LGSM servers
- **Server Status** - Whether each server is running or stopped
- **Quick Actions** - Buttons to control your servers

### Server Controls Page

Click on a server name to access its control page where you can:
- **Start/Stop/Restart** the server
- **Update** the server
- **View Details** and status
- **Check Logs** with live console output
- **Edit Configuration** files
- **Run Commands** like backup, monitor, validate

### Live Console Output

When you run commands, you'll see:
- Real-time output from the command
- Progress indicators
- Success/failure messages
- Timestamps

### Configuration Editor

Edit server configuration files directly:
1. Click "Edit Config" on the server controls page
2. Modify settings in the web editor
3. Save changes
4. Restart server to apply changes

## Managing the Web-LGSM Service

### Systemd Commands (Recommended)

```bash
# Start web interface
sudo systemctl start web-lgsm

# Stop web interface
sudo systemctl stop web-lgsm

# Restart web interface
sudo systemctl restart web-lgsm

# Check status
sudo systemctl status web-lgsm

# Enable auto-start on boot
sudo systemctl enable web-lgsm

# Disable auto-start
sudo systemctl disable web-lgsm

# View logs
sudo journalctl -u web-lgsm -f
```

### Manual Control

```bash
# Switch to pzserver user
su - pzserver

# Start web-lgsm
cd ~/web-lgsm
./web-lgsm.py

# Stop web-lgsm
./web-lgsm.py --stop
```

## Configuration

### Web-LGSM Config File

Location: `~/web-lgsm/main.conf`

```ini
[FLASK]
PORT = 12357              # Change web interface port
DEBUG = False             # Enable/disable debug mode
HOST = 0.0.0.0           # Listen address (0.0.0.0 = all interfaces)

[SECURITY]
SESSION_TIMEOUT = 30      # Session timeout in minutes
```

After changing config, restart the service:
```bash
sudo systemctl restart web-lgsm
```

## Security Considerations

### Default Setup (HTTP Only)

If you ran the script without SSL, web-LGSM runs on plain HTTP. This is fine for:
- Local network access only
- Testing and development
- VPN-only access

### Adding SSL Later

You can add SSL at any time by running the SSL setup script with your domain and email:

```bash
wget https://raw.githubusercontent.com/BonSAI0t/zomboid-vps-setup/main/3-ssl-setup-script.sh
chmod +x 3-ssl-setup-script.sh
sudo ./3-ssl-setup-script.sh yourdomain.com your@email.com
```

This will:
- Install Nginx reverse proxy
- Obtain free SSL certificate from Let's Encrypt
- Configure auto-renewal
- Redirect HTTP to HTTPS
- Block direct access to port 12357

### For Remote/Public Access

**Option 1: Use the SSL Setup Script (Recommended)**
```bash
wget https://raw.githubusercontent.com/BonSAI0t/zomboid-vps-setup/main/3-ssl-setup-script.sh
chmod +x 3-ssl-setup-script.sh
sudo ./3-ssl-setup-script.sh yourdomain.com your@email.com
```

**Option 2: VPN Access**
- Set up WireGuard, OpenVPN, or similar
- Access web-lgsm through VPN
- Keep port 12357 firewalled from internet

**Option 3: Manual Reverse Proxy with SSL**
If you prefer to configure manually, see the Nginx example below.

### Manual Nginx Reverse Proxy Example

**Note:** The 3-ssl-setup-script.sh script does all of this automatically. This is only if you want to configure manually.

```nginx
server {
    listen 443 ssl http2;
    server_name zomboid.yourdomain.com;

    ssl_certificate /etc/letsencrypt/live/yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/yourdomain.com/privkey.pem;

    location / {
        proxy_pass http://localhost:12357;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket support for live console
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

# Redirect HTTP to HTTPS
server {
    listen 80;
    server_name zomboid.yourdomain.com;
    return 301 https://$server_name$request_uri;
}
```

Then firewall the direct port:
```bash
sudo ufw deny 12357/tcp
```

### SSL Certificate Management (If Using SSL Setup)

### Certificate Auto-Renewal

If you used the SSL setup, certificates automatically renew via cron. Check renewal status:

```bash
sudo certbot certificates
```

### Manual Renewal

Force a renewal test:
```bash
sudo certbot renew --dry-run
```

Manually renew:
```bash
sudo certbot renew
sudo systemctl reload nginx
```

### Certificate Troubleshooting

**Check certificate expiry:**
```bash
sudo certbot certificates
```

**View renewal logs:**
```bash
sudo cat /var/log/letsencrypt/letsencrypt.log
```

**Test Nginx config:**
```bash
sudo nginx -t
```

## Firewall Configuration

**Allow from specific IP only:**
```bash
sudo ufw allow from YOUR_IP to any port 12357 proto tcp
```

**Allow from local network only:**
```bash
sudo ufw allow from 192.168.1.0/24 to any port 12357 proto tcp
```

**Block from internet:**
```bash
sudo ufw deny 12357/tcp
```

## Troubleshooting

### Can't Access Web Interface

**Check if service is running:**
```bash
sudo systemctl status web-lgsm
```

**Check if port is listening:**
```bash
sudo netstat -tulpn | grep 12357
# or
sudo ss -tulpn | grep 12357
```

**Check firewall:**
```bash
sudo ufw status
# or
sudo firewall-cmd --list-all
```

**Test from localhost:**
```bash
curl http://localhost:12357
```

### Service Won't Start

**View error logs:**
```bash
sudo journalctl -u web-lgsm -n 50
```

**Check for port conflicts:**
```bash
sudo lsof -i :12357
```

**Manually test:**
```bash
su - pzserver
cd ~/web-lgsm
./web-lgsm.py
# Watch for error messages
```

### Server Not Appearing in Interface

1. **Check if LGSM server exists:**
```bash
su - pzserver
ls -la ~/pzserver
./pzserver details
```

2. **Refresh the web page**

3. **Check web-lgsm logs:**
```bash
cat ~/web-lgsm/logs/web-lgsm.log
```

### Configuration Changes Not Applying

1. Make sure you saved the file
2. Restart the game server (not just web-lgsm):
```bash
./pzserver restart
```

### Forgot Web-LGSM Password

**Reset by deleting database and recreating user:**
```bash
su - pzserver
cd ~/web-lgsm
rm -f instance/web-lgsm.db  # Deletes user database
./web-lgsm.py --stop
./web-lgsm.py
# Navigate to http://YOUR_SERVER_IP:12357 and create new account
```

## Common Tasks

### Adding Another Game Server

1. Install the game server using LGSM:
```bash
su - pzserver
wget -O linuxgsm.sh https://linuxgsm.sh
chmod +x linuxgsm.sh
./linuxgsm.sh csgoserver  # Example: Counter-Strike GO
./csgoserver auto-install
```

2. The server should automatically appear in web-lgsm

### Changing Web-LGSM Port

1. Edit config:
```bash
nano ~/web-lgsm/main.conf
```

2. Change PORT value:
```ini
[FLASK]
PORT = 8080  # Or any available port
```

3. Update firewall:
```bash
sudo ufw allow 8080/tcp
sudo ufw delete allow 12357/tcp
```

4. Restart service:
```bash
sudo systemctl restart web-lgsm
```

### Backup Web-LGSM Settings

```bash
# Backup configuration
cp ~/web-lgsm/main.conf ~/web-lgsm-config-backup.conf

# Backup user database
cp ~/web-lgsm/instance/web-lgsm.db ~/web-lgsm-users-backup.db
```

## Advanced Usage

### Running Multiple Web-LGSM Instances

You can run multiple instances on different ports for different users/purposes:

1. Clone web-lgsm to different directory
2. Change PORT in main.conf
3. Create separate systemd service file
4. Start both services

### Monitoring with systemd

```bash
# Enable auto-restart on failure
sudo systemctl edit web-lgsm
```

Add:
```ini
[Service]
Restart=always
RestartSec=10
```

### Log Management

**View all logs:**
```bash
cat ~/web-lgsm/logs/web-lgsm.log
```

**Follow logs in real-time:**
```bash
tail -f ~/web-lgsm/logs/web-lgsm.log
```

**Rotate logs (prevent large files):**
```bash
# Add to crontab
0 0 * * 0 mv ~/web-lgsm/logs/web-lgsm.log ~/web-lgsm/logs/web-lgsm.log.old
```

## Getting Help

- **GitHub Issues:** https://github.com/BlueSquare23/web-lgsm/issues
- **LGSM Discord:** https://linuxgsm.com/discord
- **Web-LGSM Docs:** https://github.com/BlueSquare23/web-lgsm/tree/master/docs

## Tips & Best Practices

1. **Use strong passwords** - Both for web-lgsm and game server admin
2. **Keep web-lgsm updated** - `cd ~/web-lgsm && git pull`
3. **Regular backups** - Use the backup function frequently
4. **Monitor logs** - Check for errors and unusual activity
5. **Use SSL** - If accessing remotely, always use HTTPS
6. **Limit access** - Use firewall rules to restrict who can access
7. **Test changes** - Try configuration changes on test server first
8. **Document settings** - Keep notes on custom configurations

---

**Remember:** Web-LGSM is a powerful tool that gives browser-based access to your server. Treat your login credentials like you would SSH keys!

# Project Zomboid VPS Setup - Quick Guide

## One-Punch Installation

### Option 1: Direct Download & Run
```bash
wget https://raw.githubusercontent.com/YOUR-REPO/zomboid-setup.sh
chmod +x zomboid-setup.sh
sudo ./zomboid-setup.sh
```

### Option 2: Curl One-Liner
```bash
curl -sSL https://raw.githubusercontent.com/YOUR-REPO/zomboid-setup.sh | sudo bash
```

## What This Script Does

1. Updates system packages
2. Installs all dependencies (Java 17, SteamCMD, Git, Python, etc.)
3. Creates dedicated `pzserver` user
4. Configures firewall rules (UFW/firewalld)
5. Downloads and installs LinuxGSM
6. Installs Project Zomboid server
7. Creates basic configuration
8. Sets up systemd service for auto-start
9. **Installs web-lgsm web interface**
10. **Sets up systemd service for web-lgsm**

## Optional: SSL Setup

After the main installation, you can optionally set up HTTPS access with a free Let's Encrypt certificate:

```bash
# Download the SSL setup script
wget https://raw.githubusercontent.com/YOUR_REPO/optional-ssl-setup.sh
chmod +x optional-ssl-setup.sh

# Run with your domain and email
sudo ./optional-ssl-setup.sh yourdomain.com your@email.com
```

**Prerequisites:**
- Domain name pointing to your server's IP
- Ports 80 and 443 accessible

**What it does:**
- Installs Nginx reverse proxy
- Obtains free SSL certificate from Let's Encrypt
- Auto-redirects HTTP to HTTPS
- Blocks direct access to port 12357
- Sets up automatic certificate renewal

After SSL setup, access web-lgsm at: `https://yourdomain.com`

## Post-Installation Configuration

### Switch to Server User
```bash
su - pzserver
```

### Essential Server Commands
```bash
./pzserver start          # Start the server
./pzserver stop           # Stop the server
./pzserver restart        # Restart the server
./pzserver details        # Show server status and info
./pzserver console        # Attach to server console (Ctrl+B then D to detach)
./pzserver update         # Update server
./pzserver validate       # Verify server files
./pzserver backup         # Create backup
./pzserver monitor        # Check if server is running
```

### Using Systemd (as root)
```bash
sudo systemctl start pzserver
sudo systemctl stop pzserver
sudo systemctl restart pzserver
sudo systemctl status pzserver
sudo systemctl enable pzserver   # Enable auto-start on boot
```

## Web-LGSM Web Interface

### What is Web-LGSM?

Web-LGSM is a Python Flask-based web interface for managing your LGSM servers through a browser. It provides:
- Easy-to-use web dashboard
- Server status monitoring
- Start/stop/restart controls
- Configuration file editing
- Live console output
- Support for multiple game servers

### Accessing Web-LGSM

After installation, web-lgsm is available at:
```
http://YOUR_SERVER_IP:12357
```

### Web-LGSM Commands

**Using systemd (recommended):**
```bash
sudo systemctl start web-lgsm      # Start web interface
sudo systemctl stop web-lgsm       # Stop web interface
sudo systemctl restart web-lgsm    # Restart web interface
sudo systemctl status web-lgsm     # Check status
sudo systemctl enable web-lgsm     # Enable auto-start on boot
```

**Manual control (as pzserver user):**
```bash
su - pzserver
cd ~/web-lgsm
./web-lgsm.py                # Start web interface
./web-lgsm.py --stop         # Stop web interface
```

### First Time Setup

1. Navigate to `http://YOUR_SERVER_IP:12357`
2. Create your admin account on the setup page
3. Log in with your new credentials
4. Your Project Zomboid server should automatically appear in the interface

### Web-LGSM Security

**IMPORTANT:** The web-lgsm interface runs on HTTP by default (not HTTPS). For security:

1. **Local Network Only:** Best for servers only accessible on your local network
2. **VPN Access:** Access through a VPN like WireGuard or OpenVPN
3. **Reverse Proxy with SSL:** For public access, use Nginx/Apache with SSL (see below)
4. **Firewall:** Block port 12357 from the internet if not needed externally

### Setting up Reverse Proxy with SSL (Recommended for Public Access)

**Nginx Example:**
```nginx
server {
    listen 443 ssl;
    server_name your-domain.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

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
```

**Apache Example:**
```apache
<VirtualHost *:443>
    ServerName your-domain.com
    
    SSLEngine on
    SSLCertificateFile /path/to/cert.pem
    SSLCertificateKeyFile /path/to/key.pem
    
    ProxyPreserveHost On
    ProxyPass / http://localhost:12357/
    ProxyPassReverse / http://localhost:12357/
    
    # WebSocket support
    RewriteEngine on
    RewriteCond %{HTTP:Upgrade} websocket [NC]
    RewriteCond %{HTTP:Connection} upgrade [NC]
    RewriteRule ^/?(.*) "ws://localhost:12357/$1" [P,L]
</VirtualHost>
```

### Web-LGSM Configuration

Configuration file: `~/web-lgsm/main.conf`

Key settings you may want to customize:
```ini
[FLASK]
PORT = 12357          # Web interface port
DEBUG = False         # Enable/disable debug mode
SECRET_KEY = <auto>   # Session encryption key

[SECURITY]
SESSION_TIMEOUT = 30  # Session timeout in minutes
```

### Troubleshooting Web-LGSM

**Check if web-lgsm is running:**
```bash
sudo systemctl status web-lgsm
netstat -tulpn | grep 12357
```

**View web-lgsm logs:**
```bash
journalctl -u web-lgsm -f        # Follow logs
journalctl -u web-lgsm -n 50     # Last 50 lines
```

**Web-lgsm won't start:**
```bash
# Check for port conflicts
sudo lsof -i :12357

# Manually test
su - pzserver
cd ~/web-lgsm
./web-lgsm.py
```

**Can't access web interface:**
- Check firewall rules: `sudo ufw status` or `sudo firewall-cmd --list-all`
- Verify port 12357 is open
- Check if service is running: `sudo systemctl status web-lgsm`
- Try accessing from localhost first: `curl http://localhost:12357`

## Configuration Files

### 1. LinuxGSM Config
**Location:** `~/lgsm/config-lgsm/pzserver/pzserver.cfg`

```bash
nano ~/lgsm/config-lgsm/pzserver/pzserver.cfg
```

Key settings:
- `servername` - Server name shown in browser
- `adminpassword` - RCON password
- `maxplayers` - Maximum players
- `port` - Game port (default: 16261)

### 2. Server INI File
**Location:** `~/Zomboid/Server/servertest.ini`

```bash
nano ~/Zomboid/Server/servertest.ini
```

Important settings:
```ini
PublicName=My Awesome Server
PublicDescription=A friendly survival server
MaxPlayers=16
PauseEmpty=true
PVP=true
GlobalChat=true
AutoCreateUserInWhiteList=true
Open=true
Public=true
```

### 3. Server Rules
**Location:** `~/Zomboid/Server/servertest_SandboxVars.lua`

Configure gameplay settings like:
- Zombie population
- Loot rarity
- XP multipliers
- Day length
- And much more

## Firewall Ports

Make sure these ports are open on your VPS:
- **16261/UDP** - Game port (required)
- **16262/UDP** - Query port (required)
- **8766/TCP** - RCON port (optional, for remote admin)
- **12357/TCP** - Web-LGSM interface (optional, for web management)

### Manual Firewall Configuration

**UFW (Ubuntu/Debian):**
```bash
sudo ufw allow 16261/udp
sudo ufw allow 16262/udp
sudo ufw allow 8766/tcp
sudo ufw allow 12357/tcp   # For web-lgsm
```

**Firewalld (CentOS/Rocky):**
```bash
sudo firewall-cmd --permanent --add-port=16261/udp
sudo firewall-cmd --permanent --add-port=16262/udp
sudo firewall-cmd --permanent --add-port=8766/tcp
sudo firewall-cmd --permanent --add-port=12357/tcp  # For web-lgsm
sudo firewall-cmd --reload
```

**Cloud Provider Firewall:**
Also configure your VPS provider's firewall (AWS Security Groups, DigitalOcean Firewall, etc.)

**Security Note:** If you're not using web-lgsm remotely, consider blocking port 12357 from external access and only allow local connections or VPN access.

## Server Management

### View Server Logs
```bash
./pzserver console  # Live console (Ctrl+B then D to detach)
cat ~/log/server/pzserver-console.log
tail -f ~/log/server/pzserver-console.log
```

### Update Server
```bash
./pzserver update
```

### Backup Server
```bash
./pzserver backup
# Backups stored in ~/backups/
```

### Performance Monitoring
```bash
./pzserver details
./pzserver monitor
```

## Admin Commands (In-Game)

Connect to RCON or use in-game admin panel:

```
/adduser "username" "password"      # Add user
/setaccesslevel "username" admin    # Make admin
/save                                # Save world
/quit                                # Shutdown server
/additem "username" "item"          # Give item
/teleport "player" x,y,z            # Teleport player
```

## Mods Installation

### Workshop Mods
1. Edit `~/Zomboid/Server/servertest.ini`
2. Add Workshop IDs to `WorkshopItems=` line
3. Add mod IDs to `Mods=` line

Example:
```ini
WorkshopItems=2169435993;2398274461
Mods=Brita;BetterSorting
```

### Manual Mods
Place in: `~/Zomboid/mods/`

## Troubleshooting

### Server Won't Start
```bash
./pzserver details  # Check status
./pzserver console  # View console output
cat ~/log/server/pzserver-console.log
```

### Check Java Version
```bash
java -version  # Should be Java 17+
```

### Check Port Availability
```bash
netstat -tulpn | grep 16261
ss -tulpn | grep 16261
```

### Reinstall Server
```bash
./pzserver validate  # Verify files
./pzserver reinstall # Full reinstall
```

### Check LinuxGSM Logs
```bash
cat ~/log/script/pzserver-script.log
```

## Performance Optimization

### Allocate More RAM
Edit `~/lgsm/config-lgsm/pzserver/pzserver.cfg`:
```bash
# Add/modify:
javaparam="-Xms2G -Xmx4G"  # 2GB initial, 4GB max
```

### Server Performance Settings
Edit `~/Zomboid/Server/servertest.ini`:
```ini
ServerPlayerSaveOnABitPerUpdate=true
BackupsOnVersionChange=false
BackupsOnStart=false
```

## VPS Recommendations

### Minimum Specs
- 2 CPU cores
- 4 GB RAM
- 20 GB storage
- Ubuntu 22.04 or Debian 11+

### Recommended Specs
- 4 CPU cores
- 8 GB RAM
- 40 GB storage
- Good network connection

### Popular VPS Providers
- DigitalOcean (Droplet)
- Vultr
- Linode
- Hetzner
- AWS Lightsail

## Security Best Practices

1. **Change default passwords immediately**
2. **Use strong admin passwords** (both LGSM and web-lgsm)
3. **Keep server updated:** `./pzserver update`
4. **Regular backups:** `./pzserver backup`
5. **Use whitelist if desired**
6. **Monitor server logs**
7. **Keep OS updated:** `sudo apt update && sudo apt upgrade`
8. **Secure web-lgsm:**
   - Use HTTPS/SSL via reverse proxy for remote access
   - Or limit to local network/VPN only
   - Change default web-lgsm port if desired
   - Use strong web-lgsm admin passwords
9. **Firewall configuration:** Only open necessary ports

## Additional Resources

- **LinuxGSM Docs:** https://docs.linuxgsm.com/
- **Project Zomboid Wiki:** https://pzwiki.net/
- **Server Settings Guide:** https://pzwiki.net/wiki/Server_Settings
- **LinuxGSM Discord:** https://linuxgsm.com/discord
- **Web-LGSM GitHub:** https://github.com/BlueSquare23/web-lgsm
- **Web-LGSM Documentation:** https://github.com/BlueSquare23/web-lgsm/tree/master/docs

## Quick Cheat Sheet

```bash
# As root - Game Server
sudo systemctl start pzserver
sudo systemctl status pzserver

# As root - Web Interface
sudo systemctl start web-lgsm
sudo systemctl status web-lgsm

# As pzserver user - Game Server
su - pzserver
./pzserver start
./pzserver console
./pzserver update
./pzserver backup

# As pzserver user - Web Interface
cd ~/web-lgsm
./web-lgsm.py         # Start
./web-lgsm.py --stop  # Stop

# Configuration Files
nano ~/lgsm/config-lgsm/pzserver/pzserver.cfg
nano ~/Zomboid/Server/servertest.ini
nano ~/web-lgsm/main.conf

# Access Points
# Game Server: Connect via game client on port 16261
# Web Interface: http://YOUR_SERVER_IP:12357
```

---

**Remember:** Always test configuration changes and keep backups!

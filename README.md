# Project Zomboid VPS Server - One-Line Installer

Automated setup script for running a Project Zomboid server on Ubuntu VPS (Tested on 24.04, should work on 22.04).

**Note:** These scripts and README were made with LLM Chatbot AI Assistance (Claude).

## Foreword on security and responsibility
This script does a couple of things insecurely.
The core requirement of this script is to be a one touch zomboid install - you rent a VPS from somewhere, you remote in, you pull the script (see quick install), and then you get an IP and a port.
Therefore - I've removed as much complexity as possible, in some cases this involves taking shortcuts - e.g. giving the pzserver user the ability to run commands as root until the server is up and running.
My hope with this script is twofold:

1. Minimize the amount of pain it takes to spin up a new zomboid server
2. Lower the burden for people who want to try their hand at starting up a dedicated server outside the main providers.
3. While there are some really great providers out there - E.g. shoutout indifferent broccoli - there's a few really good reasons to control your own VPS or hardware.
- Game server providers are often at the mercy of dev cycles. A patch drops, everyone starts updating, performance across the board tanks.
- Using a VPS insulates you somewhat from this as their market is much larger - they're serving a number of different clients so they don't often get hit by the stampede problems game providers do
- If your VPS performance starts to tank, and you no longer trust your provider, it's really easy to migrate to a new provider - run the script on a new provider, stop the servers, then copy the Zomboid folder across. Done.

With that in mind - feel free to take this and customize it how you like. Suggestions:

1. Admin password should be set as a variable using a random number generator
2. Consider adding SSH PubKey authentication for additional security - https://www.ssh.com/academy/ssh/public-key-authentication
3. This install process could be wrapped in a screen terminal for remote installation resilience

I'm sure there's more improvements but anyway, hope this helps.


## Quick Install

### One Command - Complete Setup

```bash
curl -sSL https://raw.githubusercontent.com/BonSAI0t/zomboid-vps-setup/main/1-pz-installer.sh | sudo bash
```

**This installs everything:**
- Project Zomboid server (Build 42/unstable)
- Web-LGSM management interface with HTTPS
- Nginx reverse proxy with self-signed SSL
- Fail2ban protection (SSH + Web)
- Hardened SSH on port 2222

**Access:**
- Game: `YOUR_SERVER_IP:16261`
- Web: `https://YOUR_SERVER_IP` (accept browser warning)

### Optional: Upgrade to Let's Encrypt

If you have a domain name, get a verified SSL certificate (no browser warnings):

```bash
wget https://raw.githubusercontent.com/BonSAI0t/zomboid-vps-setup/main/3-upgrade-to-letsencrypt.sh
chmod +x 3-upgrade-to-letsencrypt.sh
sudo ./3-upgrade-to-letsencrypt.sh yourdomain.com your@email.com
```

Access at: `https://yourdomain.com` (verified, no warnings)

### Standalone Web-LGSM Install

If you already have a game server and just want to add web management:

```bash
curl -sSL https://raw.githubusercontent.com/BonSAI0t/zomboid-vps-setup/main/2-web-lgsm-setup-script.sh | sudo bash
```

## What It Does

### Game Server Setup
1. Updates system packages
2. Installs and configures fail2ban for SSH protection
3. Creates dedicated `pzserver` user
4. Installs LinuxGSM and all dependencies
5. Installs Project Zomboid server (unstable branch/B42)
6. Auto-creates admin account with default password
7. **Hardens SSH security** (moves SSH to port 2222 to prevent bot lag)

### Web Management Setup
8. Installs Web-LGSM dashboard (browser-based server control)
9. Installs Nginx reverse proxy
10. Generates self-signed SSL certificate for HTTPS
11. Configures Nginx with security headers and WebSocket support
12. Adds fail2ban protection for web interface (auth attempts, rate limiting, bot scanning)
13. Configures firewall (game ports 16261-16262, SSH 2222, HTTP/HTTPS 80/443)

## Post-Installation

### Default Admin Credentials

**CHANGE THESE IMMEDIATELY**
setpassword : Use this command to change password for a user. Use: /setpassword "admin" "<password>"

This can be done from the console:
setpassword "admin" "<password>"
Or from a logged in player:
/setpassword "admin" "<password>" 

- Username: `admin`
- Password: `ChangeThisPassword123`

### SSH Port Change

The installer moves SSH from port 22 to port 2222 to reduce bot scanning lag.

**From now on, connect using:**
```bash
ssh -p 2222 root@YOUR_SERVER_IP
```

### Managing Your Server

Connect via SSH

Switch to the game server user:
```bash
su - pzserver
```

Server commands:
```bash
./pzserver start      # Start server
./pzserver stop       # Stop server
./pzserver restart    # Restart server
./pzserver console    # Attach to console (Ctrl+B then D to detach)
./pzserver details    # View server status
./pzserver update     # Update server
./pzserver backup     # Create backup
```

### Server Details

- **Game Port:** 16261/udp
- **Query Port:** 16262/udp
- **SSH Port:** 2222/tcp (changed from 22)

Your friends connect to: `YOUR_SERVER_IP:16261`

## Configuration

### Game Settings
```bash
nano ~/Zomboid/Server/pzserver.ini
```

Configure:
- Server name shown in browser
- PVP enabled/disabled
- Max players
- Pause when empty
- Public/private server
- Etc

### Setting Server Password

In-game or via console:
```
/changeoption Password "YourNewPassword"
```

Or edit the server files directly and restart.

## Firewall Ports

The script automatically configures these ports:

- **2222/tcp** - SSH (hardened)
- **16261/udp** - Game port
- **16262/udp** - Query port


## Common Issues

### SteamCMD Error During Install

You'll see: `Error! Installing pzserver: SteamCMD: Unknown error occurred`

**This is normal.** LGSM will auto-retry and it will work within 30-60 seconds. Just wait.

### Can't Connect After Install

1. Check if server is running: `./pzserver details`
2. Confirm you have the right IP and port.
3. Verify firewall: `sudo ufw status`
4. Verify ports are open: `ss -tulpn | grep 16261`

### Forgot SSH Port

The new SSH port is **2222**. Connect with:
```bash
ssh -p 2222 root@YOUR_SERVER_IP
```

### Server Not Starting

Check logs:
```bash
./pzserver console
# Or
cat ~/log/console/pzserver-console.log
```

## Server Backups

Create backup:
```bash
./pzserver backup
```

Backups are stored in: `~/backups/`

## Updating the Server

```bash
./pzserver update
```

LGSM will check for updates and apply them.

## Security Notes

- SSH has been moved to port 2222 to reduce bot attack traffic
- fail2ban is active and will ban IPs after 3 failed login attempts
- Change the default game admin password immediately
- Keep your server updated regularly
- Use strong passwords

## Uninstalling

To completely remove the server:

Honestly it's easiest to just nuke the server from your VPS console, however.

```bash
# As root
pkill -u pzserver
userdel -r pzserver
rm -f /etc/sudoers.d/pzserver-lgsm
ufw delete allow 16261/udp
ufw delete allow 16262/udp
```

Should work

## Support

- **LinuxGSM Docs:** https://docs.linuxgsm.com/
- **Project Zomboid Wiki:** https://pzwiki.net/
- **Server Settings Guide:** https://pzwiki.net/wiki/Server_Settings (not updated for B42)
- **LinuxGSM Discord:** https://linuxgsm.com/discord

## Credits

- LinuxGSM - https://linuxgsm.com/
- Project Zomboid - https://projectzomboid.com/
- Bonzy - https://twitch.tv/SoHotBonzy
---

**Quick Reference**

```bash
# Connect to server
ssh -p 2222 root@YOUR_SERVER_IP

# Switch to game user
su - pzserver

# Start server
./pzserver start

# View status
./pzserver details

# Attach to console
./pzserver console
# (Ctrl+B then D to detach)
```

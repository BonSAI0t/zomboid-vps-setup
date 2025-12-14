# Project Zomboid VPS Server - One-Line Installer

Automated setup script for running a Project Zomboid server on Ubuntu VPS (Tested on 24.04, should work on 22.04).

## Quick Install

```bash
curl -sSL https://raw.githubusercontent.com/BonSAI0t/zomboid-vps-setup/main/pz-installer.sh | sudo bash
```

That's it. The script handles everything automatically.

## What It Does

1. Updates system packages
2. Installs and configures fail2ban for ssh attempts
3. Creates dedicated `pzserver` user
4. Installs LinuxGSM and all dependencies
5. Installs Project Zomboid server (unstable branch/B42)
6. Auto-creates admin account with default password
7. Configures firewall (game ports + SSH)
8. **Hardens SSH security** (moves SSH to port 2222 to prevent bot lag)

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

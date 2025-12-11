# Deploying to Existing CM4 System (Raspberry Pi OS Bookworm Desktop)

This guide covers deploying PouCon to a Compute Module 4 running **Raspberry Pi OS Desktop 64-bit Bookworm (Debian 12)** with vendor hardware and drivers already configured.

## Target System Specifications

- **OS**: Raspberry Pi OS Desktop 64-bit (Bookworm, Debian 12)
- **Architecture**: aarch64 (ARM 64-bit)
- **Desktop Environment**: LXDE/Wayfire (GUI running)
- **Vendor Hardware**: Pre-configured with drivers

## Quick Start (TL;DR)

```bash
# 1. On dev machine - Build release using Bookworm Docker
docker run -it --rm -v $(pwd):/app -w /app \
  hexpm/elixir:1.15.7-erlang-26.1.2-debian-bookworm-20231009-slim \
  bash -c "mix local.hex --force && mix local.rebar --force && \
           mix deps.get --only prod && MIX_ENV=prod mix assets.deploy && \
           MIX_ENV=prod mix release"

tar -czf pou_con_release.tar.gz -C _build/prod/rel/pou_con .
scp pou_con_release.tar.gz pi@<CM4-IP>:/home/pi/

# 2. On CM4 - Extract and configure
ssh pi@<CM4-IP>
sudo apt update && sudo apt install -y erlang-base sqlite3 libsqlite3-dev
sudo mkdir -p /opt/pou_con && sudo tar -xzf pou_con_release.tar.gz -C /opt/pou_con
sudo chown -R pi:pi /opt/pou_con
cd /opt/pou_con && mkdir -p data

# Create .env file
cat > .env << 'EOF'
DATABASE_PATH=/opt/pou_con/data/pou_con_prod.db
SECRET_KEY_BASE=$(openssl rand -base64 48)
PHX_HOST=localhost
PORT=4000
MIX_ENV=prod
SIMULATE_DEVICES=0
EOF

# 3. Initialize and start
export $(cat .env | xargs)
./bin/pou_con eval "PouCon.Release.migrate()"
sudo usermod -a -G dialout pi

# 4. Set up systemd service (see full guide below)
# 5. Access web interface: http://<CM4-IP>:4000
```

Continue reading for detailed instructions and production optimizations.

## Prerequisites on Target CM4

### 1. Check System Information

```bash
# SSH into your CM4 (or open Terminal on desktop)
ssh pi@<cm4-ip-address>

# Verify OS version
cat /etc/os-release
# Should show: PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"

# Check architecture
uname -m
# Should show: aarch64

# Verify hardware drivers
ls -la /dev/ttyUSB* /dev/ttyAMA* /dev/serial*
# Should list your RS485/Modbus serial ports

# Check available disk space
df -h
# Need at least 1GB free (Desktop OS uses more space)

# Check memory
free -h
# Desktop version uses ~400-600MB for GUI
```

### 2. Install Runtime Dependencies

```bash
# Update package list
sudo apt update

# Install required packages
sudo apt install -y \
  erlang-base \
  erlang-dev \
  erlang-parsetools \
  erlang-eunit \
  erlang-ssl \
  erlang-inets \
  erlang-crypto \
  sqlite3 \
  libsqlite3-dev

# Verify Erlang installation
erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell
# Should show OTP version (e.g., "25" or "26")
```

## Building the Release

### Option A: Build on Development Machine (Cross-compile) - RECOMMENDED

⚠️ **IMPORTANT**: Build on Debian Bookworm to match your CM4's OS version and avoid GLIBC compatibility issues.

```bash
# On your development machine
cd /home/tankwanghow/Projects/elixir/pou_con

# Use Docker with Bookworm base image to match CM4
docker run -it --rm \
  -v $(pwd):/app \
  -w /app \
  hexpm/elixir:1.15.7-erlang-26.1.2-debian-bookworm-20231009-slim \
  bash

# Inside Docker container:
mix local.hex --force
mix local.rebar --force
mix deps.get --only prod
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release

# Exit Docker - release is now in _build/prod/rel/pou_con/
exit
```

**Why use Docker?** Even if your dev machine is not Bookworm, Docker ensures the compiled binaries (especially NIFs for SQLite and serial communication) match the CM4's system libraries.

### Option B: Build Directly on CM4

```bash
# SSH into CM4
ssh pi@<cm4-ip-address>

# Install Elixir (if not already installed)
sudo apt install -y elixir

# Clone or copy your project
git clone <your-repo-url> /home/pi/pou_con
cd /home/pi/pou_con

# Build release
mix local.hex --force
mix local.rebar --force
mix deps.get --only prod
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release
```

## Deploying the Application

### 1. Transfer Release to CM4 (if built on dev machine)

```bash
# On your development machine
cd /home/tankwanghow/Projects/elixir/pou_con

# Create deployment package
tar -czf pou_con_release.tar.gz \
  -C _build/prod/rel/pou_con \
  .

# Transfer to CM4
scp pou_con_release.tar.gz pi@<cm4-ip-address>:/home/pi/

# SSH into CM4
ssh pi@<cm4-ip-address>

# Extract release
sudo mkdir -p /opt/pou_con
sudo tar -xzf /home/pi/pou_con_release.tar.gz -C /opt/pou_con
sudo chown -R pi:pi /opt/pou_con
```

### 2. Set Up Application Directories

```bash
# On CM4
sudo mkdir -p /opt/pou_con/data
sudo mkdir -p /var/log/pou_con
sudo chown -R pi:pi /opt/pou_con /var/log/pou_con

# Create environment configuration
sudo nano /opt/pou_con/.env
```

Add this content to `/opt/pou_con/.env`:

```bash
# Database
DATABASE_PATH=/opt/pou_con/data/pou_con_prod.db

# Phoenix
SECRET_KEY_BASE=$(openssl rand -base64 48)
PHX_HOST=localhost
PORT=4000

# Environment
MIX_ENV=prod

# Hardware (set to 0 for real hardware, 1 for simulation)
SIMULATE_DEVICES=0

# System identification (optional)
FARM_NAME="My Poultry Farm"
HOUSE_NUMBER="House 1"
```

Generate a real SECRET_KEY_BASE:
```bash
# Generate secret key
openssl rand -base64 48
# Copy the output and replace the value in .env
```

### 3. Initialize Database

```bash
# On CM4
cd /opt/pou_con

# Load environment variables
export $(cat .env | xargs)

# Run database migrations
./bin/pou_con eval "PouCon.Release.migrate()"

# Optional: Create initial admin user
./bin/pou_con eval "PouCon.Release.create_admin()"
```

### 4. Configure Serial Port Permissions

```bash
# On CM4
# Add pi user to dialout group for serial port access
sudo usermod -a -G dialout pi

# Set udev rules for persistent device names (optional)
sudo nano /etc/udev/rules.d/99-modbus.rules
```

Add content:
```
# Modbus RTU devices
SUBSYSTEM=="tty", ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="7523", SYMLINK+="modbus0"
SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", SYMLINK+="modbus1"
```

Reload udev:
```bash
sudo udevadm control --reload-rules
sudo udevadm trigger
```

### 5. Create Systemd Service

```bash
# On CM4
sudo nano /etc/systemd/system/pou_con.service
```

Add this content:

```ini
[Unit]
Description=PouCon Industrial Control System
After=network.target

[Service]
Type=simple
User=pi
Group=pi
WorkingDirectory=/opt/pou_con
EnvironmentFile=/opt/pou_con/.env
ExecStart=/opt/pou_con/bin/pou_con start
ExecStop=/opt/pou_con/bin/pou_con stop
Restart=always
RestartSec=5
StandardOutput=append:/var/log/pou_con/stdout.log
StandardError=append:/var/log/pou_con/stderr.log

# Security hardening (optional)
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```

Enable and start the service:

```bash
# Reload systemd
sudo systemctl daemon-reload

# Enable service to start on boot
sudo systemctl enable pou_con

# Start the service
sudo systemctl start pou_con

# Check status
sudo systemctl status pou_con
```

## Desktop OS Optimization for Production

Since you're running the **Desktop version**, consider these optimizations for production deployment:

### Option 1: Run as Headless (Disable GUI) - Best for Performance

If you don't need the desktop GUI running 24/7:

```bash
# On CM4
# Boot to console only (saves ~400MB RAM)
sudo raspi-config
# Choose: 1 System Options → S5 Boot / Auto Login → B1 Console

# Or via command line:
sudo systemctl set-default multi-user.target
sudo reboot
```

**Benefits:**
- Saves 400-600MB RAM
- Reduces CPU usage
- Less SD card wear
- Faster boot time

**Access GUI when needed:**
```bash
# Start GUI on demand
startx
```

### Option 2: Kiosk Mode (Fullscreen Browser) - Best for On-Site Display

Run Chromium in kiosk mode showing PouCon dashboard:

```bash
# On CM4
# Install required packages
sudo apt install -y unclutter

# Create kiosk startup script
nano /home/pi/kiosk.sh
```

Add this content:
```bash
#!/bin/bash
xset s off
xset -dpms
xset s noblank
unclutter -idle 0.5 -root &

chromium-browser --noerrdialogs \
  --disable-infobars \
  --kiosk \
  http://localhost:4000/dashboard
```

Make it executable and auto-start:
```bash
chmod +x /home/pi/kiosk.sh

# Auto-start on boot
mkdir -p /home/pi/.config/lxsession/LXDE-pi
nano /home/pi/.config/lxsession/LXDE-pi/autostart
```

Add:
```
@/home/pi/kiosk.sh
```

**Configure auto-login for kiosk:**
```bash
sudo raspi-config
# Choose: 1 System Options → S5 Boot / Auto Login → B4 Desktop Autologin
```

Reboot - GUI will auto-login and show PouCon dashboard fullscreen.

### Option 3: Keep Desktop as-is (Convenience)

If you want flexibility to use the desktop for configuration:

- **Access via VNC** for remote desktop (already installed on Raspberry Pi OS Desktop)
- **Reduce GUI resource usage:**

```bash
# Disable unnecessary services
sudo systemctl disable bluetooth
sudo systemctl disable avahi-daemon
sudo systemctl disable triggerhappy

# Reduce swap usage (helps SD card lifespan)
sudo nano /etc/sysctl.conf
# Add: vm.swappiness=10
```

## Verification and Testing

### 1. Check Application Logs

```bash
# View real-time logs
sudo journalctl -u pou_con -f

# Or check log files
tail -f /var/log/pou_con/stdout.log
tail -f /var/log/pou_con/stderr.log
```

### 2. Verify Web Interface

```bash
# On your development machine or another computer on the network
# Open browser to:
http://<cm4-ip-address>:4000

# Default login (if you ran create_admin):
# Username: admin
# Password: admin123  (change immediately!)
```

### 3. Test Hardware Communication

```bash
# On CM4, check if Modbus devices are responding
# Using the web interface:
# 1. Go to /admin/ports - configure your serial ports
# 2. Go to /admin/devices - add your Modbus devices
# 3. Go to /admin/simulation - verify device states are updating

# Or check from command line
./bin/pou_con remote
# In the remote console:
PouCon.Hardware.DeviceManager.get_all_device_data()
# Should show your devices and their states
# Press Ctrl+D to exit
```

### 4. Configure Time Sync (Critical for RTC Issues)

```bash
# On CM4
# Run sudo setup script for web-based time management
cd /opt/pou_con
sudo bash scripts/setup_sudo.sh

# This allows setting system time from web UI when RTC battery fails
```

## Configuration Workflow

After successful deployment, configure via web interface:

1. **Login** → http://<cm4-ip>:4000
2. **Admin → Ports** → Add your RS485/Modbus serial ports
3. **Admin → Devices** → Add Modbus devices (IO modules, sensors)
4. **Admin → Equipment** → Create equipment (fans, pumps, etc.) and link to devices
5. **Admin → Interlocks** → Define safety rules
6. **Automation Pages** → Configure schedules and auto-control

## Updating the Application

```bash
# On development machine - build new release
cd /home/tankwanghow/Projects/elixir/pou_con
# (Use Docker or build method from above)
scp pou_con_release.tar.gz pi@<cm4-ip>:/home/pi/

# On CM4
sudo systemctl stop pou_con
sudo tar -xzf /home/pi/pou_con_release.tar.gz -C /opt/pou_con
cd /opt/pou_con
export $(cat .env | xargs)
./bin/pou_con eval "PouCon.Release.migrate()"  # Run new migrations
sudo systemctl start pou_con
```

## Troubleshooting

### Application Won't Start

```bash
# Check Erlang compatibility
erl -eval 'halt().'

# Check environment variables
cat /opt/pou_con/.env

# Check permissions
ls -la /opt/pou_con/bin/pou_con
# Should be executable

# Try running manually
cd /opt/pou_con
export $(cat .env | xargs)
./bin/pou_con start
# Watch for error messages
```

### Serial Port Access Denied

```bash
# Verify group membership
groups pi
# Should include "dialout"

# If not, add and reboot
sudo usermod -a -G dialout pi
sudo reboot

# Check port permissions
ls -la /dev/ttyUSB0
# Should show: crw-rw---- 1 root dialout
```

### Database Migration Errors

```bash
# Check database file
ls -la /opt/pou_con/data/

# Reset database (⚠️ deletes all data!)
rm /opt/pou_con/data/pou_con_prod.db*
./bin/pou_con eval "PouCon.Release.migrate()"
```

### Memory/Performance Issues

```bash
# Check system resources
free -h
top

# Adjust Erlang VM settings in systemd service
sudo nano /etc/systemd/system/pou_con.service

# Add to [Service] section:
Environment="ERL_CRASH_DUMP=/var/log/pou_con/erl_crash.dump"
Environment="RELEASE_TMP=/tmp/pou_con"

# For low-memory systems (< 512MB), limit VM:
Environment="ERL_AFLAGS=-MBas ageffcbf -MBacul 100 -MBrs 100"

sudo systemctl daemon-reload
sudo systemctl restart pou_con
```

## Backup and Recovery

### Backup

```bash
# On CM4
# Backup database and configuration
sudo tar -czf /home/pi/pou_con_backup_$(date +%Y%m%d).tar.gz \
  /opt/pou_con/data/ \
  /opt/pou_con/.env \
  /etc/systemd/system/pou_con.service

# Copy backup off-site
scp pou_con_backup_*.tar.gz user@backup-server:/backups/
```

### Restore

```bash
# On CM4
sudo systemctl stop pou_con
sudo tar -xzf /home/pi/pou_con_backup_YYYYMMDD.tar.gz -C /
sudo systemctl start pou_con
```

## Network Configuration

### Set Static IP (Recommended for Production)

```bash
# On CM4
sudo nano /etc/dhcpcd.conf
```

Add at the end:
```
interface eth0
static ip_address=192.168.1.100/24
static routers=192.168.1.1
static domain_name_servers=192.168.1.1 8.8.8.8
```

Reboot:
```bash
sudo reboot
```

## Security Hardening

```bash
# On CM4

# 1. Change default password
passwd

# 2. Disable SSH password authentication (use keys only)
sudo nano /etc/ssh/sshd_config
# Set: PasswordAuthentication no
sudo systemctl restart ssh

# 3. Enable firewall
sudo apt install -y ufw
sudo ufw allow 22/tcp  # SSH
sudo ufw allow 4000/tcp  # PouCon web interface
sudo ufw enable

# 4. Set up automatic security updates
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

## Monitoring

### View Application Status

```bash
# Service status
sudo systemctl status pou_con

# Resource usage
sudo journalctl -u pou_con --since "1 hour ago"

# Database size
du -sh /opt/pou_con/data/

# Log file sizes
du -sh /var/log/pou_con/
```

### Set Up Log Rotation

```bash
# On CM4
sudo nano /etc/logrotate.d/pou_con
```

Add:
```
/var/log/pou_con/*.log {
    daily
    rotate 7
    compress
    delaycompress
    notifempty
    create 0644 pi pi
    sharedscripts
    postrotate
        systemctl reload pou_con > /dev/null 2>&1 || true
    endscript
}
```

## Hardware-Specific Notes

### Waveshare Modbus RTU IO 8CH

- Default Modbus address: 1 (check DIP switches)
- Baud rate: 9600, 8N1 (verify settings)
- Connection: RS485 A/B terminals
- Configure in Admin → Devices with correct register mappings

### Cytron RS485 Temperature/Humidity Sensor

- Default Modbus address: Check documentation
- Read registers for temp/humidity values
- Configure polling interval in device settings

### RTC Battery Failure Recovery

If CM4's RTC battery dies and time resets on boot:

```bash
# Access web interface
# Go to Admin → System Settings
# Click "Set System Time" button
# This sets CM4 time from your browser's time

# Or manually via SSH:
sudo date -s "2025-12-11 14:30:00"
```

## Quick Reference

| Task | Command |
|------|---------|
| Start service | `sudo systemctl start pou_con` |
| Stop service | `sudo systemctl stop pou_con` |
| Restart service | `sudo systemctl restart pou_con` |
| View logs | `sudo journalctl -u pou_con -f` |
| Check status | `sudo systemctl status pou_con` |
| Remote console | `/opt/pou_con/bin/pou_con remote` |
| Run migrations | `/opt/pou_con/bin/pou_con eval "PouCon.Release.migrate()"` |
| Web interface | `http://<cm4-ip>:4000` |

## Support

For issues during deployment:
1. Check logs: `sudo journalctl -u pou_con -n 100`
2. Verify environment: `cat /opt/pou_con/.env`
3. Test hardware: Check `/dev/ttyUSB*` devices exist
4. Review documentation: See CLAUDE.md for architecture details

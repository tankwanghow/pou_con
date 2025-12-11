# PouCon Deployment Guide

This guide covers deploying PouCon to Raspberry Pi controllers in poultry houses, including offline deployment scenarios.

## Table of Contents

1. [Deployment Scenarios](#deployment-scenarios)
2. [Initial Build Preparation (With Internet)](#initial-build-preparation-with-internet)
3. [Creating Portable Deployment Package](#creating-portable-deployment-package)
4. [Field Deployment (No Internet)](#field-deployment-no-internet)
5. [Replacing a Pi Controller](#replacing-a-pi-controller)
6. [Post-Deployment Configuration](#post-deployment-configuration)
7. [Touchscreen Kiosk Mode (Optional)](#touchscreen-kiosk-mode-optional)
8. [Backup and Recovery](#backup-and-recovery)
9. [Troubleshooting](#troubleshooting)
10. [Environment Variables Reference](#environment-variables-reference)
11. [Network Configuration (Optional)](#network-configuration-optional)

## Deployment Scenarios

### Scenario A: Master Image Deployment (Recommended for Production)
**Best for: Multiple poultry houses, production deployments**
- Create master SD card image once with PouCon pre-installed
- Flash image to new SD cards (10 minutes each)
- At site: Insert SD card, boot, run setup script (5 minutes)
- **Total time per site: 5 minutes**
- See **[MASTER_IMAGE_DEPLOYMENT.md](MASTER_IMAGE_DEPLOYMENT.md)** for complete guide

### Scenario B: Package Deployment (Testing/Development)
**Best for: Single installations, testing new versions**
- Pre-built deployment package on USB drive
- Fresh or existing Raspberry Pi
- Run deployment script (10 minutes)
- **Total time: 10 minutes**
- See instructions below

### Scenario C: Replacing Failed Controller
**Best for: Emergency replacements**
- Flash master image to new SD card
- Or deploy from package with backup restore
- **Downtime: 5-15 minutes**

## Initial Build Preparation (With Internet)

### Prerequisites

**Build Machine Requirements:**
- Linux/macOS with internet connection
- Elixir 1.14+ and Erlang/OTP 25+
- Git access to repository

**Target Raspberry Pi Requirements:**
- Raspberry Pi 3B+ or 4 (2GB RAM minimum)
- Raspberry Pi OS (64-bit recommended)
- 32GB+ SD card (for reliability and log storage)
- RS485 USB adapter(s) for Modbus RTU
- Network access (during initial setup only)

### Step 1: Build Production Release

On your build machine with internet:

```bash
# Clone repository
git clone <repository-url> pou_con
cd pou_con

# Install dependencies
mix deps.get

# Compile dependencies (this takes time and requires internet)
MIX_ENV=prod mix deps.compile

# Compile application
MIX_ENV=prod mix compile

# Build production release
MIX_ENV=prod mix release

# The release will be in _build/prod/rel/pou_con/
```

### Step 2: Prepare Raspberry Pi Base Image

**Option A: Standard Setup (Requires Internet on Pi)**

1. Flash Raspberry Pi OS to SD card using Raspberry Pi Imager
2. Boot Pi and run initial setup
3. Update system packages:
   ```bash
   sudo apt update && sudo apt upgrade -y
   ```

4. Install required system dependencies:
   ```bash
   sudo apt install -y \
     sqlite3 \
     openssl \
     ca-certificates \
     locales \
     libncurses5
   ```

5. Configure timezone and locale:
   ```bash
   sudo timedatectl set-timezone Asia/Kuala_Lumpur  # Adjust to your timezone
   sudo locale-gen en_US.UTF-8
   ```

6. Install web-based time setting (for RTC battery failure recovery):
   ```bash
   # Copy setup_sudo.sh from repository to /home/pi/
   sudo bash setup_sudo.sh
   ```

**Option B: Pre-configured Image (Recommended for Multiple Deployments)**

After completing Option A on one Pi, create a master image:

```bash
# On build machine with SD card reader
# Backup the configured SD card
sudo dd if=/dev/sdX of=pou_con_base_image.img bs=4M status=progress

# Compress for storage
gzip pou_con_base_image.img
# Result: pou_con_base_image.img.gz (~2-4GB)
```

For subsequent deployments, flash this pre-configured image.

## Creating Portable Deployment Package

### Step 3: Package Release for Offline Deployment

Create a deployment package that includes everything needed:

```bash
# On build machine, after successful release build
cd /path/to/pou_con

# Create deployment directory
mkdir -p deployment_package
cd deployment_package

# Copy release
cp -r ../_build/prod/rel/pou_con ./

# Copy deployment scripts
cat > deploy.sh << 'EOF'
#!/bin/bash
set -e

echo "=== PouCon Deployment Script ==="

# Variables
INSTALL_DIR="/opt/pou_con"
DATA_DIR="/var/lib/pou_con"
SERVICE_USER="pou_con"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (use sudo)"
  exit 1
fi

echo "1. Creating application user..."
if ! id "$SERVICE_USER" &>/dev/null; then
    useradd -r -s /bin/false -d "$DATA_DIR" "$SERVICE_USER"
    echo "   User $SERVICE_USER created"
else
    echo "   User $SERVICE_USER already exists"
fi

echo "2. Creating directories..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$DATA_DIR"
mkdir -p /var/log/pou_con

echo "3. Copying application files..."
cp -r pou_con/* "$INSTALL_DIR/"
chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"
chown -R "$SERVICE_USER:$SERVICE_USER" "$DATA_DIR"
chown -R "$SERVICE_USER:$SERVICE_USER" /var/log/pou_con

echo "4. Installing systemd service..."
cat > /etc/systemd/system/pou_con.service << 'EOSERVICE'
[Unit]
Description=PouCon Industrial Control System
After=network.target

[Service]
Type=simple
User=pou_con
Group=pou_con
WorkingDirectory=/opt/pou_con
Environment="PORT=4000"
Environment="DATABASE_PATH=/var/lib/pou_con/pou_con_prod.db"
Environment="SECRET_KEY_BASE=CHANGE_THIS_SECRET_KEY"
Environment="PHX_HOST=localhost"
Environment="MIX_ENV=prod"
ExecStart=/opt/pou_con/bin/pou_con start
ExecStop=/opt/pou_con/bin/pou_con stop
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=pou_con

# Security hardening
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOSERVICE

echo "5. Generating SECRET_KEY_BASE..."
SECRET_KEY=$(openssl rand -base64 48)
sed -i "s/CHANGE_THIS_SECRET_KEY/$SECRET_KEY/" /etc/systemd/system/pou_con.service

echo "6. Setting up USB serial port permissions..."
usermod -a -G dialout "$SERVICE_USER"

echo "7. Reloading systemd..."
systemctl daemon-reload

echo "8. Running database migrations..."
cd "$INSTALL_DIR"
sudo -u "$SERVICE_USER" DATABASE_PATH="$DATA_DIR/pou_con_prod.db" ./bin/pou_con eval "PouCon.Release.migrate"

echo ""
echo "=== Deployment Complete! ==="
echo ""
echo "Next steps:"
echo "  1. Enable service: sudo systemctl enable pou_con"
echo "  2. Start service:  sudo systemctl start pou_con"
echo "  3. Check status:   sudo systemctl status pou_con"
echo "  4. View logs:      sudo journalctl -u pou_con -f"
echo ""
echo "Access the web interface at http://$(hostname -I | awk '{print $1}'):4000"
echo "Default login: admin / admin (CHANGE IMMEDIATELY)"
EOF

chmod +x deploy.sh

# Copy uninstall script
cat > uninstall.sh << 'EOF'
#!/bin/bash
set -e

echo "=== PouCon Uninstall Script ==="

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (use sudo)"
  exit 1
fi

echo "Stopping and disabling service..."
systemctl stop pou_con || true
systemctl disable pou_con || true

echo "Removing systemd service..."
rm -f /etc/systemd/system/pou_con.service
systemctl daemon-reload

echo "Removing application files..."
rm -rf /opt/pou_con

echo ""
echo "IMPORTANT: Database and logs preserved in:"
echo "  - /var/lib/pou_con/"
echo "  - /var/log/pou_con/"
echo ""
echo "To completely remove including data, run:"
echo "  sudo rm -rf /var/lib/pou_con /var/log/pou_con"
echo "  sudo userdel pou_con"
EOF

chmod +x uninstall.sh

# Copy backup script
cat > backup.sh << 'EOF'
#!/bin/bash

# Backup script for PouCon
BACKUP_DIR="/var/backups/pou_con"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DATA_DIR="/var/lib/pou_con"

mkdir -p "$BACKUP_DIR"

echo "Creating backup: $BACKUP_DIR/pou_con_backup_$TIMESTAMP.tar.gz"
tar -czf "$BACKUP_DIR/pou_con_backup_$TIMESTAMP.tar.gz" \
  -C "$DATA_DIR" \
  pou_con_prod.db

echo "Backup complete: $(du -h "$BACKUP_DIR/pou_con_backup_$TIMESTAMP.tar.gz" | cut -f1)"

# Keep only last 7 backups
ls -t "$BACKUP_DIR"/pou_con_backup_*.tar.gz | tail -n +8 | xargs rm -f 2>/dev/null || true
EOF

chmod +x backup.sh

# Create README
cat > README.txt << 'EOF'
PouCon Deployment Package
=========================

This package contains everything needed to deploy PouCon to a Raspberry Pi
without internet access.

Contents:
  - pou_con/         : Application release
  - deploy.sh        : Deployment script
  - uninstall.sh     : Uninstall script
  - backup.sh        : Backup script
  - README.txt       : This file

Requirements:
  - Raspberry Pi 3B+ or 4 with Raspberry Pi OS
  - System dependencies installed (see DEPLOYMENT_GUIDE.md)
  - RS485 USB adapter(s) connected

Quick Start:
  1. Copy this entire directory to the Raspberry Pi
  2. Run: sudo ./deploy.sh
  3. Follow on-screen instructions

Configuration:
  After deployment, configure via web interface:
  - http://<pi-ip-address>:4000
  - Default login: admin / admin

Support:
  See DEPLOYMENT_GUIDE.md for detailed documentation
EOF

cd ..
echo "Creating deployment archive..."
tar -czf pou_con_deployment_$(date +%Y%m%d).tar.gz deployment_package/
echo ""
echo "Deployment package created: pou_con_deployment_$(date +%Y%m%d).tar.gz"
echo "Size: $(du -h pou_con_deployment_$(date +%Y%m%d).tar.gz | cut -f1)"
```

### Step 4: Transfer to USB Drive

```bash
# Copy deployment package to USB drive
cp pou_con_deployment_*.tar.gz /media/usb_drive/

# Optionally include base image for fresh Pi setups
cp pou_con_base_image.img.gz /media/usb_drive/
```

## Field Deployment (No Internet)

This is the typical deployment process at a poultry house. Takes **5-10 minutes**, no internet required.

### Prerequisites

On the Raspberry Pi:
- Raspberry Pi OS (64-bit) installed and booted
- Basic system packages installed: `sqlite3`, `openssl`, `ca-certificates`, `libncurses5`
- RS485 USB adapters connected

**Note**: If this is a fresh Pi, install dependencies once (with internet at office):
```bash
sudo apt update && sudo apt install -y sqlite3 openssl ca-certificates locales libncurses5
```

### Deployment Steps

**1. Transfer deployment package to Pi**

Insert USB drive (auto-mounts to `/media/pi/<USB_LABEL>`):
```bash
cd ~
cp /media/pi/*/pou_con_deployment_*.tar.gz ./
```

Or via network (if available):
```bash
# From your laptop
scp pou_con_deployment_*.tar.gz pi@<pi-ip>:~/
```

**2. Extract and deploy**

```bash
tar -xzf pou_con_deployment_*.tar.gz
cd deployment_package_*/
sudo ./deploy.sh
```

The script will automatically:
- Create `pou_con` system user
- Install application to `/opt/pou_con`
- Create database directory at `/var/lib/pou_con`
- Set up USB serial port permissions
- Configure web-based time management
- Install systemd service
- Generate secure SECRET_KEY_BASE
- Run database migrations
- Verify all permissions

**3. Start the service**

```bash
sudo systemctl enable pou_con
sudo systemctl start pou_con
```

**4. Verify it's running**

```bash
sudo systemctl status pou_con
```

Expected output:
```
● pou_con.service - PouCon Industrial Control System
   Loaded: loaded (/etc/systemd/system/pou_con.service; enabled)
   Active: active (running) since ...
```

**5. Find Pi's IP address**

```bash
hostname -I
```

Example output: `192.168.1.100`

**6. Access web interface**

Open browser on any computer on the network:
```
http://192.168.1.100:4000
```

Login with default credentials:
- Username: `admin`
- Password: `admin`

**IMMEDIATELY CHANGE THE PASSWORD** after first login.

### That's It!

The deployment is complete. The system is now running with:
- Web interface on port 4000
- Database at `/var/lib/pou_con/pou_con_prod.db`
- Automatic time management enabled
- All permissions correctly configured
- Service set to auto-start on boot

Proceed to [Post-Deployment Configuration](#post-deployment-configuration) to set up your equipment.

### Quick Troubleshooting

**Service not running?**
```bash
sudo journalctl -u pou_con -n 50
```

**Can't access web interface?**
```bash
# Test locally on Pi
curl http://localhost:4000

# Check firewall (if enabled)
sudo ufw allow 4000/tcp
```

**USB devices not detected?**
```bash
ls -l /dev/ttyUSB*
```

For detailed troubleshooting, see [Troubleshooting](#troubleshooting) section.

## Post-Deployment Configuration

### Step 7: Web Interface Setup

1. **Access Web Interface:**
   - From local network: `http://<pi-ip-address>:4000`
   - To find Pi IP: `hostname -I`

2. **Initial Login:**
   - Username: `admin`
   - Password: `admin`
   - **IMMEDIATELY CHANGE PASSWORD**

3. **Configure Hardware (Admin Menu):**

   a. **Add Ports:**
      - Navigate to Admin → Ports
      - Add RS485 port: `/dev/ttyUSB0`, baud 9600, parity none
      - If using Modbus TCP, add IP: `192.168.1.100`, port 502

   b. **Add Devices:**
      - Navigate to Admin → Devices
      - Add Waveshare Modbus RTU IO 8CH (digital outputs/inputs)
      - Add RS485 Temperature/Humidity sensors
      - Configure slave addresses and register mappings

   c. **Add Equipment:**
      - Navigate to Admin → Equipment
      - Define fans (fan_1, fan_2, ...)
      - Define pumps (pump_1, pump_2, ...)
      - Define lights, feeders, etc.
      - Link equipment to device tree (JSON mapping)

4. **Configure Automation:**
   - Navigate to Automation → Environment
   - Set temperature/humidity control parameters
   - Navigate to Automation → Lighting
   - Configure light schedules
   - Navigate to Automation → Feeding
   - Configure feeding schedules

5. **Set System Time (if needed):**
   - Navigate to Admin → System Settings
   - Set date/time if RTC battery failed
   - Or via command line: `sudo timedatectl set-time "2025-12-10 14:30:00"`

### Step 8: Test Equipment

1. **Manual Control Test:**
   - Go to Dashboard
   - Switch equipment to Manual mode
   - Turn ON/OFF each piece of equipment
   - Verify actual status matches commanded status

2. **Sensor Verification:**
   - Check temperature/humidity readings are valid
   - Verify limit switches respond correctly
   - Check running status inputs

3. **Automation Test:**
   - Switch equipment to Auto mode
   - Verify schedulers trigger correctly
   - Test environment auto-control
   - Verify interlocks prevent unsafe operations

## Replacing a Pi Controller

### Scenario: Hardware Failure or Upgrade

**Option A: Quick Swap with Backup SD Card**

1. **Preparation (at office):**
   - Keep spare SD cards with base image pre-flashed
   - Keep deployment package on USB drives
   - Keep latest configuration backups

2. **On-site replacement:**
   ```bash
   # 1. Stop old Pi (if accessible)
   ssh pi@<old-pi-ip>
   sudo /var/backups/pou_con/backup.sh  # Quick backup if possible
   sudo poweroff

   # 2. Swap SD card or entire Pi

   # 3. Boot new Pi

   # 4. Deploy application (from USB)
   cd /media/pi/*/deployment_package
   sudo ./deploy.sh
   sudo systemctl enable pou_con
   sudo systemctl start pou_con

   # 5. Restore configuration (if backup available)
   # Copy backup from USB
   cd /tmp
   tar -xzf /media/pi/*/pou_con_backup_*.tar.gz
   sudo systemctl stop pou_con
   sudo cp pou_con_prod.db /var/lib/pou_con/
   sudo chown pou_con:pou_con /var/lib/pou_con/pou_con_prod.db
   sudo systemctl start pou_con
   ```

3. **Downtime:** 5-15 minutes depending on configuration restore

**Option B: Network Configuration Restore**

If you have network access to both old and new Pi:

```bash
# On old Pi (backup)
ssh pi@<old-pi-ip>
sudo systemctl stop pou_con
cd /var/backups/pou_con
sudo ./backup.sh
# Copy backup file to USB or transfer via scp

# On new Pi (restore)
# Deploy application first (see Step 5)
# Then restore database:
sudo systemctl stop pou_con
sudo tar -xzf pou_con_backup_*.tar.gz -C /var/lib/pou_con/
sudo chown -R pou_con:pou_con /var/lib/pou_con
sudo systemctl start pou_con
```

## Touchscreen Kiosk Mode (Optional)

If you want a touchscreen display attached to the Raspberry Pi showing the PouCon interface 24/7 in fullscreen kiosk mode, see the comprehensive **[TOUCHSCREEN_KIOSK_SETUP.md](TOUCHSCREEN_KIOSK_SETUP.md)** guide.

### Quick Overview

**Use Cases:**
- Local touchscreen control panel in poultry house
- Backup interface if network fails
- Operator-friendly on-site monitoring

**Hardware Options:**
1. **Standard Setup:** Raspberry Pi + external touchscreen (HDMI/DSI)
2. **Industrial Panel PC:** All-in-one with built-in CM4 and rugged touchscreen

### Setup Process Summary

**For Standard Touchscreens:**
```bash
# After deploying PouCon, run kiosk setup
cd deployment_package_*/
./setup_kiosk.sh
sudo reboot

# Pi will boot to fullscreen PouCon interface
```

**For Industrial Touch Panel PCs:**
1. Use manufacturer's OS image (includes touch drivers)
2. Deploy PouCon as normal
3. Run kiosk setup script
4. Configure panel-specific settings (brightness, orientation)

### Industrial Panel Recommendations

**Recommended for poultry houses:**
- **Waveshare CM4-Panel-10.1-B** ($200-250) - Good balance of features and price
- **Seeed Studio reTerminal DM** ($250-300) - Excellent software support
- **Advantech TPC Series** ($500-700) - Enterprise-grade, best for large operations

**Minimum specs for poultry environment:**
- 10" screen (glove-friendly)
- IP65 rating (dust/moisture protection)
- Operating temp: -20°C to +60°C
- Capacitive touch (works with light gloves)
- 24V DC power (industrial standard)

### Important Notes

**Touchscreen Drivers:**
- Standard Pi touchscreens: Auto-detected by Raspberry Pi OS
- Industrial panels: Use vendor OS image (includes drivers pre-installed)
- If using custom panels: Check vendor documentation for device tree overlays

**Kiosk Features:**
- Fullscreen Chromium browser (no UI elements)
- Touch input for all controls
- Auto-start on boot
- Screen blanking disabled
- Mouse cursor hidden
- Crash recovery (auto-restart)

**Typical Setup Time:**
- Standard touchscreen: +15 minutes
- Industrial panel with vendor image: +20 minutes
- Industrial panel with manual drivers: +2-4 hours

For detailed setup instructions, driver installation, troubleshooting, and vendor-specific configurations, see **[TOUCHSCREEN_KIOSK_SETUP.md](TOUCHSCREEN_KIOSK_SETUP.md)**.

## Backup and Recovery

### Automated Backup Setup

```bash
# Create backup script (already included in deployment package)
sudo cp /opt/pou_con_deployment/backup.sh /usr/local/bin/pou_con_backup
sudo chmod +x /usr/local/bin/pou_con_backup

# Schedule daily backups via cron
sudo crontab -e
# Add line:
0 2 * * * /usr/local/bin/pou_con_backup
```

### Manual Backup

```bash
# Create instant backup
sudo /usr/local/bin/pou_con_backup

# Copy to USB drive
sudo cp /var/backups/pou_con/pou_con_backup_*.tar.gz /media/pi/USB/
```

### Restore from Backup

```bash
# Stop service
sudo systemctl stop pou_con

# Restore database
cd /tmp
tar -xzf /path/to/pou_con_backup_YYYYMMDD_HHMMSS.tar.gz
sudo cp pou_con_prod.db /var/lib/pou_con/
sudo chown pou_con:pou_con /var/lib/pou_con/pou_con_prod.db

# Start service
sudo systemctl start pou_con
```

## Troubleshooting

### Service Won't Start

```bash
# Check logs
sudo journalctl -u pou_con -n 50

# Common issues:
# 1. Database migration failed
sudo -u pou_con DATABASE_PATH=/var/lib/pou_con/pou_con_prod.db \
  /opt/pou_con/bin/pou_con eval "PouCon.Release.migrate"

# 2. Permission issues
sudo chown -R pou_con:pou_con /opt/pou_con /var/lib/pou_con

# 3. Port already in use
sudo netstat -tlnp | grep 4000
```

### Cannot Access Web Interface

```bash
# Check service status
systemctl status pou_con

# Check firewall (if enabled)
sudo ufw allow 4000/tcp

# Test local access
curl http://localhost:4000

# Find Pi IP address
hostname -I
```

### Modbus Communication Errors

```bash
# Check USB devices
ls -l /dev/ttyUSB*

# Check permissions
sudo usermod -a -G dialout pou_con
sudo systemctl restart pou_con

# Test Modbus connection manually
# Install modpoll for testing
sudo apt install modpoll
modpoll -b 9600 -p none -m rtu -a 1 -r 0 -c 8 /dev/ttyUSB0
```

### Database Corruption

```bash
# Stop service
sudo systemctl stop pou_con

# Check database integrity
sqlite3 /var/lib/pou_con/pou_con_prod.db "PRAGMA integrity_check;"

# Restore from backup if corrupted
cd /var/backups/pou_con
tar -xzf pou_con_backup_LATEST.tar.gz
sudo cp pou_con_prod.db /var/lib/pou_con/
sudo chown pou_con:pou_con /var/lib/pou_con/pou_con_prod.db

# Restart service
sudo systemctl start pou_con
```

### Disk Space Issues

```bash
# Check disk usage
df -h

# Clean old logs (if journal is large)
sudo journalctl --vacuum-time=7d

# Database cleanup runs automatically at 3 AM daily
# Manual cleanup:
sudo -u pou_con DATABASE_PATH=/var/lib/pou_con/pou_con_prod.db \
  /opt/pou_con/bin/pou_con eval "PouCon.Logging.CleanupTask.perform()"
```

## Environment Variables Reference

The PouCon application is configured via environment variables set in the systemd service file. These are automatically configured during deployment, but you may need to customize them for specific scenarios.

### Configuration File Location

Environment variables are stored in: `/etc/systemd/system/pou_con.service`

### Available Environment Variables

#### Required Variables

**`DATABASE_PATH`**
- **Purpose**: Path to SQLite database file
- **Default**: `/var/lib/pou_con/pou_con_prod.db` (set by deploy.sh)
- **When to change**:
  - Using external storage (USB drive, network mount)
  - Multiple PouCon instances on same Pi
- **Example**: `DATABASE_PATH=/mnt/usb/pou_con.db`
- **IMPORTANT**: The pou_con user MUST have read/write permissions to both the database file and its parent directory. SQLite requires write access to the directory for lock files.

**`SECRET_KEY_BASE`**
- **Purpose**: Cryptographic key for signing cookies and sessions
- **Default**: Auto-generated during deployment (64-character random string)
- **When to change**:
  - NEVER change after deployment (invalidates all user sessions)
  - Only regenerate if security compromised
- **Generate new**: `openssl rand -base64 48`

#### Optional Variables (with defaults)

**`PORT`**
- **Purpose**: HTTP server listening port
- **Default**: `4000`
- **When to change**:
  - Port conflict with other services
  - Running behind reverse proxy
  - Multiple PouCon instances
- **Example**: `PORT=8080`

**`PHX_HOST`**
- **Purpose**: Hostname for URL generation (used in links, redirects)
- **Default**: `localhost`
- **When to change**:
  - Accessing from remote computers (use Pi's IP or hostname)
  - Using custom domain name
- **Example**: `PHX_HOST=192.168.1.100` or `PHX_HOST=poultry-house-1.local`

**`MIX_ENV`**
- **Purpose**: Application environment (controls logging, error reporting)
- **Default**: `prod`
- **Options**: `prod`, `dev`, `test`
- **When to change**: RARELY. Only for debugging production issues.

**`POOL_SIZE`**
- **Purpose**: Database connection pool size
- **Default**: `5` (if not set)
- **When to change**:
  - SQLite only supports 1 writer, so keep at 1-5
  - Larger values don't improve performance
- **Example**: `POOL_SIZE=1` (recommended for SQLite)

#### Advanced Variables (optional)

**`PHX_SERVER`**
- **Purpose**: Enable HTTP server (used by `mix release`)
- **Default**: Not needed (deploy.sh uses `bin/pou_con start` which auto-starts server)
- **When to use**: Only if manually running `bin/pou_con` without `start` command

**`DNS_CLUSTER_QUERY`**
- **Purpose**: Cluster discovery for distributed deployments
- **Default**: Not set (single-node deployment)
- **When to use**: Multi-node clusters (not applicable for typical poultry farm setup)

### How to View Current Configuration

```bash
# View all environment variables
sudo systemctl cat pou_con | grep Environment

# Or view entire service file
sudo cat /etc/systemd/system/pou_con.service
```

### How to Change Environment Variables

**Step 1: Stop the service**
```bash
sudo systemctl stop pou_con
```

**Step 2: Edit the service file**
```bash
sudo nano /etc/systemd/system/pou_con.service
```

**Step 3: Modify the Environment line(s)**
```ini
# Example: Change port to 8080
Environment="PORT=8080"

# Example: Use custom database location
Environment="DATABASE_PATH=/mnt/usb/pou_con_prod.db"

# Example: Set hostname to Pi IP
Environment="PHX_HOST=192.168.1.100"
```

**Step 4: Reload systemd configuration**
```bash
sudo systemctl daemon-reload
```

**Step 5: Start the service**
```bash
sudo systemctl start pou_con
```

**Step 6: Verify changes**
```bash
# Check service status
sudo systemctl status pou_con

# Check logs for startup issues
sudo journalctl -u pou_con -n 50
```

### Common Scenarios

#### Scenario 1: Change Web Interface Port

If port 4000 conflicts with another service:

```bash
sudo systemctl stop pou_con
sudo nano /etc/systemd/system/pou_con.service
# Change: Environment="PORT=8080"
sudo systemctl daemon-reload
sudo systemctl start pou_con
# Access at http://<pi-ip>:8080
```

#### Scenario 2: Access from Remote Computers

If accessing from network computers (not localhost):

```bash
sudo systemctl stop pou_con
sudo nano /etc/systemd/system/pou_con.service
# Change: Environment="PHX_HOST=192.168.1.100"  # Use Pi's actual IP
sudo systemctl daemon-reload
sudo systemctl start pou_con
```

#### Scenario 3: Move Database to USB Drive

If SD card space is limited:

```bash
# 1. Stop service
sudo systemctl stop pou_con

# 2. Create USB directory and copy database
sudo mkdir -p /mnt/usb/pou_con
sudo cp /var/lib/pou_con/pou_con_prod.db /mnt/usb/pou_con/

# 3. Set correct ownership and permissions
sudo chown -R pou_con:pou_con /mnt/usb/pou_con
sudo chmod 755 /mnt/usb/pou_con
sudo chmod 644 /mnt/usb/pou_con/pou_con_prod.db

# 4. Update service file
sudo nano /etc/systemd/system/pou_con.service
# Change: Environment="DATABASE_PATH=/mnt/usb/pou_con/pou_con_prod.db"

# 5. Reload and restart
sudo systemctl daemon-reload
sudo systemctl start pou_con

# 6. Verify database location and permissions
ls -la /mnt/usb/pou_con/
sqlite3 /mnt/usb/pou_con/pou_con_prod.db "SELECT COUNT(*) FROM equipment;"

# 7. Check service is running correctly
sudo systemctl status pou_con
sudo journalctl -u pou_con -n 20
```

#### Scenario 4: Multiple PouCon Instances (Advanced)

Running multiple houses on one Pi (requires separate databases and ports):

```bash
# House 1: Use default config (port 4000, /var/lib/pou_con/)
# House 2: Copy service file and customize
sudo cp /etc/systemd/system/pou_con.service /etc/systemd/system/pou_con_house2.service

# Edit house2 service
sudo nano /etc/systemd/system/pou_con_house2.service
# Change:
#   Environment="PORT=4001"
#   Environment="DATABASE_PATH=/var/lib/pou_con_house2/pou_con_prod.db"
#   WorkingDirectory=/opt/pou_con_house2

sudo systemctl daemon-reload
sudo systemctl enable pou_con_house2
sudo systemctl start pou_con_house2
```

### Important Notes

- **SECRET_KEY_BASE**: Never change after deployment unless absolutely necessary. Changing it invalidates all user sessions and cookies.
- **DATABASE_PATH**: Always ensure the pou_con user has read/write permissions to the database file and directory.
  - Directory must be owned by `pou_con:pou_con` and have at least `755` permissions (rwxr-xr-x)
  - Database file must be owned by `pou_con:pou_con` and have at least `644` permissions (rw-r--r--)
  - SQLite requires write access to the directory for temporary lock files (`.db-shm`, `.db-wal`)
- **PORT**: After changing, update firewall rules if applicable: `sudo ufw allow <new-port>/tcp`
- **PHX_HOST**: Should match how users access the system (IP address or hostname).

### Troubleshooting Environment Variable Issues

**Service won't start after changes:**
```bash
# Check for syntax errors
sudo systemctl status pou_con

# View detailed error logs
sudo journalctl -u pou_con -n 50 --no-pager
```

**Common errors:**
- `environment variable DATABASE_PATH is missing` - Variable not set or misspelled
- `environment variable SECRET_KEY_BASE is missing` - Variable not set or empty
- `Address already in use` - PORT is used by another service
- `Permission denied` (database) - Database file or directory permissions incorrect
  ```bash
  # Fix database permissions
  sudo chown pou_con:pou_con /path/to/database/directory
  sudo chown pou_con:pou_con /path/to/database/pou_con_prod.db
  sudo chmod 755 /path/to/database/directory
  sudo chmod 644 /path/to/database/pou_con_prod.db
  ```
- `unable to open database file` - Database path incorrect or directory doesn't exist

**Reset to default configuration:**
```bash
# Redeploy (preserves database)
cd ~/deployment_package_*/
sudo ./deploy.sh
```

## Network Configuration (Optional)

### Static IP Setup

For reliable access, configure static IP:

```bash
# Edit dhcpcd configuration
sudo nano /etc/dhcpcd.conf

# Add at the end:
interface eth0
static ip_address=192.168.1.100/24
static routers=192.168.1.1
static domain_name_servers=192.168.1.1 8.8.8.8

# Restart networking
sudo systemctl restart dhcpcd
```

### WiFi Configuration (if needed)

```bash
# Edit wpa_supplicant
sudo nano /etc/wpa_supplicant/wpa_supplicant.conf

# Add network:
network={
    ssid="YourNetworkName"
    psk="YourPassword"
}

# Restart
sudo systemctl restart wpa_supplicant
```

## Monitoring and Maintenance

### Regular Maintenance Tasks

**Daily:**
- Check dashboard for equipment errors
- Verify automation is running correctly

**Weekly:**
- Review event logs for anomalies
- Check system resources: `htop` or `free -h`
- Verify backups exist: `ls -lh /var/backups/pou_con/`

**Monthly:**
- Review and archive old logs
- Check SD card health: `sudo smartctl -a /dev/mmcblk0` (if supported)
- Update deployment package with any configuration changes

**Quarterly:**
- Test disaster recovery procedure
- Review and update documentation

### Remote Access Setup (Optional)

For remote monitoring and support:

```bash
# Install Tailscale for secure remote access
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# Access Pi remotely via Tailscale IP
# No port forwarding or firewall changes needed
```

## Deployment Checklist

### Pre-Deployment (Office)

- [ ] Build production release
- [ ] Create deployment package
- [ ] Prepare base SD card image
- [ ] Copy deployment package to USB drive
- [ ] Prepare backup USB drive
- [ ] Print this guide

### On-Site Deployment

- [ ] Flash SD card (if new Pi)
- [ ] Connect RS485 adapters
- [ ] Boot Pi and verify USB devices detected
- [ ] Deploy application from USB
- [ ] Enable and start service
- [ ] Verify web interface accessible
- [ ] Change admin password
- [ ] Configure ports and devices
- [ ] Configure equipment and device trees
- [ ] Test manual control of all equipment
- [ ] Configure automation (schedules, environment)
- [ ] Test automation triggers
- [ ] Verify interlocks
- [ ] Create initial backup
- [ ] Document IP address and location
- [ ] Label Pi with site name

### Post-Deployment

- [ ] Monitor for 24 hours
- [ ] Review logs for errors
- [ ] Train operators on basic troubleshooting
- [ ] Schedule first maintenance check
- [ ] Update deployment inventory

## Appendix: Quick Reference Commands

```bash
# Service management
sudo systemctl start pou_con
sudo systemctl stop pou_con
sudo systemctl restart pou_con
sudo systemctl status pou_con

# View logs
sudo journalctl -u pou_con -f          # Follow logs
sudo journalctl -u pou_con -n 100      # Last 100 lines
sudo journalctl -u pou_con --since today

# Backup
sudo /usr/local/bin/pou_con_backup

# Database access
sqlite3 /var/lib/pou_con/pou_con_prod.db

# Check disk space
df -h

# Check USB devices
ls -l /dev/ttyUSB*

# Find IP address
hostname -I

# Reboot Pi
sudo reboot

# Safe shutdown
sudo shutdown -h now
```

## Support and Documentation

- Main documentation: `CLAUDE.md`
- Logging integration: `LOGGING_INTEGRATION_GUIDE.md`
- Hardware recommendations: `brain_recommendation.md`
- Hardware requirements: `HARDWARE_REQUIREMENTS.md`

For issues or questions, refer to project repository documentation.

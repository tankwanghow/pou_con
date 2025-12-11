# Master Image Deployment Guide

This guide shows how to create a pre-configured master SD card image with PouCon pre-installed, then deploy to poultry houses by simply flashing SD cards and running a minimal setup script.

**Deployment time per site: 5 minutes** (just flash SD card, insert, boot, run setup)

## Overview

### The Strategy

1. **Build once**: Create a "golden master" SD card with everything pre-installed
2. **Image it**: Create an image file from the master SD card
3. **Replicate**: Flash the image to new SD cards for each poultry house
4. **Customize**: Run a simple setup script to configure site-specific settings

### Benefits

- **Fastest deployment**: No compilation, no package extraction, no system setup
- **Consistent**: Every Pi starts with identical, tested configuration
- **Offline-ready**: No internet required at any deployment site
- **Foolproof**: Minimal commands to run on-site
- **Easy recovery**: Keep master image for quick replacements

---

## Phase 1: Create Master SD Card (One-Time Setup)

### Step 1: Prepare Fresh Raspberry Pi

**Install Raspberry Pi OS:**

1. Download Raspberry Pi OS (64-bit) from https://www.raspberrypi.com/software/
2. Flash to SD card using Raspberry Pi Imager
3. Boot Pi and complete initial setup (locale, timezone, user)

**Install system dependencies:**

```bash
sudo apt update
sudo apt upgrade -y
sudo apt install -y sqlite3 openssl ca-certificates locales libncurses5

# Set timezone
sudo timedatectl set-timezone Asia/Kuala_Lumpur

# Generate locale
sudo locale-gen en_US.UTF-8
```

### Step 2: Deploy PouCon Application

```bash
# Copy deployment package to Pi
scp pou_con_deployment_*.tar.gz pi@<pi-ip>:~/

# SSH to Pi
ssh pi@<pi-ip>

# Extract and deploy
cd ~
tar -xzf pou_con_deployment_*.tar.gz
cd deployment_package_*/
sudo ./deploy.sh

# Enable service (but don't start yet - we'll configure per-site)
sudo systemctl enable pou_con

# Don't start service yet
```

### Step 3: Create Setup Script for Per-Site Configuration

Create a script that will be run at each poultry house to configure site-specific settings:

```bash
sudo nano /usr/local/bin/poucon-setup
```

Add this content:

```bash
#!/bin/bash
# PouCon Site Setup Script
# Run this at each poultry house to configure site-specific settings

set -e

echo "======================================="
echo "  PouCon Site Configuration Setup"
echo "======================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run with sudo: sudo poucon-setup"
  exit 1
fi

# Get site information
echo "Enter site information:"
echo ""
read -p "Site/House Name (e.g., House-A, Farm-1): " SITE_NAME
read -p "Hostname (e.g., poucon-house-a): " HOSTNAME

# Set hostname
echo ""
echo "Setting hostname to: $HOSTNAME"
hostnamectl set-hostname "$HOSTNAME"

# Update /etc/hosts
sed -i "s/127.0.1.1.*/127.0.1.1\t$HOSTNAME/" /etc/hosts

# Configure static IP (optional)
echo ""
read -p "Configure static IP? (y/n): " CONFIGURE_IP
if [ "$CONFIGURE_IP" = "y" ]; then
    read -p "IP Address (e.g., 192.168.1.100): " IP_ADDRESS
    read -p "Gateway (e.g., 192.168.1.1): " GATEWAY
    read -p "DNS Server (e.g., 192.168.1.1): " DNS_SERVER

    echo ""
    echo "Configuring static IP: $IP_ADDRESS"

    # Backup dhcpcd.conf
    cp /etc/dhcpcd.conf /etc/dhcpcd.conf.backup

    # Add static IP configuration
    cat >> /etc/dhcpcd.conf << EOF

# Static IP configuration for $SITE_NAME
interface eth0
static ip_address=$IP_ADDRESS/24
static routers=$GATEWAY
static domain_name_servers=$DNS_SERVER
EOF

    echo "Static IP configured. Will take effect after reboot."
fi

# Reset database (start fresh for each site)
echo ""
read -p "Reset database to start fresh? (y/n): " RESET_DB
if [ "$RESET_DB" = "y" ]; then
    echo "Stopping PouCon service..."
    systemctl stop pou_con || true

    echo "Removing old database..."
    rm -f /var/lib/pou_con/pou_con_prod.db
    rm -f /var/lib/pou_con/pou_con_prod.db-shm
    rm -f /var/lib/pou_con/pou_con_prod.db-wal

    echo "Running migrations to create fresh database..."
    cd /opt/pou_con
    sudo -u pou_con DATABASE_PATH=/var/lib/pou_con/pou_con_prod.db \
      ./bin/pou_con eval "PouCon.Release.migrate"

    echo "Database reset complete."
fi

# Start service
echo ""
echo "Starting PouCon service..."
systemctl start pou_con

# Wait for service to start
sleep 3

# Check service status
if systemctl is-active --quiet pou_con; then
    echo ""
    echo "======================================="
    echo "  Setup Complete!"
    echo "======================================="
    echo ""
    echo "Site Name: $SITE_NAME"
    echo "Hostname:  $HOSTNAME"

    if [ "$CONFIGURE_IP" = "y" ]; then
        echo "IP Address: $IP_ADDRESS (after reboot)"
    else
        echo "IP Address: $(hostname -I | awk '{print $1}')"
    fi

    echo ""
    echo "Access PouCon at: http://$(hostname -I | awk '{print $1}'):4000"
    echo "Default login: admin / admin"
    echo ""
    echo "IMPORTANT: Change admin password immediately!"
    echo ""

    if [ "$CONFIGURE_IP" = "y" ]; then
        read -p "Reboot now to apply network settings? (y/n): " REBOOT_NOW
        if [ "$REBOOT_NOW" = "y" ]; then
            echo "Rebooting in 3 seconds..."
            sleep 3
            reboot
        else
            echo "Remember to reboot for network settings to take effect."
        fi
    fi
else
    echo ""
    echo "ERROR: PouCon service failed to start!"
    echo "Check logs: sudo journalctl -u pou_con -n 50"
    exit 1
fi
EOF

chmod +x /usr/local/bin/poucon-setup
```

### Step 4: Clean Up Master SD Card

Before creating the image, clean up temporary files and history:

```bash
# Clean package cache
sudo apt clean

# Remove deployment package
cd ~
rm -f pou_con_deployment_*.tar.gz
rm -rf deployment_package_*/

# Clear bash history
history -c
cat /dev/null > ~/.bash_history

# Shutdown Pi
sudo shutdown -h now
```

### Step 5: Create Master Image

Remove SD card from Pi and create image on your development machine:

**On Linux:**

```bash
# Find SD card device
lsblk

# Create image (replace /dev/sdX with your SD card device)
sudo dd if=/dev/sdX of=poucon_master_image.img bs=4M status=progress

# Compress image (this will take a while - reduces ~32GB to ~2-4GB)
gzip -9 poucon_master_image.img

# Result: poucon_master_image.img.gz (~2-4GB)
```

**On Windows:**

Use Win32 Disk Imager:
1. Download Win32 Disk Imager
2. Select SD card drive
3. Choose output file: `poucon_master_image.img`
4. Click "Read" to create image
5. Use 7-Zip to compress: Right-click → 7-Zip → Add to archive

**On macOS:**

```bash
# Find disk
diskutil list

# Unmount disk (replace diskN)
diskutil unmountDisk /dev/diskN

# Create image
sudo dd if=/dev/rdiskN of=poucon_master_image.img bs=4m

# Compress
gzip -9 poucon_master_image.img
```

**Store master image safely:**
- Keep on external drive
- Keep backup copy
- Document the version/date

---

## Phase 2: Deploy to Poultry Houses

### For Each New Poultry House:

**1. Flash SD Card**

Insert fresh SD card and flash the master image:

**On Linux:**
```bash
# Decompress and flash in one command
gunzip -c poucon_master_image.img.gz | sudo dd of=/dev/sdX bs=4M status=progress
```

**On Windows:**
- Use Balena Etcher or Win32 Disk Imager
- Select `poucon_master_image.img.gz` file
- Select SD card drive
- Click "Flash"

**On macOS:**
```bash
gunzip -c poucon_master_image.img.gz | sudo dd of=/dev/rdiskN bs=4m
```

**2. Deploy at Site**

Insert SD card into Raspberry Pi at poultry house and boot.

**3. Run Setup Script**

SSH to Pi or connect keyboard/monitor:

```bash
sudo poucon-setup
```

The script will ask:
- Site name (e.g., "House-A", "Farm-1-Building-B")
- Hostname (e.g., "poucon-house-a")
- Whether to configure static IP
- Whether to reset database (usually "yes" for new sites)

**4. Access Web Interface**

After setup completes:
```
http://<pi-ip>:4000
```

Login: `admin` / `admin`

**IMMEDIATELY CHANGE PASSWORD**

**5. Configure Equipment**

Via web interface:
- Admin → Ports (add RS485 ports)
- Admin → Devices (add Modbus devices)
- Admin → Equipment (configure fans, pumps, etc.)
- Automation → Configure schedules

Done!

---

## Phase 3: Updating the Master Image

When you release a new version of PouCon:

### Option A: Update Existing Master

1. Boot the master SD card
2. Deploy new version:
   ```bash
   cd ~
   scp pou_con_deployment_*.tar.gz pi@<pi-ip>:~/
   tar -xzf pou_con_deployment_*.tar.gz
   cd deployment_package_*/
   sudo ./deploy.sh
   sudo systemctl restart pou_con
   ```
3. Test thoroughly
4. Clean up and create new image (repeat Phase 1, Steps 4-5)

### Option B: Start Fresh

1. Flash fresh Raspberry Pi OS
2. Follow Phase 1 completely
3. Create new master image

**Version your images:**
- `poucon_master_v1.0_20251210.img.gz`
- `poucon_master_v1.1_20251215.img.gz`
- Keep previous versions for rollback

---

## Deployment Time Comparison

| Method | Time | Complexity | Use Case |
|--------|------|------------|----------|
| **Master Image** | **5 min** | **Very Low** | **Production (recommended)** |
| Package Deployment | 10 min | Low | Testing/development |
| Manual Setup | 30 min | Medium | One-off installations |

---

## Quick Reference

### Create Master Image
```bash
# On development machine
sudo dd if=/dev/sdX of=poucon_master_image.img bs=4M status=progress
gzip -9 poucon_master_image.img
```

### Flash to New SD Card
```bash
gunzip -c poucon_master_image.img.gz | sudo dd of=/dev/sdX bs=4M status=progress
```

### At Poultry House
```bash
# Boot Pi, then run:
sudo poucon-setup
```

### Access Web Interface
```
http://<pi-ip>:4000
admin / admin
```

---

## Troubleshooting

### Image Creation

**"No space left on device" during image creation:**
- Use larger storage device
- Create image on external drive

**Image too large:**
- Use `pishrink` tool to shrink image before compression
  ```bash
  wget https://raw.githubusercontent.com/Drewsif/PiShrink/master/pishrink.sh
  chmod +x pishrink.sh
  sudo ./pishrink.sh poucon_master_image.img
  gzip -9 poucon_master_image.img
  ```

### Flashing

**SD card not detected:**
- Try different card reader
- Check SD card is not write-protected

**Flash verification fails:**
- Use higher-quality SD card (SanDisk, Samsung)
- Try lower write speed

### Setup Script

**poucon-setup command not found:**
```bash
# Check if script exists
ls -la /usr/local/bin/poucon-setup

# If missing, recreate it (see Phase 1, Step 3)
```

**Service fails to start:**
```bash
sudo journalctl -u pou_con -n 50
```

---

## Best Practices

1. **Test master image thoroughly** before mass deployment
2. **Version your images** with dates
3. **Keep backup images** of previous versions
4. **Document hardware changes** (if image created on Pi 4, note compatibility)
5. **Use quality SD cards** (SanDisk Extreme, Samsung PRO Endurance)
6. **Create site inventory** tracking which image version deployed where
7. **Schedule image updates** (e.g., quarterly)

---

## Multi-Site Deployment Example

**Scenario**: Deploy to 10 poultry houses

**Preparation (one time):**
- Create master image: 2 hours
- Purchase 10 SD cards: $200

**Deployment (per site):**
1. Flash SD card: 10 minutes (can do in parallel)
2. At site: Insert SD card, boot: 2 minutes
3. Run `sudo poucon-setup`: 3 minutes
4. Configure equipment via web: 10 minutes

**Total per site: 15 minutes**
**Total for 10 sites: 2.5 hours** (including travel between sites)

Compare to package deployment: 10 sites × 30 min = 5 hours

**Time saved: 2.5 hours**

---

## Advanced: Automated Setup

For completely hands-off deployment, you can pre-configure site-specific settings:

Create `/boot/poucon-site-config.txt` on SD card before deploying:

```ini
SITE_NAME=House-A
HOSTNAME=poucon-house-a
IP_ADDRESS=192.168.1.100
GATEWAY=192.168.1.1
DNS_SERVER=192.168.1.1
RESET_DATABASE=true
```

Modify `poucon-setup` script to read this file automatically on first boot.

This enables: **flash SD card → insert → power on → done** (zero interaction required).

---

## Summary

**Master Image Deployment = Fastest & Most Reliable**

✅ 5-minute site deployment
✅ Consistent configuration
✅ No compilation required
✅ Perfect for multiple sites
✅ Easy disaster recovery

**Recommended for:**
- Production deployments
- Multiple poultry houses
- Field technicians with minimal training
- Quick replacement of failed controllers

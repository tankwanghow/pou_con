# Quick Start: Offline Deployment

This guide gets you from zero to deployed in under 30 minutes (after one-time setup).

## TL;DR

**On your development machine (one-time setup):**
```bash
./scripts/setup_docker_arm.sh
```

**Every time you want to deploy (10-20 minutes):**
```bash
./scripts/build_and_package.sh
cp pou_con_deployment_*.tar.gz /media/usb_drive/
```

**At poultry house (5-10 minutes, no internet):**
```bash
# Extract and deploy
tar -xzf pou_con_deployment_*.tar.gz
cd deployment_package_*/
sudo ./deploy.sh

# Start service
sudo systemctl enable pou_con
sudo systemctl start pou_con

# Get Pi's IP address
hostname -I
```

Access at `http://<pi-ip>:4000`, login `admin`/`admin`, change password immediately.

---

## Detailed Walkthrough

### Phase 1: One-Time Setup (Your Development Machine)

**Current machine:** x86_64 Linux
**Goal:** Build releases for ARM Raspberry Pi

**Step 1: Setup Docker for ARM builds (once, ~10 minutes)**

```bash
cd /home/tankwanghow/Projects/elixir/pou_con

# Run setup script
./scripts/setup_docker_arm.sh

# If prompted to log out/in, do so and run again
```

**Verify setup:**
```bash
docker buildx ls
# Should show 'multiarch' builder with linux/arm64 support
```

That's it! You never need to repeat this.

---

### Phase 2: Build for Deployment (Every Release)

**When you have code ready to deploy:**

**Option A: One Command (Easiest)**

```bash
cd /home/tankwanghow/Projects/elixir/pou_con

# Build AND package in one command
./scripts/build_and_package.sh

# Result: pou_con_deployment_YYYYMMDD_HHMMSS.tar.gz
```

**Option B: Step by Step**

```bash
# Build ARM release (~10-20 minutes)
./scripts/build_arm.sh

# Create deployment package (~1 minute)
./scripts/create_deployment_package.sh

# Result: pou_con_deployment_YYYYMMDD_HHMMSS.tar.gz
```

**Copy to USB drive:**
```bash
# Find USB mount point
lsblk

# Copy deployment package
cp pou_con_deployment_*.tar.gz /media/$USER/<usb-label>/

# Optional: Copy multiple packages for different sites
cp pou_con_deployment_*.tar.gz /media/$USER/<usb-label>/site1/
cp pou_con_deployment_*.tar.gz /media/$USER/<usb-label>/site2/
```

---

### Phase 3: Deploy at Poultry House (No Internet)

**Prerequisites on Raspberry Pi:**
- Raspberry Pi OS (64-bit) installed
- Basic system packages: `sqlite3`, `openssl`, `ca-certificates`, `libncurses5`
- RS485 USB adapters connected

**Note**: Install dependencies once (with internet at office):
```bash
sudo apt update && sudo apt install -y sqlite3 openssl ca-certificates locales libncurses5
```

**Deployment Process (5-10 minutes):**

```bash
# 1. Transfer package to Pi
# Via USB (insert USB drive):
cd ~
cp /media/pi/*/pou_con_deployment_*.tar.gz ./

# OR via network (if available):
# scp pou_con_deployment_*.tar.gz pi@<pi-ip>:~/

# 2. Extract and deploy
tar -xzf pou_con_deployment_*.tar.gz
cd deployment_package_*/
sudo ./deploy.sh

# The script automatically:
# - Creates pou_con user
# - Installs to /opt/pou_con
# - Sets up database at /var/lib/pou_con
# - Configures permissions
# - Sets up time management
# - Runs migrations

# 3. Start service
sudo systemctl enable pou_con
sudo systemctl start pou_con

# 4. Verify running
sudo systemctl status pou_con

# 5. Get Pi's IP address
hostname -I
```

**Access web interface:**

Open browser on any computer: `http://<pi-ip>:4000`

Login: `admin` / `admin` (change password immediately!)

---

### Phase 4: Initial Configuration (Web Interface)

**Login:**
- Username: `admin`
- Password: `admin`
- **CHANGE PASSWORD IMMEDIATELY!**

**Configure Hardware:**

1. **Admin → Ports**
   - Add RS485 port: `/dev/ttyUSB0`
   - Settings: 9600 baud, no parity, 8 data bits, 1 stop bit

2. **Admin → Devices**
   - Add Waveshare Modbus IO module
   - Add Temperature/Humidity sensors
   - Configure slave addresses

3. **Admin → Equipment**
   - Add fans: `fan_1`, `fan_2`, etc.
   - Add pumps: `pump_1`, `pump_2`, etc.
   - Configure device trees (JSON mapping)

4. **Test Manual Control**
   - Dashboard → Select equipment
   - Switch to Manual mode
   - Turn ON/OFF
   - Verify actual status matches

5. **Configure Automation**
   - Automation → Environment (temp/humidity control)
   - Automation → Lighting (schedules)
   - Automation → Feeding (schedules)

Done! System is now operational.

---

## File Locations Reference

**On Development Machine:**
```
/home/tankwanghow/Projects/elixir/pou_con/
├── Dockerfile.arm                          # ARM build definition
├── scripts/
│   ├── setup_docker_arm.sh                 # One-time setup
│   ├── build_arm.sh                        # Build ARM release
│   ├── create_deployment_package.sh        # Package for deployment
│   └── build_and_package.sh                # All-in-one
├── output/
│   └── pou_con_release_arm.tar.gz          # ARM release
└── pou_con_deployment_YYYYMMDD_HHMMSS.tar.gz  # Ready for USB
```

**On Raspberry Pi (after deployment):**
```
/opt/pou_con/                    # Application installation
/var/lib/pou_con/                # Database (pou_con_prod.db)
/var/log/pou_con/                # Application logs
/var/backups/pou_con/            # Database backups
/etc/systemd/system/pou_con.service  # Systemd service
```

---

## Troubleshooting

### Build Fails

**"Docker not found":**
```bash
./scripts/setup_docker_arm.sh
```

**"Permission denied" on Docker:**
```bash
sudo usermod -aG docker $USER
# Log out and log back in
```

**"Platform linux/arm64 not supported":**
```bash
# Reinstall buildx
docker buildx rm multiarch
./scripts/setup_docker_arm.sh
```

### Deployment Fails

**"deploy.sh: permission denied":**
```bash
chmod +x deploy.sh
sudo ./deploy.sh
```

**"User pou_con already exists":**
This is normal if redeploying. Script continues safely.

**"Database migration failed":**
```bash
# Check database permissions
sudo chown -R pou_con:pou_con /var/lib/pou_con

# Retry migration
sudo -u pou_con DATABASE_PATH=/var/lib/pou_con/pou_con_prod.db \
  /opt/pou_con/bin/pou_con eval "PouCon.Release.migrate"
```

### Service Won't Start

**Check logs:**
```bash
sudo journalctl -u pou_con -n 50 --no-pager
```

**Common issues:**

1. Port 4000 already in use:
   ```bash
   sudo netstat -tlnp | grep 4000
   # Kill conflicting process or change PORT in service file
   ```

2. Permission denied on /dev/ttyUSB0:
   ```bash
   sudo usermod -a -G dialout pou_con
   sudo systemctl restart pou_con
   ```

3. Database locked:
   ```bash
   sudo systemctl stop pou_con
   # Wait 5 seconds
   sudo systemctl start pou_con
   ```

### Cannot Access Web Interface

**From Pi itself:**
```bash
curl http://localhost:4000
# Should show HTML response
```

**From other computer:**
```bash
# Check Pi IP
hostname -I

# Test connectivity
ping <pi-ip>

# Check firewall (if enabled)
sudo ufw allow 4000/tcp
```

---

## Tips for Multiple Site Deployments

### Strategy 1: Master SD Card Image

1. Deploy to one Pi completely (including base system setup)
2. Configure and test thoroughly
3. Create SD card image:
   ```bash
   # On development machine with SD card reader
   sudo dd if=/dev/sdX of=pou_con_master.img bs=4M status=progress
   gzip pou_con_master.img
   ```
4. Flash this image to all other Pis
5. Only customize per-site settings (equipment names, IP, etc.)

**Deployment time per site: ~5 minutes** (just flash SD card)

### Strategy 2: Deployment Package + Configuration Templates

1. Create deployment package once
2. Copy to multiple USB drives
3. Create site-specific config files
4. Deploy to each Pi with site config

**Deployment time per site: ~10 minutes**

### Strategy 3: Pre-configured Spare Pi's

Keep 2-3 spare Pi's at office with:
- SD card with base system
- PouCon pre-deployed
- Generic configuration

When needed:
1. Grab spare Pi
2. Apply site-specific config
3. Ship/install on-site
4. Restore backup if replacing failed unit

**Replacement time: ~15 minutes**

---

## Backup and Recovery

### Create Backup

**Manual backup:**
```bash
# On Raspberry Pi
sudo ./backup.sh

# Backup saved to: /var/backups/pou_con/pou_con_backup_YYYYMMDD_HHMMSS.tar.gz
```

**Automatic backup (recommended):**
```bash
# Already configured by deploy.sh
# Runs daily at 2 AM
# Keeps last 7 backups
```

**Copy backup to USB:**
```bash
cp /var/backups/pou_con/pou_con_backup_*.tar.gz /media/pi/<usb-label>/
```

### Restore Backup

```bash
# On Raspberry Pi
sudo systemctl stop pou_con

# Extract backup
cd /tmp
tar -xzf /media/pi/<usb-label>/pou_con_backup_YYYYMMDD_HHMMSS.tar.gz

# Restore database
sudo cp pou_con_prod.db /var/lib/pou_con/
sudo chown pou_con:pou_con /var/lib/pou_con/pou_con_prod.db

# Restart service
sudo systemctl start pou_con
```

---

## Maintenance Commands

```bash
# Service management
sudo systemctl start pou_con      # Start
sudo systemctl stop pou_con       # Stop
sudo systemctl restart pou_con    # Restart
sudo systemctl status pou_con     # Status

# Logs
sudo journalctl -u pou_con -f                # Follow logs
sudo journalctl -u pou_con --since today     # Today's logs
sudo journalctl -u pou_con -n 100            # Last 100 lines

# Backup
sudo /var/backups/pou_con/backup.sh          # Manual backup

# Database access
sqlite3 /var/lib/pou_con/pou_con_prod.db     # Direct DB access

# System info
df -h                             # Disk space
free -h                           # Memory
systemctl is-active pou_con       # Check if running
ls -l /dev/ttyUSB*                # Check USB devices
```

---

## Support

**Documentation:**
- `DEPLOYMENT_GUIDE.md` - Comprehensive deployment documentation
- `CROSS_PLATFORM_BUILD.md` - Detailed build process explanation
- `CLAUDE.md` - Project architecture and development guide

**Common Issues:**
- Service won't start: Check logs with `journalctl`
- Can't access web: Check firewall and IP address
- Modbus errors: Check USB permissions and device paths

---

## Summary: Your Workflow

**One-time setup (10 minutes):**
```bash
./scripts/setup_docker_arm.sh
```

**Build deployment package (10-20 minutes):**
```bash
./scripts/build_and_package.sh
cp pou_con_deployment_*.tar.gz /media/usb/
```

**Deploy at poultry house (5-10 minutes, no internet):**
```bash
tar -xzf pou_con_deployment_*.tar.gz
cd deployment_package_*/
sudo ./deploy.sh
sudo systemctl enable pou_con && sudo systemctl start pou_con
hostname -I  # Get Pi's IP
```

**Configure via browser:**
- Access: `http://<pi-ip>:4000`
- Login: `admin` / `admin`
- Change password immediately
- Configure ports, devices, equipment

Done!

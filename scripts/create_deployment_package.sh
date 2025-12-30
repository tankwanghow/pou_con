#!/bin/bash
# Create deployment package from ARM release tarball
# This package can be deployed to Raspberry Pi without internet

set -e

echo "=== Creating Deployment Package ==="
echo ""

# Check if release exists
if [ ! -f "output/pou_con_release_arm.tar.gz" ]; then
    echo "ERROR: Release not found: output/pou_con_release_arm.tar.gz"
    echo "Run ./scripts/build_arm.sh first"
    exit 1
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
PACKAGE_DIR="deployment_package_$TIMESTAMP"

echo "Creating package: $PACKAGE_DIR"

# Create package directory structure
mkdir -p "$PACKAGE_DIR/pou_con"

# Extract release
echo "Extracting release..."
tar -xzf output/pou_con_release_arm.tar.gz -C "$PACKAGE_DIR/pou_con/"

# Create deploy script
echo "Creating deployment scripts..."
cat > "$PACKAGE_DIR/deploy.sh" << 'EOF'
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
mkdir -p /var/backups/pou_con

echo "3. Copying application files..."
cp -r pou_con/* "$INSTALL_DIR/"

echo "4. Setting directory permissions..."
chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"
chown -R "$SERVICE_USER:$SERVICE_USER" "$DATA_DIR"
chown -R "$SERVICE_USER:$SERVICE_USER" /var/log/pou_con
# Ensure database directory is writable
chmod 755 "$DATA_DIR"

echo "5. Setting up USB serial port permissions..."
usermod -a -G dialout "$SERVICE_USER"

echo "6. Setting up web-based system time management..."
if [ -f "setup_sudo.sh" ]; then
    bash setup_sudo.sh
    echo "   System time management configured"
else
    echo "   WARNING: setup_sudo.sh not found - skipping time management setup"
    echo "   You can set it up later by running: sudo bash setup_sudo.sh"
fi

echo "7. Installing systemd service..."
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
Environment="PHX_SERVER=true"
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

echo "8. Generating SECRET_KEY_BASE..."
SECRET_KEY=$(openssl rand -base64 48)
sed -i "s|CHANGE_THIS_SECRET_KEY|$SECRET_KEY|" /etc/systemd/system/pou_con.service

echo "9. Reloading systemd..."
systemctl daemon-reload

echo "10. Running database migrations..."
cd "$INSTALL_DIR"
sudo -u "$SERVICE_USER" DATABASE_PATH="$DATA_DIR/pou_con_prod.db" SECRET_KEY_BASE="$SECRET_KEY" ./bin/pou_con eval "PouCon.Release.migrate"

echo "11. Running database seeds..."
sudo -u "$SERVICE_USER" DATABASE_PATH="$DATA_DIR/pou_con_prod.db" SECRET_KEY_BASE="$SECRET_KEY" ./bin/pou_con eval "PouCon.Release.seed" || echo "Seeding failed or already seeded"

echo "12. Verifying database permissions..."
if [ -f "$DATA_DIR/pou_con_prod.db" ]; then
    chown "$SERVICE_USER:$SERVICE_USER" "$DATA_DIR/pou_con_prod.db"
    chmod 644 "$DATA_DIR/pou_con_prod.db"
    echo "   Database permissions verified"
else
    echo "   WARNING: Database file not found - may be created on first run"
fi

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

chmod +x "$PACKAGE_DIR/deploy.sh"

# Create backup script
cat > "$PACKAGE_DIR/backup.sh" << 'EOF'
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

chmod +x "$PACKAGE_DIR/backup.sh"

# Create uninstall script
cat > "$PACKAGE_DIR/uninstall.sh" << 'EOF'
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
echo "  - /var/backups/pou_con/"
echo ""
echo "To completely remove including data, run:"
echo "  sudo rm -rf /var/lib/pou_con /var/log/pou_con /var/backups/pou_con"
echo "  sudo userdel pou_con"
EOF

chmod +x "$PACKAGE_DIR/uninstall.sh"

# Copy kiosk setup script (if it exists)
if [ -f "scripts/setup_kiosk.sh" ]; then
    cp scripts/setup_kiosk.sh "$PACKAGE_DIR/"
    chmod +x "$PACKAGE_DIR/setup_kiosk.sh"
fi

# Copy house setup script for HTTPS configuration
if [ -f "scripts/setup_house.sh" ]; then
    cp scripts/setup_house.sh "$PACKAGE_DIR/"
    chmod +x "$PACKAGE_DIR/setup_house.sh"
fi

# Copy setup_sudo.sh for system time management (if it exists)
if [ -f "setup_sudo.sh" ]; then
    cp setup_sudo.sh "$PACKAGE_DIR/"
    chmod +x "$PACKAGE_DIR/setup_sudo.sh"
fi

# Create README
cat > "$PACKAGE_DIR/README.txt" << 'EOF'
PouCon Deployment Package
=========================

This package contains everything needed to deploy PouCon to a Raspberry Pi
without internet access.

Contents:
  - pou_con/         : Application release (built for ARM)
  - deploy.sh        : Deployment script (runs setup_sudo.sh automatically)
  - backup.sh        : Backup script
  - uninstall.sh     : Uninstall script
  - setup_house.sh   : House setup (house_id + HTTPS certificates)
  - setup_sudo.sh    : System time management setup (auto-run by deploy.sh)
  - setup_kiosk.sh   : Optional touchscreen kiosk mode setup
  - README.txt       : This file

Requirements:
  - Raspberry Pi 3B+ or 4 with Raspberry Pi OS (64-bit)
  - System dependencies installed (see DEPLOYMENT_GUIDE.md)
  - RS485 USB adapter(s) connected

Quick Start:
  1. Copy this entire directory to the Raspberry Pi:
     scp -r deployment_package_* pi@<pi-ip>:~/

  2. SSH to the Pi:
     ssh pi@<pi-ip>

  3. Run deployment:
     cd deployment_package_*
     sudo ./deploy.sh

  4. Enable and start service:
     sudo systemctl enable pou_con
     sudo systemctl start pou_con

  5. Check status:
     sudo systemctl status pou_con

Configuration:
  After deployment, configure via web interface:
  - http://<pi-ip-address>:4000
  - Default login: admin / admin (CHANGE IMMEDIATELY!)

Post-Deployment:
  - Configure Ports (Admin -> Ports)
  - Configure Devices (Admin -> Devices)
  - Configure Equipment (Admin -> Equipment)
  - Set up automation schedules

System Time Management:
  The deploy.sh script automatically configures web-based time setting.
  This allows you to set the system time via the web interface if the
  RTC battery fails or if the Pi loses time. Access via Admin -> System Settings.

  If you need to run this setup manually later:
  - Run: sudo bash setup_sudo.sh

Environment Variables (Advanced):
  The systemd service is configured with default environment variables:
  - PORT=4000 (web interface port)
  - DATABASE_PATH=/var/lib/pou_con/pou_con_prod.db
  - PHX_HOST=localhost
  - SECRET_KEY_BASE=<auto-generated>

  To customize these (e.g., change port, move database):
  - Edit: sudo nano /etc/systemd/system/pou_con.service
  - Reload: sudo systemctl daemon-reload
  - Restart: sudo systemctl restart pou_con
  - See DEPLOYMENT_GUIDE.md "Environment Variables Reference" for details

Backup:
  - Manual: sudo ./backup.sh
  - Automatic: Configured in cron (daily at 2 AM)
  - Location: /var/backups/pou_con/

Logs:
  - View logs: sudo journalctl -u pou_con -f
  - Log location: /var/log/pou_con/

Touchscreen Kiosk Mode (Optional):
  If you have a touchscreen connected:
  - Run: ./setup_kiosk.sh
  - Reboot: sudo reboot
  - Pi will boot to fullscreen PouCon interface
  - See TOUCHSCREEN_KIOSK_SETUP.md for details

Support:
  See DEPLOYMENT_GUIDE.md, CROSS_PLATFORM_BUILD.md, and TOUCHSCREEN_KIOSK_SETUP.md
  for detailed documentation
EOF

# Package everything
echo "Creating deployment archive..."
tar -czf "pou_con_deployment_$TIMESTAMP.tar.gz" "$PACKAGE_DIR/"

# Cleanup temp directory
rm -rf "$PACKAGE_DIR"

echo ""
echo "=== Deployment Package Created! ==="
echo ""
echo "Package: pou_con_deployment_$TIMESTAMP.tar.gz"
echo "Size: $(du -h pou_con_deployment_$TIMESTAMP.tar.gz | cut -f1)"
echo ""
echo "Next steps:"
echo "  1. Copy to USB drive:"
echo "     cp pou_con_deployment_$TIMESTAMP.tar.gz /media/<usb-drive>/"
echo ""
echo "  2. At poultry house, extract and deploy:"
echo "     tar -xzf pou_con_deployment_$TIMESTAMP.tar.gz"
echo "     cd deployment_package_*/"
echo "     sudo ./deploy.sh"
echo ""
echo "  3. Follow on-screen instructions"

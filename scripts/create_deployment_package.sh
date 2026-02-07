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
mkdir -p "$PACKAGE_DIR/debs"

# Extract release
echo "Extracting release..."
tar -xzf output/pou_con_release_arm.tar.gz -C "$PACKAGE_DIR/pou_con/"

# Extract runtime dependencies if available
if [ -f "output/runtime_debs_arm.tar.gz" ]; then
    echo "Including offline dependencies..."
    tar -xzf output/runtime_debs_arm.tar.gz -C "$PACKAGE_DIR/debs/"
    echo "  ✓ $(ls "$PACKAGE_DIR/debs/"*.deb 2>/dev/null | wc -l) packages included"
else
    echo "  ⚠ No offline dependencies found - deployment will require internet"
    rmdir "$PACKAGE_DIR/debs" 2>/dev/null || true
fi

# Create deploy script
echo "Creating deployment scripts..."
cat > "$PACKAGE_DIR/deploy.sh" << 'EOF'
#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "═══════════════════════════════════════════"
echo "  PouCon Complete Deployment"
echo "═══════════════════════════════════════════"
echo ""

# Variables
INSTALL_DIR="/opt/pou_con"
DATA_DIR="/var/lib/pou_con"
POUCON_CONFIG_DIR="/etc/pou_con"
SSL_DIR="$POUCON_CONFIG_DIR/ssl"
SERVICE_USER="pi"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root (use sudo)${NC}"
  exit 1
fi

# Check for CA files
if [ ! -f "$SCRIPT_DIR/ca.crt" ] || [ ! -f "$SCRIPT_DIR/ca.key" ]; then
    echo -e "${RED}ERROR: CA files not found in deployment package!${NC}"
    echo "Expected: $SCRIPT_DIR/ca.crt and $SCRIPT_DIR/ca.key"
    echo "Run ./scripts/setup_ca.sh on your dev machine first."
    exit 1
fi

#═══════════════════════════════════════════
# STEP 1: Prompt for House ID
#═══════════════════════════════════════════
echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo -e "${CYAN}  House Configuration${NC}"
echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo ""
echo "Enter the house identifier for this installation."
echo "Examples: h1, h2, house1, farm_a, building_north"
echo ""
read -p "House ID: " HOUSE_ID

if [ -z "$HOUSE_ID" ]; then
    echo -e "${RED}ERROR: House ID cannot be empty${NC}"
    exit 1
fi

# Normalize house_id (lowercase, trim whitespace)
HOUSE_ID=$(echo "$HOUSE_ID" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
HOSTNAME="poucon.$HOUSE_ID"

echo ""
echo "Configuration:"
echo -e "  House ID:  ${CYAN}$HOUSE_ID${NC}"
echo -e "  Hostname:  ${CYAN}$HOSTNAME${NC}"
echo -e "  URL:       ${CYAN}https://$HOSTNAME${NC}"
echo ""
read -p "Proceed? (Y/n): " confirm
if [[ "$confirm" =~ ^[Nn]$ ]]; then
    echo "Cancelled."
    exit 0
fi

#═══════════════════════════════════════════
# STEP 1b: Configure Serial Port
#═══════════════════════════════════════════
echo ""
echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo -e "${CYAN}  Serial Port Configuration${NC}"
echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo ""
echo "Select the Modbus RS485 serial port type:"
echo ""
echo "  1) USB Adapter (ttyUSB0) - Raspberry Pi with USB-RS485 adapter"
echo "  2) Built-in RS485 (ttyAMA0) - RevPi Connect 5 RS485 variant"
echo "  3) Custom - Enter a custom device path"
echo ""
read -p "Select [1-3] (default: 1): " PORT_CHOICE

case "$PORT_CHOICE" in
    2)
        MODBUS_PORT="ttyAMA0"
        echo -e "   Selected: ${CYAN}Built-in RS485 (/dev/ttyAMA0)${NC}"
        ;;
    3)
        read -p "   Enter device path (without /dev/): " CUSTOM_PORT
        MODBUS_PORT="${CUSTOM_PORT:-ttyUSB0}"
        echo -e "   Selected: ${CYAN}Custom (/dev/$MODBUS_PORT)${NC}"
        ;;
    *)
        MODBUS_PORT="ttyUSB0"
        echo -e "   Selected: ${CYAN}USB Adapter (/dev/ttyUSB0)${NC}"
        ;;
esac

# Store port choice for seed script
export MODBUS_PORT_PATH="$MODBUS_PORT"

#═══════════════════════════════════════════
# STEP 2: Install Dependencies
#═══════════════════════════════════════════
echo ""
echo "1. Installing system dependencies..."

# Check internet connectivity (quick test with 3 second timeout)
check_internet() {
    wget -q --spider --timeout=3 http://deb.debian.org 2>/dev/null || \
    ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1
}

# Check if offline package is newer than installed version
# Returns 0 if offline should be installed (newer or not installed)
needs_offline_install() {
    local deb_file="$1"
    local pkg_name=$(dpkg-deb -f "$deb_file" Package 2>/dev/null)
    local offline_ver=$(dpkg-deb -f "$deb_file" Version 2>/dev/null)
    local installed_ver=$(dpkg-query -W -f '${Version}' "$pkg_name" 2>/dev/null || echo "")

    if [ -z "$installed_ver" ]; then
        # Package not installed - need to install
        return 0
    fi

    if [ -z "$offline_ver" ]; then
        # Can't read offline version - skip
        return 1
    fi

    # Compare versions: returns 0 if offline is newer
    dpkg --compare-versions "$offline_ver" gt "$installed_ver" 2>/dev/null
}

HAS_OFFLINE_DEBS=false
if [ -d "$SCRIPT_DIR/debs" ] && ls "$SCRIPT_DIR/debs/"*.deb 1> /dev/null 2>&1; then
    HAS_OFFLINE_DEBS=true
fi

if check_internet; then
    echo "   Internet available - installing from online repositories..."
    apt-get update -qq
    apt-get install -y -qq sqlite3 libsqlite3-dev openssl libncurses5 swayidle > /dev/null
    echo "   ✓ Dependencies installed (online - latest versions)"
elif [ "$HAS_OFFLINE_DEBS" = true ]; then
    echo "   No internet - checking offline packages..."
    DEBS_TO_INSTALL=""
    for deb_file in "$SCRIPT_DIR/debs/"*.deb; do
        pkg_name=$(dpkg-deb -f "$deb_file" Package 2>/dev/null || basename "$deb_file" .deb)
        if needs_offline_install "$deb_file"; then
            echo "   → $pkg_name: will install from offline"
            DEBS_TO_INSTALL="$DEBS_TO_INSTALL $deb_file"
        else
            echo "   → $pkg_name: already installed (same or newer)"
        fi
    done

    if [ -n "$DEBS_TO_INSTALL" ]; then
        echo "   Installing selected offline packages..."
        dpkg -i $DEBS_TO_INSTALL 2>&1 | grep -v "^Selecting\|^Preparing\|^Unpacking\|^Setting up" || true
        # Fix any broken dependencies (offline, so this may fail)
        apt-get install -f -y -qq 2>/dev/null || true
        echo "   ✓ Dependencies installed (offline)"
    else
        echo "   ✓ All packages already up-to-date"
    fi
else
    echo -e "   ${YELLOW}No internet and no offline packages available${NC}"
    echo "   Attempting to install from system cache..."
    apt-get install -y -qq sqlite3 libsqlite3-dev openssl libncurses5 swayidle 2>/dev/null || true
fi

# Verify critical tools are available
for cmd in openssl sqlite3; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "   ${RED}ERROR: $cmd not found after installation${NC}"
        echo "   Try: apt-get update && apt-get install -y $cmd"
        exit 1
    fi
done
echo "   ✓ All required tools available"

#═══════════════════════════════════════════
# STEP 3: Verify User and Create Directories
#═══════════════════════════════════════════
echo "2. Verifying application user..."
if ! id "$SERVICE_USER" &>/dev/null; then
    echo -e "   ${RED}ERROR: pi user not found - this is unexpected on Raspberry Pi OS${NC}"
    exit 1
fi
echo "   ✓ Using default pi user"

echo "3. Creating directories..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$DATA_DIR"
mkdir -p "$POUCON_CONFIG_DIR"
mkdir -p "$SSL_DIR"
mkdir -p /var/log/pou_con
mkdir -p /var/backups/pou_con

#═══════════════════════════════════════════
# STEP 4: Write House ID
#═══════════════════════════════════════════
echo "4. Writing house_id..."
echo "$HOUSE_ID" > "$POUCON_CONFIG_DIR/house_id"
chmod 644 "$POUCON_CONFIG_DIR/house_id"
echo "   ✓ House ID: $HOUSE_ID"

#═══════════════════════════════════════════
# STEP 5: Generate SSL Certificate
#═══════════════════════════════════════════
echo "5. Generating SSL certificate..."

# Check if openssl is available
if ! command -v openssl &> /dev/null; then
    echo -e "   ${RED}ERROR: openssl not found${NC}"
    echo "   Try: apt-get update && apt-get install -y openssl"
    exit 1
fi

# Check if CA files exist
if [ ! -f "$SCRIPT_DIR/ca.crt" ] || [ ! -f "$SCRIPT_DIR/ca.key" ]; then
    echo -e "   ${RED}ERROR: CA files not found in deployment package${NC}"
    echo "   Expected: $SCRIPT_DIR/ca.crt and $SCRIPT_DIR/ca.key"
    exit 1
fi

# Get Pi's IP address
PI_IP=$(hostname -I | awk '{print $1}')
if [ -z "$PI_IP" ]; then
    PI_IP="127.0.0.1"
    echo "   ⚠ Could not detect IP, using 127.0.0.1"
fi

# Create temp directory for cert generation
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Generate server private key
echo "   Generating private key..."
if ! openssl genrsa -out server.key 2048 2>&1; then
    echo -e "   ${RED}ERROR: Failed to generate private key${NC}"
    exit 1
fi

# Create CSR
echo "   Creating certificate request..."
if ! openssl req -new -key server.key \
    -out server.csr \
    -subj "/CN=$HOSTNAME/O=PouCon/C=MY" 2>&1; then
    echo -e "   ${RED}ERROR: Failed to create CSR${NC}"
    exit 1
fi

# Create extension file with SAN
cat > server.ext << EXTEOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = $HOSTNAME
DNS.2 = poucon.$HOUSE_ID.local
DNS.3 = localhost
IP.1 = $PI_IP
IP.2 = 127.0.0.1
EXTEOF

# Sign with CA (valid 2 years)
echo "   Signing certificate with CA..."
if ! openssl x509 -req -in server.csr \
    -CA "$SCRIPT_DIR/ca.crt" -CAkey "$SCRIPT_DIR/ca.key" \
    -CAcreateserial \
    -out server.crt \
    -days 730 \
    -sha256 \
    -extfile server.ext 2>&1; then
    echo -e "   ${RED}ERROR: Failed to sign certificate${NC}"
    echo "   Check that ca.crt and ca.key are valid"
    cd "$SCRIPT_DIR"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Verify certificate was created
if [ ! -f server.crt ] || [ ! -s server.crt ]; then
    echo -e "   ${RED}ERROR: Certificate file not created or empty${NC}"
    cd "$SCRIPT_DIR"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Install certificates (permissions set later in Step 7 after recursive chown)
cp server.key "$SSL_DIR/server.key"
cp server.crt "$SSL_DIR/server.crt"
cp "$SCRIPT_DIR/ca.crt" "$SSL_DIR/ca.crt"

# Cleanup
cd "$SCRIPT_DIR"
rm -rf "$TEMP_DIR"

echo "   ✓ SSL certificate generated for $HOSTNAME"

#═══════════════════════════════════════════
# STEP 6: Copy Application Files
#═══════════════════════════════════════════
echo "6. Copying application files..."
cp -r "$SCRIPT_DIR/pou_con/"* "$INSTALL_DIR/"

#═══════════════════════════════════════════
# STEP 7: Set Permissions
#═══════════════════════════════════════════
echo "7. Setting permissions..."
chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"
chown -R "$SERVICE_USER:$SERVICE_USER" "$DATA_DIR"
chown -R "$SERVICE_USER:$SERVICE_USER" /var/log/pou_con
chown -R root:root "$POUCON_CONFIG_DIR"
chmod 755 "$DATA_DIR"
chmod 755 "$POUCON_CONFIG_DIR"

# SSL key must be readable by the service user (set AFTER recursive chown above)
chown "$SERVICE_USER:$SERVICE_USER" "$SSL_DIR/server.key"
chmod 600 "$SSL_DIR/server.key"
chmod 644 "$SSL_DIR/server.crt"
chmod 644 "$SSL_DIR/ca.crt"
echo "   ✓ SSL key ownership set to $SERVICE_USER"

# Group permissions for hardware and display access
usermod -a -G dialout "$SERVICE_USER"  # Serial ports (Modbus RTU)
usermod -a -G video "$SERVICE_USER"    # Backlight control (screen blanking)
usermod -a -G input "$SERVICE_USER"    # Touchscreen input
usermod -a -G render "$SERVICE_USER" 2>/dev/null || true  # GPU access (may not exist)
usermod -a -G audio "$SERVICE_USER" 2>/dev/null || true   # Audio (for alerts)

#═══════════════════════════════════════════
# STEP 8: Allow Privileged Ports
#═══════════════════════════════════════════
echo "8. Allowing privileged ports (80/443)..."
if ls "$INSTALL_DIR"/erts-*/bin/beam.smp 1> /dev/null 2>&1; then
    setcap 'cap_net_bind_service=+ep' "$INSTALL_DIR"/erts-*/bin/beam.smp
    echo "   ✓ Port binding enabled"
else
    echo "   ⚠ beam.smp not found - may need manual setcap"
fi

#═══════════════════════════════════════════
# STEP 9: System Time Management
#═══════════════════════════════════════════
echo "9. Setting up system time management..."
if [ -f "$SCRIPT_DIR/setup_sudo.sh" ]; then
    bash "$SCRIPT_DIR/setup_sudo.sh"
    echo "   ✓ Time management configured"
else
    echo "   ⚠ setup_sudo.sh not found - skipping"
fi

#═══════════════════════════════════════════
# STEP 10: Install Systemd Service
#═══════════════════════════════════════════
echo "10. Installing systemd service..."
cat > /etc/systemd/system/pou_con.service << EOSERVICE
[Unit]
Description=PouCon Industrial Control System
After=network.target

[Service]
Type=simple
User=pi
Group=pi
WorkingDirectory=/opt/pou_con
Environment="DATABASE_PATH=/var/lib/pou_con/pou_con_prod.db"
Environment="SECRET_KEY_BASE=CHANGE_THIS_SECRET_KEY"
Environment="MIX_ENV=prod"
Environment="PHX_SERVER=true"
ExecStart=/opt/pou_con/bin/pou_con start
ExecStop=/opt/pou_con/bin/pou_con stop
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=pou_con
AmbientCapabilities=CAP_NET_BIND_SERVICE
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOSERVICE

# Generate and set SECRET_KEY_BASE
SECRET_KEY=$(openssl rand -base64 48)
sed -i "s|CHANGE_THIS_SECRET_KEY|$SECRET_KEY|" /etc/systemd/system/pou_con.service

systemctl daemon-reload
echo "   ✓ Service installed"

#═══════════════════════════════════════════
# STEP 11: Database Setup
#═══════════════════════════════════════════
echo "11. Running database migrations..."
cd "$INSTALL_DIR"
sudo -u "$SERVICE_USER" DATABASE_PATH="$DATA_DIR/pou_con_prod.db" SECRET_KEY_BASE="$SECRET_KEY" ./bin/pou_con eval "PouCon.Release.migrate"

echo "12. Running database seeds..."
echo "    Serial port: $MODBUS_PORT_PATH"
sudo -u "$SERVICE_USER" DATABASE_PATH="$DATA_DIR/pou_con_prod.db" SECRET_KEY_BASE="$SECRET_KEY" MODBUS_PORT_PATH="$MODBUS_PORT_PATH" ./bin/pou_con eval "PouCon.Release.seed" 2>/dev/null || true

if [ -f "$DATA_DIR/pou_con_prod.db" ]; then
    chown "$SERVICE_USER:$SERVICE_USER" "$DATA_DIR/pou_con_prod.db"
    chmod 644 "$DATA_DIR/pou_con_prod.db"
fi

#═══════════════════════════════════════════
# STEP 12: Set Hostname (Optional)
#═══════════════════════════════════════════
echo ""
read -p "Set system hostname to '$HOSTNAME'? (Y/n): " set_hostname
if [[ ! "$set_hostname" =~ ^[Nn]$ ]]; then
    hostnamectl set-hostname "$HOSTNAME"
    if ! grep -q "$HOSTNAME" /etc/hosts; then
        echo "127.0.0.1 $HOSTNAME" >> /etc/hosts
    fi
    echo "   ✓ Hostname set"
fi

#═══════════════════════════════════════════
# STEP 13: Enable and Start Service
#═══════════════════════════════════════════
echo ""
echo "13. Starting PouCon service..."
systemctl enable pou_con
systemctl start pou_con
sleep 3

if systemctl is-active --quiet pou_con; then
    echo -e "   ${GREEN}✓ Service started successfully!${NC}"
else
    echo -e "   ${YELLOW}⚠ Service may not have started. Check: sudo journalctl -u pou_con${NC}"
fi

#═══════════════════════════════════════════
# DONE!
#═══════════════════════════════════════════
echo ""
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo -e "${GREEN}  Deployment Complete!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo ""
echo "  House ID:      $HOUSE_ID"
echo "  Serial Port:   /dev/$MODBUS_PORT_PATH"
echo "  IP Address:    $PI_IP"
echo "  URL:           https://$HOSTNAME"
echo ""
echo -e "${YELLOW}CLIENT DEVICE SETUP:${NC}"
echo "  1. Install ca.crt on mobile/iPad (one-time)"
echo "  2. Add to DNS or /etc/hosts:"
echo "     $PI_IP  $HOSTNAME"
echo "  3. Access: https://$HOSTNAME"
echo ""
echo "Default login: admin / admin (CHANGE IMMEDIATELY)"
echo ""
echo -e "${GREEN}You can now unplug the USB drive.${NC}"
echo ""
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
echo "  sudo rm -rf /var/lib/pou_con /var/log/pou_con /var/backups/pou_con /etc/pou_con"
EOF

chmod +x "$PACKAGE_DIR/uninstall.sh"

# Copy update script for existing installations
if [ -f "scripts/update.sh" ]; then
    cp scripts/update.sh "$PACKAGE_DIR/"
    chmod +x "$PACKAGE_DIR/update.sh"
    echo "  ✓ Update script included (for existing installations)"
fi

# Copy kiosk setup script (if it exists)
if [ -f "scripts/setup_kiosk.sh" ]; then
    cp scripts/setup_kiosk.sh "$PACKAGE_DIR/"
    chmod +x "$PACKAGE_DIR/setup_kiosk.sh"
fi

# Copy RevPi-specific scripts
if [ -f "scripts/verify_revpi_hardware.sh" ]; then
    cp scripts/verify_revpi_hardware.sh "$PACKAGE_DIR/"
    chmod +x "$PACKAGE_DIR/verify_revpi_hardware.sh"
    echo "  ✓ RevPi hardware verification script included"
fi

# Copy screen timeout scripts
if [ -f "scripts/set_screen_timeout.sh" ]; then
    mkdir -p "$PACKAGE_DIR/pou_con/scripts"
    cp scripts/set_screen_timeout.sh "$PACKAGE_DIR/pou_con/scripts/"
    cp scripts/on_screen.sh "$PACKAGE_DIR/pou_con/scripts/"
    cp scripts/off_screen.sh "$PACKAGE_DIR/pou_con/scripts/"
    chmod +x "$PACKAGE_DIR/pou_con/scripts/"*.sh
    echo "  ✓ Screen timeout scripts included"
fi

if [ -f "scripts/revpi_first_setup.sh" ]; then
    cp scripts/revpi_first_setup.sh "$PACKAGE_DIR/"
    chmod +x "$PACKAGE_DIR/revpi_first_setup.sh"
    echo "  ✓ RevPi first-time setup script included"
fi

# Copy house setup script for HTTPS configuration
if [ -f "scripts/setup_house.sh" ]; then
    cp scripts/setup_house.sh "$PACKAGE_DIR/"
    chmod +x "$PACKAGE_DIR/setup_house.sh"
fi

# Copy CA files for HTTPS setup (if they exist)
if [ -f "priv/ssl/ca/ca.crt" ] && [ -f "priv/ssl/ca/ca.key" ]; then
    echo "Including CA files for HTTPS setup..."
    cp priv/ssl/ca/ca.crt "$PACKAGE_DIR/"
    cp priv/ssl/ca/ca.key "$PACKAGE_DIR/"
    echo "  ✓ CA files included"
else
    echo "  ⚠ CA files not found - run ./scripts/setup_ca.sh first if you need HTTPS"
fi

# Copy setup_sudo.sh for system time management (if it exists)
if [ -f "setup_sudo.sh" ]; then
    cp setup_sudo.sh "$PACKAGE_DIR/"
    chmod +x "$PACKAGE_DIR/setup_sudo.sh"
fi

# Copy user documentation
echo "Including user documentation..."
if [ -f "docs/USER_MANUAL.md" ]; then
    cp docs/USER_MANUAL.md "$PACKAGE_DIR/"
    echo "  ✓ User manual included"
fi
if [ -f "docs/DEPLOYMENT_MANUAL.md" ]; then
    cp docs/DEPLOYMENT_MANUAL.md "$PACKAGE_DIR/"
    echo "  ✓ Deployment manual included"
fi
if [ -f "docs/REVPI_DEPLOYMENT_GUIDE.md" ]; then
    cp docs/REVPI_DEPLOYMENT_GUIDE.md "$PACKAGE_DIR/"
    echo "  ✓ RevPi deployment guide included"
fi

# Create README
cat > "$PACKAGE_DIR/README.txt" << 'EOF'
PouCon Deployment Package
=========================

This package contains everything needed to deploy PouCon to a Raspberry Pi
without internet access.

Contents:
  - pou_con/                   : Application release (built for ARM)
  - debs/                      : Offline system dependencies (if available)
  - deploy.sh                  : Fresh installation script (new Pi)
  - update.sh                  : Update existing installation (preserves data)
  - setup_house.sh             : House reconfiguration (house_id + HTTPS)
  - ca.crt, ca.key             : CA files for signing SSL certificates
  - backup.sh                  : Backup script
  - uninstall.sh               : Uninstall script
  - setup_sudo.sh              : System time management setup (auto-run by deploy.sh)
  - setup_kiosk.sh             : Optional touchscreen kiosk mode setup
  - verify_revpi_hardware.sh   : RevPi hardware verification (optional)
  - revpi_first_setup.sh       : RevPi first-time setup (optional)
  - USER_MANUAL.md             : Complete operator guide
  - DEPLOYMENT_MANUAL.md       : Detailed deployment instructions
  - REVPI_DEPLOYMENT_GUIDE.md  : RevPi Connect 5 specific guide
  - README.txt                 : This file

Requirements:
  - Raspberry Pi 3B+/4/5 with Raspberry Pi OS (64-bit), OR
  - RevPi Connect 5 with RevPi OS (Debian Bookworm), OR
  - Any ARM64 Linux system with Debian/Ubuntu
  - RS485 USB adapter(s) OR built-in RS485 (RevPi RS485 variant)
  - NO INTERNET REQUIRED (if debs/ folder is present)

Quick Start (USB Drive - No Internet Required):
  1. Extract on USB drive:
     tar -xzf pou_con_deployment_*.tar.gz

  2. At Raspberry Pi - insert USB and run:
     cd /media/pi/*/deployment_package_*/
     sudo ./deploy.sh

  3. Follow prompts:
     - Enter house_id (e.g., h1, h2, farm_a)
     - Confirm configuration
     - Done! Service starts automatically

  4. Unplug USB drive

Updating Existing Installation:
  If you already have PouCon running and want to update:

  1. At Raspberry Pi - insert USB and run:
     cd /media/pi/*/deployment_package_*/
     sudo ./update.sh

  2. The script will:
     - Stop the service
     - Backup your database (to /var/backups/pou_con/)
     - Update application files
     - Run database migrations
     - Restart the service

  Your data, SSL certificates, and configuration are preserved.

  To rollback if something goes wrong:
     sudo systemctl stop pou_con
     cp /var/backups/pou_con/pou_con_pre_update_<timestamp>.db /var/lib/pou_con/pou_con_prod.db
     sudo systemctl start pou_con

RevPi Connect 5 Deployment:
  For RevPi Connect 5, the process is identical. Optional extra steps:

  1. First-time RevPi setup (on fresh RevPi OS):
     sudo ./revpi_first_setup.sh

  2. Verify hardware before deployment:
     sudo ./verify_revpi_hardware.sh

  3. Serial port configuration:
     - Built-in RS485 (RevPi RS485 variant): /dev/ttyAMA0
     - USB adapter: /dev/ttyUSB0

  See REVPI_DEPLOYMENT_GUIDE.md for detailed instructions.

Configuration:
  After deployment, configure via web interface:
  - https://poucon.<house_id> (or http://<pi-ip>)
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

Documentation:
  The following guides are included in this package:
  - USER_MANUAL.md           : Complete operator guide for daily use
  - DEPLOYMENT_MANUAL.md     : Detailed deployment and setup instructions
  - REVPI_DEPLOYMENT_GUIDE.md: RevPi Connect 5 specific deployment guide
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

# Check if offline deps were included
if [ -f "output/runtime_debs_arm.tar.gz" ]; then
    echo ""
    echo "✓ OFFLINE DEPLOYMENT ENABLED"
    echo "  System dependencies included - no internet required!"
else
    echo ""
    echo "⚠ Online deployment only - internet required at Pi"
fi

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
echo "  3. Follow on-screen prompts (enter house_id, confirm)"
echo "  4. Unplug USB - done!"

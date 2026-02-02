#!/bin/bash
# Update existing PouCon installation
# Usage: sudo ./update.sh
#
# This script updates an existing PouCon installation while preserving:
# - Database (all your data)
# - SSL certificates
# - House ID configuration
# - SECRET_KEY_BASE
# - Systemd service configuration
#
# It will:
# - Stop the service
# - Backup the database
# - Extract new application files
# - Run database migrations
# - Restart the service

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
INSTALL_DIR="/opt/pou_con"
DATA_DIR="/var/lib/pou_con"
BACKUP_DIR="/var/backups/pou_con"
SERVICE_USER="pi"
DB_FILE="$DATA_DIR/pou_con_prod.db"

echo ""
echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo -e "${CYAN}  PouCon Update Script${NC}"
echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root (use sudo)${NC}"
    exit 1
fi

# Check if this is an existing installation
if [ ! -d "$INSTALL_DIR" ]; then
    echo -e "${RED}ERROR: No existing installation found at $INSTALL_DIR${NC}"
    echo "Use deploy.sh for fresh installations."
    exit 1
fi

if [ ! -f "$DB_FILE" ]; then
    echo -e "${RED}ERROR: No database found at $DB_FILE${NC}"
    echo "Use deploy.sh for fresh installations."
    exit 1
fi

# Check if new release exists
if [ ! -d "$SCRIPT_DIR/pou_con" ]; then
    echo -e "${RED}ERROR: New release not found in $SCRIPT_DIR/pou_con${NC}"
    exit 1
fi

# Show current installation info
echo -e "${CYAN}Current Installation:${NC}"
echo "  Install dir: $INSTALL_DIR"
echo "  Database:    $DB_FILE"
if [ -f /etc/pou_con/house_id ]; then
    HOUSE_ID=$(cat /etc/pou_con/house_id)
    echo "  House ID:    $HOUSE_ID"
fi
echo ""

# Confirm update
read -p "Proceed with update? (Y/n): " confirm
if [[ "$confirm" =~ ^[Nn]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""

#═══════════════════════════════════════════
# STEP 1: Stop Service
#═══════════════════════════════════════════
echo "1. Stopping PouCon service..."
if systemctl is-active --quiet pou_con; then
    systemctl stop pou_con
    echo "   ✓ Service stopped"
else
    echo "   ⚠ Service was not running"
fi

#═══════════════════════════════════════════
# STEP 2: Backup Database
#═══════════════════════════════════════════
echo "2. Backing up database..."
mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/pou_con_pre_update_$TIMESTAMP.db"
cp "$DB_FILE" "$BACKUP_FILE"
echo "   ✓ Backup created: $BACKUP_FILE"
echo "   ✓ Size: $(du -h "$BACKUP_FILE" | cut -f1)"

#═══════════════════════════════════════════
# STEP 3: Update Application Files
#═══════════════════════════════════════════
echo "3. Updating application files..."

# Remove old release files but keep data directory structure
# We preserve anything that might have been customized
rm -rf "$INSTALL_DIR/bin"
rm -rf "$INSTALL_DIR/lib"
rm -rf "$INSTALL_DIR/releases"
rm -rf "$INSTALL_DIR/erts-"*

# Copy new release
cp -r "$SCRIPT_DIR/pou_con/"* "$INSTALL_DIR/"

# Fix ownership
chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"

echo "   ✓ Application files updated"

#═══════════════════════════════════════════
# STEP 4: Re-enable Port Binding
#═══════════════════════════════════════════
echo "4. Re-enabling privileged port binding..."
if ls "$INSTALL_DIR"/erts-*/bin/beam.smp 1> /dev/null 2>&1; then
    setcap 'cap_net_bind_service=+ep' "$INSTALL_DIR"/erts-*/bin/beam.smp
    echo "   ✓ Port binding enabled"
else
    echo "   ⚠ beam.smp not found - may need manual setcap"
fi

#═══════════════════════════════════════════
# STEP 5: Run Database Migrations
#═══════════════════════════════════════════
echo "5. Running database migrations..."

# Get SECRET_KEY_BASE from systemd service
SECRET_KEY=$(grep -oP 'SECRET_KEY_BASE=\K[^"]+' /etc/systemd/system/pou_con.service 2>/dev/null || echo "")

if [ -z "$SECRET_KEY" ]; then
    echo -e "   ${RED}ERROR: Could not find SECRET_KEY_BASE in systemd service${NC}"
    echo "   Attempting to start without migrations..."
else
    cd "$INSTALL_DIR"
    if sudo -u "$SERVICE_USER" DATABASE_PATH="$DB_FILE" SECRET_KEY_BASE="$SECRET_KEY" ./bin/pou_con eval "PouCon.Release.migrate" 2>&1; then
        echo "   ✓ Migrations completed"
    else
        echo -e "   ${YELLOW}⚠ Migration returned non-zero (may be OK if no new migrations)${NC}"
    fi
fi

#═══════════════════════════════════════════
# STEP 6: Start Service
#═══════════════════════════════════════════
echo "6. Starting PouCon service..."
systemctl start pou_con
sleep 3

if systemctl is-active --quiet pou_con; then
    echo -e "   ${GREEN}✓ Service started successfully!${NC}"
else
    echo -e "   ${RED}⚠ Service may not have started${NC}"
    echo "   Check: sudo journalctl -u pou_con -n 50"
fi

#═══════════════════════════════════════════
# STEP 7: Cleanup old backups (keep last 10)
#═══════════════════════════════════════════
echo "7. Cleaning up old backups..."
ls -t "$BACKUP_DIR"/pou_con_pre_update_*.db 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null || true
BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/pou_con_pre_update_*.db 2>/dev/null | wc -l)
echo "   ✓ Keeping $BACKUP_COUNT most recent backups"

#═══════════════════════════════════════════
# DONE
#═══════════════════════════════════════════
echo ""
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo -e "${GREEN}  Update Complete!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo ""
echo "  Backup saved: $BACKUP_FILE"
echo ""
echo "  To verify:"
echo "    sudo systemctl status pou_con"
echo "    sudo journalctl -u pou_con -f"
echo ""
echo "  To rollback if needed:"
echo "    sudo systemctl stop pou_con"
echo "    cp $BACKUP_FILE $DB_FILE"
echo "    sudo systemctl start pou_con"
echo ""

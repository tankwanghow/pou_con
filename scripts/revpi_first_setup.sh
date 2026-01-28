#!/bin/bash
# First-time setup script for PouCon on RevPi Connect 5
# Run this script ON the RevPi after a fresh OS installation
# This prepares the system before deploying PouCon

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

print_step() {
    echo -e "${GREEN}==>${NC} $1"
}

print_info() {
    echo -e "${CYAN}   →${NC} $1"
}

echo ""
echo "═══════════════════════════════════════════"
echo "  PouCon RevPi Connect 5 First-Time Setup"
echo "  For RevPi OS (Debian Bookworm 64-bit)"
echo "═══════════════════════════════════════════"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root (use sudo)${NC}"
    exit 1
fi

# Detect hardware
print_step "Detecting hardware..."
if [ -f /proc/device-tree/model ]; then
    MODEL=$(cat /proc/device-tree/model | tr '\0' ' ')
    echo "   Model: $MODEL"
else
    echo "   Model: Unknown"
fi

# Check if this is a RevPi
IS_REVPI=false
if [ -f /etc/revpi/config.rsc ] || grep -q "RevPi" /proc/device-tree/model 2>/dev/null; then
    IS_REVPI=true
    echo -e "   ${GREEN}✓ RevPi detected${NC}"
elif grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null; then
    echo -e "   ${YELLOW}⚠ Raspberry Pi detected (compatible, but not RevPi)${NC}"
else
    echo -e "   ${YELLOW}⚠ Unknown hardware (may still work)${NC}"
fi

#═══════════════════════════════════════════
# 1. System Update
#═══════════════════════════════════════════
echo ""
print_step "Updating system packages..."
apt-get update -qq
apt-get upgrade -y -qq
echo "   ✓ System updated"

#═══════════════════════════════════════════
# 2. Install Dependencies
#═══════════════════════════════════════════
print_step "Installing system dependencies..."
apt-get install -y -qq \
    sqlite3 \
    libsqlite3-dev \
    openssl \
    libcap2-bin \
    curl \
    ca-certificates
echo "   ✓ Dependencies installed"
echo "   (Erlang not required - release includes embedded runtime)"

#═══════════════════════════════════════════
# 3. Configure RS485 (if RevPi RS485 variant)
#═══════════════════════════════════════════
print_step "Configuring serial interfaces..."

# Check for built-in RS485
if $IS_REVPI && [ -e /dev/ttyAMA0 ]; then
    echo "   ✓ Built-in RS485 detected at /dev/ttyAMA0"

    # Ensure UART is enabled
    if ! grep -q "^enable_uart=1" /boot/config.txt 2>/dev/null; then
        echo "enable_uart=1" >> /boot/config.txt
        echo "   ✓ UART enabled in /boot/config.txt"
    fi
else
    print_info "No built-in RS485 detected"
    print_info "Use USB RS485 adapter (will appear as /dev/ttyUSB0)"
fi

# Check for USB serial adapters
USB_COUNT=$(ls -1 /dev/ttyUSB* 2>/dev/null | wc -l)
if [ "$USB_COUNT" -gt 0 ]; then
    echo "   ✓ Found $USB_COUNT USB serial adapter(s)"
    ls -la /dev/ttyUSB* 2>/dev/null | while read line; do
        echo "      $line"
    done
fi

#═══════════════════════════════════════════
# 4. Configure Networking
#═══════════════════════════════════════════
print_step "Network configuration..."

# Display current network status
echo "   Current network interfaces:"
for IFACE in $(ip -o link show | awk -F': ' '{print $2}' | grep -v lo); do
    IP_ADDR=$(ip -4 addr show "$IFACE" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    if [ -n "$IP_ADDR" ]; then
        echo "      $IFACE: $IP_ADDR"
    else
        echo "      $IFACE: no IP"
    fi
done

# RevPi Connect 5 has dual Ethernet - suggest configuration
if $IS_REVPI; then
    echo ""
    print_info "RevPi Connect 5 has dual Ethernet ports:"
    print_info "  - eth0: Use for control network (Modbus devices)"
    print_info "  - eth1: Use for management (web UI access)"
fi

#═══════════════════════════════════════════
# 5. Time Configuration
#═══════════════════════════════════════════
print_step "Configuring time synchronization..."

# Enable NTP
timedatectl set-ntp true 2>/dev/null || true

# Set timezone (prompt user)
CURRENT_TZ=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "UTC")
echo "   Current timezone: $CURRENT_TZ"
echo ""
read -p "   Set timezone? (enter timezone or press Enter to keep current): " NEW_TZ

if [ -n "$NEW_TZ" ]; then
    if timedatectl set-timezone "$NEW_TZ" 2>/dev/null; then
        echo "   ✓ Timezone set to $NEW_TZ"
    else
        echo -e "   ${YELLOW}⚠ Invalid timezone, keeping $CURRENT_TZ${NC}"
    fi
else
    echo "   ✓ Keeping timezone: $CURRENT_TZ"
fi

#═══════════════════════════════════════════
# 6. Create pou_con User
#═══════════════════════════════════════════
print_step "Creating application user..."

if ! id "pou_con" &>/dev/null; then
    # Create as regular user with home directory (needed for kiosk/desktop)
    useradd -m -s /bin/bash -d /home/pou_con pou_con
    # Set a random password (user won't need to login with password - auto-login)
    echo "pou_con:$(openssl rand -base64 32)" | chpasswd
    echo "   ✓ User pou_con created with home directory"
else
    echo "   ✓ User pou_con already exists"
    # Ensure home directory exists for existing user
    if [ ! -d "/home/pou_con" ]; then
        mkdir -p /home/pou_con
        chown pou_con:pou_con /home/pou_con
        echo "   ✓ Created missing home directory"
    fi
fi

# Add to required groups for hardware and display access
usermod -a -G dialout pou_con   # Serial ports (Modbus RTU)
usermod -a -G video pou_con     # Backlight control (screen blanking)
usermod -a -G input pou_con     # Touchscreen input
usermod -a -G render pou_con 2>/dev/null || true  # GPU access
usermod -a -G audio pou_con 2>/dev/null || true   # Audio (for alerts)
echo "   ✓ Added pou_con to required groups"

#═══════════════════════════════════════════
# 7. Create Directory Structure
#═══════════════════════════════════════════
print_step "Creating directory structure..."

mkdir -p /opt/pou_con
mkdir -p /var/lib/pou_con
mkdir -p /var/log/pou_con
mkdir -p /var/backups/pou_con
mkdir -p /etc/pou_con/ssl

chown -R pou_con:pou_con /opt/pou_con
chown -R pou_con:pou_con /var/lib/pou_con
chown -R pou_con:pou_con /var/log/pou_con
chmod 755 /etc/pou_con

echo "   ✓ Directories created"

#═══════════════════════════════════════════
# 8. Configure Log Rotation
#═══════════════════════════════════════════
print_step "Setting up log rotation..."

cat > /etc/logrotate.d/pou_con << 'EOF'
/var/log/pou_con/*.log {
    daily
    rotate 7
    compress
    delaycompress
    notifempty
    create 0644 pou_con pou_con
    sharedscripts
    postrotate
        systemctl reload pou_con > /dev/null 2>&1 || true
    endscript
}
EOF

echo "   ✓ Log rotation configured"

#═══════════════════════════════════════════
# 9. System Performance Tuning
#═══════════════════════════════════════════
print_step "Applying performance optimizations..."

# Increase file descriptor limits for BEAM
if ! grep -q "pou_con" /etc/security/limits.conf; then
    cat >> /etc/security/limits.conf << 'EOF'
# PouCon file descriptor limits
pou_con soft nofile 65536
pou_con hard nofile 65536
EOF
    echo "   ✓ File descriptor limits increased"
fi

# Optimize for industrial use (reduce swappiness)
if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
    echo "vm.swappiness=10" >> /etc/sysctl.conf
    sysctl -p > /dev/null 2>&1
    echo "   ✓ Swappiness reduced for better performance"
fi

#═══════════════════════════════════════════
# 10. RevPi-Specific Setup
#═══════════════════════════════════════════
if $IS_REVPI; then
    print_step "RevPi-specific configuration..."

    # Check for piControl driver
    if lsmod | grep -q piControl; then
        echo "   ✓ piControl driver loaded"
    else
        print_info "piControl driver not loaded (no I/O modules connected)"
    fi

    # Set up watchdog (optional but recommended for industrial)
    if [ -e /dev/watchdog ]; then
        echo "   ✓ Hardware watchdog available"
        print_info "Consider enabling watchdog for production"
    fi
fi

#═══════════════════════════════════════════
# 11. Display System Info
#═══════════════════════════════════════════
echo ""
print_step "System Information:"
echo "   OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo "   Arch: $(uname -m)"
echo "   CPU: $(nproc) cores"
echo "   Memory: $(free -h | awk '/^Mem:/ {print $2}')"
echo "   Disk Free: $(df -h / | awk 'NR==2 {print $4}')"
echo ""

#═══════════════════════════════════════════
# 12. Serial Port Summary
#═══════════════════════════════════════════
print_step "Available serial ports:"
echo "   Built-in:"
ls -la /dev/ttyAMA* /dev/serial* 2>/dev/null | while read line; do
    echo "      $line"
done || echo "      None detected"

echo "   USB adapters:"
ls -la /dev/ttyUSB* 2>/dev/null | while read line; do
    echo "      $line"
done || echo "      None connected"

echo ""

#═══════════════════════════════════════════
# Done!
#═══════════════════════════════════════════
echo ""
echo "═══════════════════════════════════════════"
echo -e "${GREEN}  First-Time Setup Complete!${NC}"
echo "═══════════════════════════════════════════"
echo ""
echo -e "${YELLOW}NEXT STEPS:${NC}"
echo ""
echo "  1. Transfer deployment package to this device:"
echo "     scp pou_con_deployment_*.tar.gz pi@$(hostname -I | awk '{print $1}'):/tmp/"
echo ""
echo "  2. Extract and deploy:"
echo "     cd /tmp"
echo "     tar -xzf pou_con_deployment_*.tar.gz"
echo "     cd deployment_package_*/"
echo "     sudo ./deploy.sh"
echo ""
echo "  3. Follow prompts (enter house_id, confirm)"
echo ""
echo "  4. Access: https://poucon.<house_id>"
echo ""
echo "═══════════════════════════════════════════"
echo ""

# Recommend reboot if kernel was updated
if [ -f /var/run/reboot-required ]; then
    echo -e "${YELLOW}⚠ Reboot required for kernel updates${NC}"
    echo "   Run: sudo reboot"
    echo ""
fi

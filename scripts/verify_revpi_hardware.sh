#!/bin/bash
# Hardware verification script for RevPi Connect 5
# Run this before deploying PouCon to ensure hardware is properly configured

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

print_ok() { echo -e "   ${GREEN}✓${NC} $1"; }
print_warn() { echo -e "   ${YELLOW}⚠${NC} $1"; }
print_fail() { echo -e "   ${RED}✗${NC} $1"; }
print_info() { echo -e "   ${CYAN}→${NC} $1"; }

ERRORS=0
WARNINGS=0

echo ""
echo "═══════════════════════════════════════════"
echo "  RevPi Connect 5 Hardware Verification"
echo "═══════════════════════════════════════════"
echo ""

#═══════════════════════════════════════════
# 1. System Information
#═══════════════════════════════════════════
echo -e "${CYAN}1. System Information${NC}"

# Detect if this is a RevPi
IS_REVPI=false
if [ -f /etc/revpi/config.rsc ] || grep -q "RevPi" /proc/device-tree/model 2>/dev/null; then
    IS_REVPI=true
fi

# Get model
if [ -f /proc/device-tree/model ]; then
    MODEL=$(cat /proc/device-tree/model | tr '\0' ' ')
    print_ok "Model: $MODEL"
else
    MODEL="Unknown"
    print_warn "Could not detect model"
    ((WARNINGS++))
fi

# Check if RevPi or compatible
if $IS_REVPI; then
    print_ok "RevPi detected"
elif grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null; then
    print_warn "Raspberry Pi detected (not RevPi, but compatible)"
    ((WARNINGS++))
else
    print_warn "Unknown hardware (may still work if Debian-based)"
    ((WARNINGS++))
fi

# CPU info
CPU_CORES=$(nproc)
CPU_MODEL=$(lscpu | grep "Model name" | cut -d: -f2 | xargs)
print_ok "CPU: $CPU_MODEL ($CPU_CORES cores)"

# RAM
RAM_TOTAL=$(free -h | awk '/^Mem:/ {print $2}')
RAM_AVAILABLE=$(free -h | awk '/^Mem:/ {print $7}')
print_ok "RAM: $RAM_TOTAL total, $RAM_AVAILABLE available"

# Check minimum RAM (2GB)
RAM_MB=$(free -m | awk '/^Mem:/ {print $2}')
if [ "$RAM_MB" -lt 2000 ]; then
    print_fail "RAM below 2GB - may cause performance issues"
    ((ERRORS++))
fi

# OS
OS_NAME=$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2)
print_ok "OS: $OS_NAME"

# Kernel
KERNEL=$(uname -r)
print_ok "Kernel: $KERNEL"

# Check for real-time kernel
if uname -r | grep -q "rt\|preempt"; then
    print_ok "Real-time kernel detected"
fi

echo ""

#═══════════════════════════════════════════
# 2. Serial Ports
#═══════════════════════════════════════════
echo -e "${CYAN}2. Serial Ports${NC}"

SERIAL_FOUND=0

# Check built-in UART (RevPi RS485 variant)
if [ -e /dev/ttyAMA0 ]; then
    print_ok "/dev/ttyAMA0 - Built-in UART available"
    ((SERIAL_FOUND++))

    # Check if it's RS485 capable (RevPi RS485 variant)
    if $IS_REVPI && [ -e /sys/class/tty/ttyAMA0/device/of_node/rs485-rts-delay ]; then
        print_info "  RS485 mode supported (auto direction control)"
    fi
elif [ -e /dev/serial0 ]; then
    print_ok "/dev/serial0 - Built-in serial available"
    ((SERIAL_FOUND++))
else
    print_info "/dev/ttyAMA0 not found (normal if not RS485 variant)"
fi

# Check USB serial adapters
for USB_PORT in /dev/ttyUSB*; do
    if [ -e "$USB_PORT" ]; then
        # Get device info
        USB_INFO=$(udevadm info --query=property "$USB_PORT" 2>/dev/null | grep ID_MODEL= | cut -d= -f2)
        if [ -n "$USB_INFO" ]; then
            print_ok "$USB_PORT - USB Serial: $USB_INFO"
        else
            print_ok "$USB_PORT - USB Serial Adapter"
        fi
        ((SERIAL_FOUND++))
    fi
done

# Check for ACM devices (some USB converters)
for ACM_PORT in /dev/ttyACM*; do
    if [ -e "$ACM_PORT" ]; then
        print_ok "$ACM_PORT - USB ACM Device"
        ((SERIAL_FOUND++))
    fi
done

if [ $SERIAL_FOUND -eq 0 ]; then
    print_fail "No serial ports found!"
    print_info "Connect RS485 USB adapter or use RevPi RS485 variant"
    ((ERRORS++))
else
    print_ok "$SERIAL_FOUND serial port(s) detected"
fi

# Check dialout group
DIALOUT_MEMBERS=$(getent group dialout | cut -d: -f4)
print_info "dialout group members: ${DIALOUT_MEMBERS:-none}"

echo ""

#═══════════════════════════════════════════
# 3. Network Interfaces
#═══════════════════════════════════════════
echo -e "${CYAN}3. Network Interfaces${NC}"

# Get network interfaces
for IFACE in $(ip -o link show | awk -F': ' '{print $2}' | grep -v lo); do
    IP_ADDR=$(ip -4 addr show "$IFACE" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}/\d+' | head -1)
    LINK_STATE=$(cat /sys/class/net/"$IFACE"/operstate 2>/dev/null)

    if [ -n "$IP_ADDR" ]; then
        print_ok "$IFACE: $IP_ADDR ($LINK_STATE)"
    elif [ "$LINK_STATE" = "up" ]; then
        print_warn "$IFACE: no IP address ($LINK_STATE)"
    else
        print_info "$IFACE: $LINK_STATE"
    fi
done

# Check for dual Ethernet (RevPi Connect 5 feature)
ETH_COUNT=$(ip -o link show | grep -c "eth[0-9]")
if [ "$ETH_COUNT" -ge 2 ]; then
    print_ok "Dual Ethernet detected (RevPi Connect 5 feature)"
fi

echo ""

#═══════════════════════════════════════════
# 4. Storage
#═══════════════════════════════════════════
echo -e "${CYAN}4. Storage${NC}"

# Root filesystem
ROOT_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
ROOT_FREE=$(df -h / | awk 'NR==2 {print $4}')
ROOT_PERCENT=$(df -h / | awk 'NR==2 {print $5}')
print_ok "Root filesystem: $ROOT_TOTAL total, $ROOT_FREE free ($ROOT_PERCENT used)"

# Check for eMMC (RevPi typically has eMMC)
if [ -e /dev/mmcblk0 ]; then
    if [ -e /dev/mmcblk0boot0 ]; then
        print_ok "eMMC storage detected (more reliable than SD)"
    else
        print_ok "SD card storage detected"
    fi
fi

# Check minimum free space (1GB)
FREE_MB=$(df -m / | awk 'NR==2 {print $4}')
if [ "$FREE_MB" -lt 1000 ]; then
    print_warn "Low disk space: ${FREE_MB}MB free"
    ((WARNINGS++))
fi

# Check for /var/lib/pou_con (data directory)
if [ -d /var/lib/pou_con ]; then
    DATA_SIZE=$(du -sh /var/lib/pou_con 2>/dev/null | cut -f1)
    print_ok "PouCon data directory exists: $DATA_SIZE"
fi

echo ""

#═══════════════════════════════════════════
# 5. RevPi-Specific Checks
#═══════════════════════════════════════════
echo -e "${CYAN}5. RevPi-Specific Features${NC}"

if $IS_REVPI; then
    # Check PiBridge (RevPi I/O expansion bus)
    if [ -e /dev/piControl0 ]; then
        print_ok "PiBridge control device available"

        # Check for connected I/O modules
        if command -v piTest &> /dev/null; then
            MODULE_COUNT=$(piTest -d 2>/dev/null | grep -c "device" || echo "0")
            print_info "PiBridge modules detected: $MODULE_COUNT"
        fi
    else
        print_info "PiBridge not available (no I/O modules connected)"
    fi

    # Check RS485 configuration
    if grep -q "rs485" /boot/config.txt 2>/dev/null; then
        print_ok "RS485 enabled in boot config"
    fi

    # Check KUNBUS piControl driver
    if lsmod | grep -q piControl; then
        print_ok "piControl kernel module loaded"
    fi
else
    print_info "RevPi-specific checks skipped (not a RevPi)"
fi

echo ""

#═══════════════════════════════════════════
# 6. System Services
#═══════════════════════════════════════════
echo -e "${CYAN}6. System Services${NC}"

# Check if PouCon is already installed
if systemctl list-unit-files | grep -q pou_con; then
    STATUS=$(systemctl is-active pou_con 2>/dev/null || echo "unknown")
    if [ "$STATUS" = "active" ]; then
        print_ok "PouCon service: running"
    elif [ "$STATUS" = "inactive" ]; then
        print_info "PouCon service: stopped"
    else
        print_info "PouCon service: $STATUS"
    fi
else
    print_info "PouCon service: not installed (expected for fresh deployment)"
fi

# Check time sync
if timedatectl show 2>/dev/null | grep -q "NTPSynchronized=yes"; then
    print_ok "Time synchronized via NTP"
else
    print_warn "Time not synchronized (NTP disabled or no network)"
    ((WARNINGS++))
fi

# Check RTC (real-time clock)
if [ -e /dev/rtc0 ]; then
    print_ok "Hardware RTC available"
else
    print_info "No hardware RTC (relies on NTP)"
fi

echo ""

#═══════════════════════════════════════════
# 7. Required Tools
#═══════════════════════════════════════════
echo -e "${CYAN}7. Required Tools${NC}"

for TOOL in openssl sqlite3; do
    if command -v $TOOL &> /dev/null; then
        VERSION=$($TOOL --version 2>/dev/null | head -1 || echo "installed")
        print_ok "$TOOL: $VERSION"
    else
        print_fail "$TOOL: not installed"
        ((ERRORS++))
    fi
done

# Check for setcap (needed for port 80/443 binding)
if command -v setcap &> /dev/null; then
    print_ok "setcap: available (for privileged ports)"
else
    print_warn "setcap: not found (install libcap2-bin)"
    ((WARNINGS++))
fi

echo ""

#═══════════════════════════════════════════
# Summary
#═══════════════════════════════════════════
echo "═══════════════════════════════════════════"

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "  ${GREEN}All checks passed - ready for deployment${NC}"
elif [ $ERRORS -eq 0 ]; then
    echo -e "  ${YELLOW}$WARNINGS warning(s) - deployment should work${NC}"
else
    echo -e "  ${RED}$ERRORS error(s), $WARNINGS warning(s)${NC}"
    echo -e "  ${RED}Please resolve errors before deployment${NC}"
fi

echo "═══════════════════════════════════════════"
echo ""

# Recommendations
if [ $SERIAL_FOUND -eq 0 ]; then
    echo "NEXT STEPS:"
    echo "  1. Connect RS485 USB adapter, or"
    echo "  2. Use RevPi Connect 5 RS485 variant with built-in RS485"
    echo ""
fi

if [ $ERRORS -gt 0 ]; then
    exit 1
fi

exit 0

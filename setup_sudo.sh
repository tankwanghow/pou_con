#!/bin/bash
# Setup passwordless sudo for pou_con service user
# This enables web-based system time management and screen control

set -e

SERVICE_USER="pou_con"
SUDOERS_FILE="/etc/sudoers.d/pou_con"

echo "=== PouCon Sudo Configuration ==="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Please run as root (use sudo)"
    exit 1
fi

# Check if user exists
if ! id "$SERVICE_USER" &>/dev/null; then
    echo "ERROR: User '$SERVICE_USER' does not exist"
    echo "Run the deployment script first to create the user"
    exit 1
fi

echo "Configuring passwordless sudo for $SERVICE_USER..."

# Create sudoers file with specific command permissions
cat > "$SUDOERS_FILE" << 'EOF'
# PouCon service user sudo permissions
# This file allows the pou_con user to run specific system commands
# without a password, enabling web-based administration.

# System time management (for RTC battery failure recovery)
pou_con ALL=(ALL) NOPASSWD: /usr/bin/date
pou_con ALL=(ALL) NOPASSWD: /usr/sbin/hwclock
pou_con ALL=(ALL) NOPASSWD: /usr/bin/timedatectl

# System management (reboot, shutdown from web UI)
pou_con ALL=(ALL) NOPASSWD: /usr/sbin/reboot
pou_con ALL=(ALL) NOPASSWD: /usr/sbin/shutdown
pou_con ALL=(ALL) NOPASSWD: /usr/bin/systemctl reboot
pou_con ALL=(ALL) NOPASSWD: /usr/bin/systemctl poweroff
EOF

# Set correct permissions (required for sudoers files)
chmod 440 "$SUDOERS_FILE"
chown root:root "$SUDOERS_FILE"

# Validate sudoers file
if visudo -c -f "$SUDOERS_FILE" > /dev/null 2>&1; then
    echo "   ✓ Sudoers file validated"
else
    echo "ERROR: Invalid sudoers file syntax"
    rm -f "$SUDOERS_FILE"
    exit 1
fi

echo ""
echo "=== Configuration Complete ==="
echo ""
echo "The $SERVICE_USER user can now run these commands without password:"
echo "  - sudo date -s \"YYYY-MM-DD HH:MM:SS\"  (set system time)"
echo "  - sudo hwclock --systohc              (sync hardware clock)"
echo "  - sudo timedatectl set-ntp true       (enable NTP)"
echo "  - sudo reboot                         (restart system)"
echo "  - sudo shutdown -h now                (power off)"
echo ""
echo "These permissions enable:"
echo "  - Web-based time setting (Admin -> System Time)"
echo "  - Web-based system reboot (Admin -> System Management)"
echo ""

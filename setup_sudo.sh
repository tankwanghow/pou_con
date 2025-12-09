#!/bin/bash
# Setup passwordless sudo for PouCon time management
# Run this once during deployment: sudo bash setup_sudo.sh

echo "Setting up passwordless sudo for PouCon system time management..."

# Determine the user running the Phoenix application
# In production, this is typically the deployment user (pi, ubuntu, etc.)
# In development, it's the current user
if [ "$SUDO_USER" != "" ]; then
    APP_USER="$SUDO_USER"
else
    APP_USER=$(whoami)
fi

echo "Configuring sudo for user: $APP_USER"

# Create sudoers file for PouCon
SUDOERS_FILE="/etc/sudoers.d/poucon-time"

cat > /tmp/poucon-time << EOF
# PouCon System Time Management
# Allows the application user to set system time without password
# Required for RTC battery failure recovery

# Allow setting system time
$APP_USER ALL=(ALL) NOPASSWD: /bin/date
$APP_USER ALL=(ALL) NOPASSWD: /usr/bin/date

# Allow syncing hardware clock
$APP_USER ALL=(ALL) NOPASSWD: /sbin/hwclock
$APP_USER ALL=(ALL) NOPASSWD: /usr/sbin/hwclock

# Allow timedatectl for NTP management
$APP_USER ALL=(ALL) NOPASSWD: /bin/timedatectl
$APP_USER ALL=(ALL) NOPASSWD: /usr/bin/timedatectl
EOF

# Move to sudoers.d with correct permissions
mv /tmp/poucon-time "$SUDOERS_FILE"
chmod 0440 "$SUDOERS_FILE"
chown root:root "$SUDOERS_FILE"

# Validate sudoers syntax
if visudo -c -f "$SUDOERS_FILE" > /dev/null 2>&1; then
    echo "✓ Sudoers configuration created successfully: $SUDOERS_FILE"
    echo "✓ User '$APP_USER' can now set system time without password"
    echo ""
    echo "Test with:"
    echo "  sudo date -s '2025-12-09 14:30:00'"
    echo "  sudo hwclock --systohc"
else
    echo "✗ Error: Sudoers configuration is invalid!"
    rm -f "$SUDOERS_FILE"
    exit 1
fi

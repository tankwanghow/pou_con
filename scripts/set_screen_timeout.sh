#!/bin/bash
# Set screen blank timeout for labwc/swayidle
# Called by PouCon app to configure screen blanking
#
# Usage: set_screen_timeout.sh <seconds>
#   seconds: 0 = disable, or timeout in seconds (60-3600)
#
# This script updates ~/.config/labwc/autostart for the display user

set -e

TIMEOUT_SECONDS="${1:-0}"
DISPLAY_USER="${2:-pi}"
AUTOSTART_FILE="/home/$DISPLAY_USER/.config/labwc/autostart"
BACKLIGHT_PATH="/sys/class/backlight/lcd_backlight/brightness"
MAX_BRIGHTNESS="5"

# Validate input
if ! [[ "$TIMEOUT_SECONDS" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Invalid timeout value: $TIMEOUT_SECONDS"
    exit 1
fi

if [ "$TIMEOUT_SECONDS" -gt 3600 ]; then
    echo "ERROR: Timeout cannot exceed 3600 seconds (1 hour)"
    exit 1
fi

# Ensure directory exists
mkdir -p "$(dirname "$AUTOSTART_FILE")"

# Check if autostart file exists
if [ ! -f "$AUTOSTART_FILE" ]; then
    # Create new autostart file
    touch "$AUTOSTART_FILE"
    chown "$DISPLAY_USER:$DISPLAY_USER" "$AUTOSTART_FILE"
fi

# Remove existing swayidle line(s)
if grep -q "swayidle" "$AUTOSTART_FILE" 2>/dev/null; then
    sed -i '/swayidle/d' "$AUTOSTART_FILE"
fi

# Add new swayidle configuration if timeout > 0
if [ "$TIMEOUT_SECONDS" -gt 0 ]; then
    # Use backlight control for reliable blanking on reTerminal DM
    echo "swayidle -w timeout $TIMEOUT_SECONDS 'echo 0 > $BACKLIGHT_PATH' resume 'echo $MAX_BRIGHTNESS > $BACKLIGHT_PATH' &" >> "$AUTOSTART_FILE"
    echo "Screen timeout set to $TIMEOUT_SECONDS seconds"
else
    echo "Screen timeout disabled (always on)"
fi

# Restart swayidle if running (to apply changes immediately)
if pgrep -u "$DISPLAY_USER" swayidle > /dev/null 2>&1; then
    pkill -u "$DISPLAY_USER" swayidle || true
    sleep 1

    # Start new swayidle if timeout > 0
    if [ "$TIMEOUT_SECONDS" -gt 0 ]; then
        sudo -u "$DISPLAY_USER" sh -c "swayidle -w timeout $TIMEOUT_SECONDS 'echo 0 > $BACKLIGHT_PATH' resume 'echo $MAX_BRIGHTNESS > $BACKLIGHT_PATH' &" 2>/dev/null || true
        echo "swayidle restarted with new timeout"
    else
        echo "swayidle stopped (screen always on)"
    fi
fi

echo "Done. Changes will persist after reboot."

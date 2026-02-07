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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if swayidle is installed
# NOTE: Do NOT attempt inline install here - this script is called from the web UI
# with a short timeout. Install swayidle via: sudo bash setup_sudo.sh
SWAYIDLE_AVAILABLE=true
if ! command -v swayidle &> /dev/null; then
    SWAYIDLE_AVAILABLE=false
    echo "WARNING: swayidle not installed. Run 'sudo bash setup_sudo.sh' to install it."
    echo "Autostart config will be updated but screen timeout won't work until swayidle is installed."
fi
DISPLAY_USER="${2:-pi}"
AUTOSTART_FILE="/home/$DISPLAY_USER/.config/labwc/autostart"

# Auto-detect backlight device (different hardware uses different paths)
BACKLIGHT_PATH=""
MAX_BRIGHTNESS="5"
for bl in lcd_backlight 10-0045 rpi_backlight backlight; do
    if [ -f "/sys/class/backlight/$bl/brightness" ]; then
        BACKLIGHT_PATH="/sys/class/backlight/$bl/brightness"
        MAX_BRIGHTNESS=$(cat "/sys/class/backlight/$bl/max_brightness" 2>/dev/null || echo "5")
        break
    fi
done

if [ -z "$BACKLIGHT_PATH" ]; then
    echo "WARNING: No backlight device found. Screen blanking may not work."
    # Use a default path anyway for the config file
    BACKLIGHT_PATH="/sys/class/backlight/lcd_backlight/brightness"
fi

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
    # Use backlight control scripts for reliable blanking on reTerminal DM
    echo "swayidle -w timeout $TIMEOUT_SECONDS '$SCRIPT_DIR/off_screen.sh' resume '$SCRIPT_DIR/on_screen.sh' &" >> "$AUTOSTART_FILE"
    echo "Screen timeout set to $TIMEOUT_SECONDS seconds"
else
    echo "Screen timeout disabled (always on)"
fi

# Only manage swayidle process if it's installed
if [ "$SWAYIDLE_AVAILABLE" = true ]; then
    # Stop existing swayidle if running
    if pgrep -u "$DISPLAY_USER" swayidle > /dev/null 2>&1; then
        pkill -u "$DISPLAY_USER" swayidle || true
        sleep 1
        echo "Stopped existing swayidle"
    fi

    # Start swayidle if timeout > 0
    # Need to set Wayland environment variables to connect to the compositor
    if [ "$TIMEOUT_SECONDS" -gt 0 ]; then
        # Find the Wayland display socket
        XDG_RUNTIME="/run/user/$(id -u "$DISPLAY_USER")"
        WAYLAND_SOCK=$(ls "$XDG_RUNTIME"/wayland-* 2>/dev/null | head -1 | xargs basename 2>/dev/null || echo "wayland-0")

        if [ -S "$XDG_RUNTIME/$WAYLAND_SOCK" ]; then
            # Start swayidle with proper Wayland environment
            sudo -u "$DISPLAY_USER" \
                WAYLAND_DISPLAY="$WAYLAND_SOCK" \
                XDG_RUNTIME_DIR="$XDG_RUNTIME" \
                sh -c "swayidle -w timeout $TIMEOUT_SECONDS '$SCRIPT_DIR/off_screen.sh' resume '$SCRIPT_DIR/on_screen.sh' &" 2>/dev/null

            if pgrep -u "$DISPLAY_USER" swayidle > /dev/null 2>&1; then
                echo "swayidle started with ${TIMEOUT_SECONDS}s timeout"
            else
                echo "Note: swayidle configured but could not start immediately."
                echo "      It will start automatically on next login/reboot."
            fi
        else
            echo "Note: Wayland display not found. swayidle will start on next login/reboot."
        fi
    else
        echo "Screen timeout disabled (swayidle not running)"
    fi
fi

echo "Done. Configuration saved to $AUTOSTART_FILE"

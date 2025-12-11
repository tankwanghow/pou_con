#!/bin/bash
# Setup touchscreen kiosk mode for PouCon
# Run this on Raspberry Pi with touchscreen connected

set -e

echo "=== PouCon Touchscreen Kiosk Setup ==="
echo ""

# Check if running on Pi
if [ ! -f /proc/device-tree/model ]; then
    echo "WARNING: This script is designed for Raspberry Pi"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check if PouCon is installed
if [ ! -f /opt/pou_con/bin/pou_con ]; then
    echo "ERROR: PouCon not installed. Run deploy.sh first"
    exit 1
fi

# Check if running Raspberry Pi OS Desktop
if [ ! -d /usr/share/lightdm ]; then
    echo "ERROR: This script requires Raspberry Pi OS Desktop"
    echo "       For Raspberry Pi OS Lite, see TOUCHSCREEN_KIOSK_SETUP.md"
    exit 1
fi

echo "This will configure the Pi to boot directly to PouCon kiosk mode"
echo "on the connected touchscreen display."
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

# Install required packages
echo ""
echo "1. Installing required packages..."
sudo apt update
sudo apt install -y chromium-browser unclutter xdotool

# Create kiosk script directory
echo "2. Creating kiosk startup script..."
mkdir -p ~/.local/bin

cat > ~/.local/bin/start_poucon_kiosk.sh << 'EOF'
#!/bin/bash

# Wait for PouCon service to be ready
echo "Waiting for PouCon service..."
sleep 10

# Wait for PouCon to be actually responding
for i in {1..30}; do
    if curl -s http://localhost:4000 > /dev/null; then
        echo "PouCon is ready!"
        break
    fi
    echo "Waiting for PouCon to respond... ($i/30)"
    sleep 2
done

# Hide mouse cursor after 0.1 seconds of inactivity
unclutter -idle 0.1 -root &

# Disable screen blanking
xset s off
xset -dpms
xset s noblank

# Optional: Set brightness (uncomment and adjust for your panel)
# echo 200 | sudo tee /sys/class/backlight/*/brightness > /dev/null 2>&1

# Start Chromium in kiosk mode
chromium-browser \
  --kiosk \
  --noerrdialogs \
  --disable-infobars \
  --disable-session-crashed-bubble \
  --disable-translate \
  --no-first-run \
  --fast \
  --fast-start \
  --disable-features=TranslateUI \
  --disk-cache-dir=/dev/null \
  --overscroll-history-navigation=0 \
  --disable-pinch \
  http://localhost:4000
EOF

chmod +x ~/.local/bin/start_poucon_kiosk.sh

# Create autostart configuration
echo "3. Creating autostart configuration..."
mkdir -p ~/.config/autostart

cat > ~/.config/autostart/poucon-kiosk.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=PouCon Kiosk
Exec=/home/pi/.local/bin/start_poucon_kiosk.sh
X-GNOME-Autostart-enabled=true
EOF

# Disable screen saver
echo "4. Disabling screen saver..."
sudo mkdir -p /etc/X11/xorg.conf.d/
sudo cat > /etc/X11/xorg.conf.d/10-monitor.conf << 'EOF'
Section "ServerLayout"
    Identifier "ServerLayout0"
    Option "BlankTime"   "0"
    Option "StandbyTime" "0"
    Option "SuspendTime" "0"
    Option "OffTime"     "0"
EndSection
EOF

# Check and enable auto-login
echo "5. Checking auto-login configuration..."
if ! grep -q "^autologin-user=" /etc/lightdm/lightdm.conf 2>/dev/null; then
    echo "   Enabling auto-login..."
    sudo sed -i 's/^#autologin-user=/autologin-user=pi/' /etc/lightdm/lightdm.conf

    # If that didn't work, add it manually
    if ! grep -q "^autologin-user=" /etc/lightdm/lightdm.conf 2>/dev/null; then
        sudo sed -i '/^\[Seat:\*\]/a autologin-user=pi' /etc/lightdm/lightdm.conf
    fi
else
    echo "   Auto-login already enabled"
fi

# Verify touchscreen is detected
echo ""
echo "6. Verifying touchscreen detection..."
if xinput list | grep -iq touch; then
    echo "   ✓ Touchscreen detected"
    xinput list | grep -i touch
else
    echo "   ⚠ WARNING: No touchscreen detected"
    echo "   The kiosk will work with mouse/keyboard"
    echo "   For touchscreen setup, see TOUCHSCREEN_KIOSK_SETUP.md"
fi

echo ""
echo "=== Kiosk Setup Complete! ==="
echo ""
echo "Next steps:"
echo "  1. Reboot: sudo reboot"
echo "  2. Pi will boot directly to PouCon kiosk mode"
echo "  3. Touch screen to interact with controls"
echo ""
echo "To disable kiosk mode:"
echo "  rm ~/.config/autostart/poucon-kiosk.desktop"
echo "  rm ~/.local/bin/start_poucon_kiosk.sh"
echo ""
echo "To customize kiosk settings, edit:"
echo "  ~/.local/bin/start_poucon_kiosk.sh"
echo ""
echo "For troubleshooting, see TOUCHSCREEN_KIOSK_SETUP.md"

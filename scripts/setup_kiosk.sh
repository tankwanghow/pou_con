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

echo "This will configure the Pi to boot directly to PouCon in fullscreen mode"
echo "on the connected touchscreen display."
echo ""
echo "Keyboard shortcuts available after setup:"
echo "  F11       - Toggle fullscreen on/off"
echo "  Alt+Tab   - Switch between applications"
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
mkdir -p ~/.local/share/poucon

# Create loading page (black screen that auto-redirects when PouCon is ready)
cat > ~/.local/share/poucon/loading.html << 'HTMLEOF'
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Loading...</title>
  <style>
    * { margin: 0; padding: 0; }
    body {
      background: #000;
      height: 100vh;
      display: flex;
      justify-content: center;
      align-items: center;
      font-family: system-ui, sans-serif;
      color: #333;
    }
    .loader {
      text-align: center;
      opacity: 0;
      animation: fadeIn 2s ease-in 3s forwards;
    }
    .spinner {
      width: 40px;
      height: 40px;
      border: 3px solid #333;
      border-top-color: #666;
      border-radius: 50%;
      animation: spin 1s linear infinite;
      margin: 0 auto 16px;
    }
    @keyframes spin { to { transform: rotate(360deg); } }
    @keyframes fadeIn { to { opacity: 1; } }
  </style>
</head>
<body>
  <div class="loader">
    <div class="spinner"></div>
    <div>Starting PouCon...</div>
  </div>
  <script>
    const target = 'http://localhost';
    const maxAttempts = 60;
    let attempts = 0;

    function checkServer() {
      attempts++;
      fetch(target, { mode: 'no-cors' })
        .then(() => { window.location.href = target; })
        .catch(() => {
          if (attempts < maxAttempts) {
            setTimeout(checkServer, 2000);
          } else {
            document.body.innerHTML = '<div style="color:#c00;text-align:center;padding:20px;">Failed to connect to PouCon.<br>Please check the service.</div>';
          }
        });
    }

    // Start checking after a brief delay
    setTimeout(checkServer, 3000);
  </script>
</body>
</html>
HTMLEOF

cat > ~/.local/bin/start_poucon_kiosk.sh << 'EOF'
#!/bin/bash

# Hide mouse cursor after 0.1 seconds of inactivity
unclutter -idle 0.1 -root &

# Disable screen blanking
xset s off
xset -dpms
xset s noblank

# Optional: Set brightness (uncomment and adjust for your panel)
# echo 200 | sudo tee /sys/class/backlight/*/brightness > /dev/null 2>&1

# Start Chromium immediately with loading page (shows black screen)
# The loading page will auto-redirect to PouCon when it's ready
chromium-browser \
  --start-fullscreen \
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
  file://$HOME/.local/share/poucon/loading.html
EOF

chmod +x ~/.local/bin/start_poucon_kiosk.sh

# Create autostart configuration
echo "3. Creating autostart configuration..."
mkdir -p ~/.config/autostart

cat > ~/.config/autostart/poucon-kiosk.desktop << EOF
[Desktop Entry]
Type=Application
Name=PouCon Kiosk
Exec=$HOME/.local/bin/start_poucon_kiosk.sh
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
CURRENT_USER=$(whoami)
if ! grep -q "^autologin-user=" /etc/lightdm/lightdm.conf 2>/dev/null; then
    echo "   Enabling auto-login for user: $CURRENT_USER"
    sudo sed -i "s/^#autologin-user=/autologin-user=$CURRENT_USER/" /etc/lightdm/lightdm.conf

    # If that didn't work, add it manually
    if ! grep -q "^autologin-user=" /etc/lightdm/lightdm.conf 2>/dev/null; then
        sudo sed -i "/^\[Seat:\*\]/a autologin-user=$CURRENT_USER" /etc/lightdm/lightdm.conf
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
echo "  2. Pi will boot directly to PouCon in fullscreen"
echo "  3. Touch screen to interact with controls"
echo ""
echo "Keyboard shortcuts:"
echo "  F11       - Toggle fullscreen on/off"
echo "  Alt+Tab   - Switch between applications"
echo ""
echo "To disable kiosk mode:"
echo "  rm ~/.config/autostart/poucon-kiosk.desktop"
echo "  rm ~/.local/bin/start_poucon_kiosk.sh"
echo ""
echo "To customize settings, edit:"
echo "  ~/.local/bin/start_poucon_kiosk.sh"
echo ""
echo "For troubleshooting, see TOUCHSCREEN_KIOSK_SETUP.md"

#!/bin/bash
# Setup touchscreen kiosk mode for PouCon on Raspberry Pi OS Bookworm (Wayland/labwc)
# Run this on Raspberry Pi with touchscreen connected

set -e

echo "=== PouCon Touchscreen Kiosk Setup (Wayland) ==="
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
    echo "ERROR: PouCon not installed. Run deploy script first."
    exit 1
fi

# Check if labwc is installed (Wayland compositor for Raspberry Pi OS Bookworm)
if ! command -v labwc &> /dev/null; then
    echo "ERROR: labwc not installed."
    echo "       This script requires Raspberry Pi OS Bookworm Desktop."
    echo "       Install with: sudo apt install labwc"
    exit 1
fi

# Check if we're running in a graphical session or via SSH
if pgrep -x labwc > /dev/null 2>&1; then
    echo "Detected: labwc (Wayland) is running"
else
    echo "Note: labwc is installed but not currently running"
    echo "      (This is normal when running via SSH or before desktop starts)"
fi
echo ""
echo "This will configure the Pi to boot directly to PouCon in fullscreen mode"
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
sudo apt install -y chromium-browser

# Get current user (usually 'pi')
CURRENT_USER=$(whoami)
LABWC_CONFIG_DIR="/home/$CURRENT_USER/.config/labwc"

# Create labwc config directory
echo "2. Creating labwc configuration..."
mkdir -p "$LABWC_CONFIG_DIR"

# Create loading page (black screen that auto-redirects when PouCon is ready)
echo "3. Creating loading page..."
mkdir -p ~/.local/share/poucon

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

# Create kiosk startup script
echo "4. Creating kiosk startup script..."
mkdir -p ~/.local/bin

cat > ~/.local/bin/start_poucon_kiosk.sh << 'EOF'
#!/bin/bash
# PouCon Kiosk Mode - Wayland/labwc

# Start Chromium in kiosk mode with Wayland support
# The loading page shows a black screen and auto-redirects when PouCon is ready
chromium-browser \
  --ozone-platform=wayland \
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
  --enable-features=TouchpadOverscrollHistoryNavigation \
  "file://$HOME/.local/share/poucon/loading.html"
EOF

chmod +x ~/.local/bin/start_poucon_kiosk.sh

# Update labwc autostart to include kiosk browser
echo "5. Configuring labwc autostart..."

# Backup existing autostart if it exists
if [ -f "$LABWC_CONFIG_DIR/autostart" ]; then
    cp "$LABWC_CONFIG_DIR/autostart" "$LABWC_CONFIG_DIR/autostart.backup"
    # Remove any existing poucon kiosk line
    sed -i '/start_poucon_kiosk/d' "$LABWC_CONFIG_DIR/autostart"
fi

# Add kiosk to autostart
echo "$HOME/.local/bin/start_poucon_kiosk.sh &" >> "$LABWC_CONFIG_DIR/autostart"

# Configure labwc to hide cursor after inactivity
echo "6. Configuring cursor hiding..."
cat > "$LABWC_CONFIG_DIR/rc.xml" << 'EOF'
<?xml version="1.0"?>
<labwc_config>
  <core>
    <gap>0</gap>
  </core>
  <mouse>
    <hideWhenTyping>yes</hideWhenTyping>
  </mouse>
  <libinput>
    <device category="touch">
      <tap>yes</tap>
    </device>
  </libinput>
</labwc_config>
EOF

# Check and enable auto-login
echo "7. Checking auto-login configuration..."
if [ -f /etc/lightdm/lightdm.conf ]; then
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
else
    echo "   WARNING: lightdm.conf not found. Auto-login may need manual configuration."
fi

# Verify touchscreen is detected
echo ""
echo "8. Verifying touchscreen detection..."
if command -v libinput &> /dev/null; then
    if sudo libinput list-devices 2>/dev/null | grep -iq touch; then
        echo "   Touchscreen detected"
    else
        echo "   WARNING: No touchscreen detected via libinput"
        echo "   The kiosk will work with mouse/keyboard"
    fi
else
    echo "   libinput not available for touchscreen detection"
fi

echo ""
echo "=== Kiosk Setup Complete! ==="
echo ""
echo "Next steps:"
echo "  1. Reboot: sudo reboot"
echo "  2. Pi will boot directly to PouCon in fullscreen"
echo "  3. Touch screen to interact with controls"
echo ""
echo "To exit kiosk mode temporarily:"
echo "  - Connect a keyboard and press Alt+F4"
echo "  - Or SSH in and run: pkill chromium"
echo ""
echo "To disable kiosk mode permanently:"
echo "  sed -i '/start_poucon_kiosk/d' ~/.config/labwc/autostart"
echo ""
echo "To customize settings, edit:"
echo "  ~/.local/bin/start_poucon_kiosk.sh"
echo "  ~/.config/labwc/autostart"
echo ""

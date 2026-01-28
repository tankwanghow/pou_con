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

# Get script directory to check for offline debs
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Install chromium (kiosk browser)
if command -v chromium-browser &> /dev/null || command -v chromium &> /dev/null; then
    echo "   ✓ Chromium already installed"
elif [ -d "$SCRIPT_DIR/debs" ] && ls "$SCRIPT_DIR/debs/"*chromium*.deb 1> /dev/null 2>&1; then
    echo "   Installing chromium from offline packages..."
    sudo dpkg -i "$SCRIPT_DIR/debs/"*.deb 2>&1 | grep -v "^Selecting\|^Preparing\|^Unpacking\|^Setting up" || true
    sudo apt-get install -f -y -qq 2>/dev/null || true
    echo "   ✓ Chromium installed (offline)"
else
    echo "   Installing chromium from internet..."
    sudo apt update
    sudo apt install -y chromium
    echo "   ✓ Chromium installed (online)"
fi

# Install swayidle (screen timeout/blanking)
if command -v swayidle &> /dev/null; then
    echo "   ✓ swayidle already installed"
elif [ -d "$SCRIPT_DIR/debs" ] && ls "$SCRIPT_DIR/debs/"*swayidle*.deb 1> /dev/null 2>&1; then
    echo "   Installing swayidle from offline packages..."
    sudo dpkg -i "$SCRIPT_DIR/debs/"*swayidle*.deb 2>&1 | grep -v "^Selecting\|^Preparing\|^Unpacking\|^Setting up" || true
    sudo apt-get install -f -y -qq 2>/dev/null || true
    echo "   ✓ swayidle installed (offline)"
else
    echo "   Installing swayidle from internet..."
    sudo apt-get install -y -qq swayidle 2>/dev/null || sudo apt install -y swayidle
    echo "   ✓ swayidle installed (online)"
fi

# Use pou_con user for kiosk mode (consistent with the service user)
KIOSK_USER="pou_con"
KIOSK_HOME="/home/$KIOSK_USER"
LABWC_CONFIG_DIR="$KIOSK_HOME/.config/labwc"

# Verify pou_con user exists
if ! id "$KIOSK_USER" &>/dev/null; then
    echo "ERROR: User $KIOSK_USER does not exist."
    echo "       Run the deploy script first, or create the user manually:"
    echo "       sudo useradd -m -s /bin/bash $KIOSK_USER"
    exit 1
fi

# Verify home directory exists
if [ ! -d "$KIOSK_HOME" ]; then
    echo "Creating home directory for $KIOSK_USER..."
    sudo mkdir -p "$KIOSK_HOME"
    sudo chown "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME"
fi

# Create labwc config directory
echo "2. Creating labwc configuration..."
sudo -u "$KIOSK_USER" mkdir -p "$LABWC_CONFIG_DIR"

# Create loading page (black screen that auto-redirects when PouCon is ready)
echo "3. Creating loading page..."
sudo -u "$KIOSK_USER" mkdir -p "$KIOSK_HOME/.local/share/poucon"

cat > "$KIOSK_HOME/.local/share/poucon/loading.html" << 'HTMLEOF'
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
sudo -u "$KIOSK_USER" mkdir -p "$KIOSK_HOME/.local/bin"

cat > "$KIOSK_HOME/.local/bin/start_poucon_kiosk.sh" << 'EOF'
#!/bin/bash
# PouCon Kiosk Mode - Wayland/labwc

# Detect chromium command (chromium-browser on some distros, chromium on others)
if command -v chromium-browser &> /dev/null; then
    CHROMIUM_CMD="chromium-browser"
elif command -v chromium &> /dev/null; then
    CHROMIUM_CMD="chromium"
else
    echo "ERROR: Chromium not found"
    exit 1
fi

# Start Chromium in kiosk mode with Wayland support
# The loading page shows a black screen and auto-redirects when PouCon is ready
$CHROMIUM_CMD \
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

chmod +x "$KIOSK_HOME/.local/bin/start_poucon_kiosk.sh"
chown "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/.local/bin/start_poucon_kiosk.sh"
chown "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/.local/share/poucon/loading.html"

# Update labwc autostart to include kiosk browser
echo "5. Configuring labwc autostart..."

# Backup existing autostart if it exists
if [ -f "$LABWC_CONFIG_DIR/autostart" ]; then
    cp "$LABWC_CONFIG_DIR/autostart" "$LABWC_CONFIG_DIR/autostart.backup"
    # Remove any existing poucon kiosk line
    sed -i '/start_poucon_kiosk/d' "$LABWC_CONFIG_DIR/autostart"
fi

# Add kiosk to autostart (use explicit path, not $HOME which varies by user)
echo "$KIOSK_HOME/.local/bin/start_poucon_kiosk.sh &" >> "$LABWC_CONFIG_DIR/autostart"
chown "$KIOSK_USER:$KIOSK_USER" "$LABWC_CONFIG_DIR/autostart"

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
chown "$KIOSK_USER:$KIOSK_USER" "$LABWC_CONFIG_DIR/rc.xml"

# Check and enable auto-login for pou_con user
echo "7. Checking auto-login configuration..."
if [ -f /etc/lightdm/lightdm.conf ]; then
    # Check current auto-login setting
    CURRENT_AUTOLOGIN=$(grep "^autologin-user=" /etc/lightdm/lightdm.conf 2>/dev/null | cut -d= -f2)

    if [ "$CURRENT_AUTOLOGIN" = "$KIOSK_USER" ]; then
        echo "   ✓ Auto-login already configured for $KIOSK_USER"
    elif [ -n "$CURRENT_AUTOLOGIN" ]; then
        echo "   Changing auto-login from $CURRENT_AUTOLOGIN to $KIOSK_USER"
        sudo sed -i "s/^autologin-user=.*/autologin-user=$KIOSK_USER/" /etc/lightdm/lightdm.conf
    else
        echo "   Enabling auto-login for user: $KIOSK_USER"
        sudo sed -i "s/^#autologin-user=/autologin-user=$KIOSK_USER/" /etc/lightdm/lightdm.conf

        # If that didn't work, add it manually
        if ! grep -q "^autologin-user=" /etc/lightdm/lightdm.conf 2>/dev/null; then
            sudo sed -i "/^\[Seat:\*\]/a autologin-user=$KIOSK_USER" /etc/lightdm/lightdm.conf
        fi
    fi
else
    echo "   WARNING: lightdm.conf not found. Auto-login may need manual configuration."
    echo "   Add to /etc/lightdm/lightdm.conf under [Seat:*]:"
    echo "   autologin-user=$KIOSK_USER"
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

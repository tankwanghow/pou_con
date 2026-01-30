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

# Use pi user for kiosk mode (default Raspberry Pi user, simplifies permissions)
KIOSK_USER="pi"
KIOSK_HOME="/home/$KIOSK_USER"
LABWC_CONFIG_DIR="$KIOSK_HOME/.config/labwc"

# Verify pi user exists (should always exist on Raspberry Pi OS)
if ! id "$KIOSK_USER" &>/dev/null; then
    echo "ERROR: User $KIOSK_USER does not exist."
    echo "       This is unexpected - pi user should exist on Raspberry Pi OS."
    exit 1
fi

# Create only the directories that don't exist by default on Raspberry Pi OS
# (pi user already has .config, .cache, .local with correct ownership)
echo "2. Creating kiosk directories..."
sudo -u "$KIOSK_USER" mkdir -p "$KIOSK_HOME/.config/labwc"
sudo -u "$KIOSK_USER" mkdir -p "$KIOSK_HOME/.local/share/poucon"
sudo -u "$KIOSK_USER" mkdir -p "$KIOSK_HOME/.local/bin"
echo "   ✓ Directories created"

# Create loading page (black screen that auto-redirects when PouCon is ready)
echo "3. Creating loading page..."

sudo -u "$KIOSK_USER" tee "$KIOSK_HOME/.local/share/poucon/loading.html" > /dev/null << 'HTMLEOF'
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
sudo -u "$KIOSK_USER" tee "$KIOSK_HOME/.local/bin/start_poucon_kiosk.sh" > /dev/null << 'EOF'
#!/bin/bash
# PouCon Kiosk Mode - Wayland/labwc (touchscreen optimized)

# Clear chromium session files to prevent "restore session" prompts on crash/reboot
rm -f ~/.config/chromium/Default/{Current,Last}\ {Session,Tabs} 2>/dev/null
rm -rf ~/.config/chromium/Crash\ Reports 2>/dev/null

# Detect chromium command
CHROMIUM=$(command -v chromium-browser || command -v chromium)
[ -z "$CHROMIUM" ] && { echo "ERROR: Chromium not found"; exit 1; }

# Start Chromium in kiosk mode (touchscreen optimized)
exec $CHROMIUM \
  --ozone-platform=wayland \
  --start-fullscreen \
  --noerrdialogs \
  --disable-infobars \
  --disable-session-crashed-bubble \
  --disable-restore-session-state \
  --disable-translate \
  --no-first-run \
  --password-store=basic \
  --disable-features=TranslateUI,PasswordManager \
  --overscroll-history-navigation=0 \
  --disable-pinch \
  --touch-events=enabled \
  --enable-touch-drag-drop \
  "file://$HOME/.local/share/poucon/loading.html"
EOF

chmod +x "$KIOSK_HOME/.local/bin/start_poucon_kiosk.sh"

# Configure screen orientation
echo "5. Configuring screen orientation..."
echo ""
echo "Select screen orientation:"
echo "  1) Normal (0°) - Landscape, no rotation"
echo "  2) Left (90°) - Portrait, rotated left"
echo "  3) Inverted (180°) - Landscape, upside down"
echo "  4) Right (270°) - Portrait, rotated right (common for reTerminal)"
echo ""
read -p "Select [1-4] (default: 1): " ORIENTATION_CHOICE

case "$ORIENTATION_CHOICE" in
    2) SCREEN_TRANSFORM="transform 90" ;;
    3) SCREEN_TRANSFORM="transform 180" ;;
    4) SCREEN_TRANSFORM="transform 270" ;;
    *) SCREEN_TRANSFORM="" ;;
esac

# Configure screen timeout
echo ""
echo "6. Configuring screen timeout..."
echo ""
echo "Select screen blank timeout:"
echo "  1) 1 minute"
echo "  2) 3 minutes"
echo "  3) 5 minutes"
echo "  4) 10 minutes"
echo "  5) Never (always on)"
echo ""
read -p "Select [1-5] (default: 3): " TIMEOUT_CHOICE

case "$TIMEOUT_CHOICE" in
    1) SCREEN_TIMEOUT=60 ;;
    2) SCREEN_TIMEOUT=180 ;;
    4) SCREEN_TIMEOUT=600 ;;
    5) SCREEN_TIMEOUT=0 ;;
    *) SCREEN_TIMEOUT=300 ;;
esac

# Update labwc autostart to include kiosk browser
echo "7. Configuring labwc autostart..."

# Backup existing autostart if it exists
if [ -f "$LABWC_CONFIG_DIR/autostart" ]; then
    sudo cp "$LABWC_CONFIG_DIR/autostart" "$LABWC_CONFIG_DIR/autostart.backup"
fi

# Build autostart content
AUTOSTART_CONTENT="# Screen orientation (applied on startup)"

# Add wlr-randr command if rotation is needed
if [ -n "$SCREEN_TRANSFORM" ]; then
    # Install wlr-randr if not present
    if ! command -v wlr-randr &> /dev/null; then
        echo "   Installing wlr-randr for screen rotation..."
        if [ -d "$SCRIPT_DIR/debs" ] && ls "$SCRIPT_DIR/debs/"*wlr-randr*.deb 1> /dev/null 2>&1; then
            sudo dpkg -i "$SCRIPT_DIR/debs/"*wlr-randr*.deb 2>/dev/null || true
            sudo apt-get install -f -y -qq 2>/dev/null || true
        else
            sudo apt-get install -y -qq wlr-randr 2>/dev/null || sudo apt install -y wlr-randr
        fi
    fi
    AUTOSTART_CONTENT="$AUTOSTART_CONTENT
wlr-randr --output \$(wlr-randr | grep -m1 '^[A-Z]' | cut -d' ' -f1) --$SCREEN_TRANSFORM"
    echo "   ✓ Screen rotation configured: $SCREEN_TRANSFORM"
else
    echo "   ✓ No screen rotation (normal orientation)"
fi

# Add screen timeout configuration
AUTOSTART_CONTENT="$AUTOSTART_CONTENT

# Screen timeout (swayidle)"
if [ "$SCREEN_TIMEOUT" -gt 0 ]; then
    AUTOSTART_CONTENT="$AUTOSTART_CONTENT
swayidle -w timeout $SCREEN_TIMEOUT '/opt/pou_con/scripts/off_screen.sh' resume '/opt/pou_con/scripts/on_screen.sh' &"
    echo "   ✓ Screen timeout set to ${SCREEN_TIMEOUT}s"
else
    AUTOSTART_CONTENT="$AUTOSTART_CONTENT
# Screen timeout disabled (always on)"
    echo "   ✓ Screen timeout disabled (always on)"
fi

# Add kiosk browser
AUTOSTART_CONTENT="$AUTOSTART_CONTENT

# PouCon kiosk browser
$KIOSK_HOME/.local/bin/start_poucon_kiosk.sh &"

# Write autostart file (as pi user for correct ownership)
echo "$AUTOSTART_CONTENT" | sudo -u "$KIOSK_USER" tee "$LABWC_CONFIG_DIR/autostart" > /dev/null

# Configure labwc for touchscreen-first mode
echo "8. Configuring touchscreen mode..."
sudo -u "$KIOSK_USER" tee "$LABWC_CONFIG_DIR/rc.xml" > /dev/null << 'EOF'
<?xml version="1.0"?>
<labwc_config>
  <core>
    <gap>0</gap>
  </core>
  <cursor>
    <!-- Hide cursor after 3 seconds of inactivity (touchscreen mode) -->
    <hide>3000</hide>
  </cursor>
  <libinput>
    <!-- Touchscreen settings -->
    <device category="touch">
      <tap>yes</tap>
      <naturalScroll>yes</naturalScroll>
    </device>
    <!-- Disable touchpad if mouse is connected (prefer touch) -->
    <device category="touchpad">
      <tap>yes</tap>
      <naturalScroll>yes</naturalScroll>
    </device>
  </libinput>
</labwc_config>
EOF

# Check and enable auto-login for pi user
echo "9. Checking auto-login configuration..."
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
echo "10. Verifying touchscreen detection..."
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

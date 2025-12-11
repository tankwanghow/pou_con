# Touchscreen Kiosk Mode Setup

This guide covers setting up a touchscreen display connected to the Raspberry Pi to show the PouCon interface in fullscreen kiosk mode.

## Table of Contents

1. [Overview](#overview)
2. [Hardware Options](#hardware-options)
3. [Standard Raspberry Pi + Touchscreen Setup](#standard-raspberry-pi--touchscreen-setup)
4. [Industrial Touch Panel PC Setup](#industrial-touch-panel-pc-setup)
5. [Kiosk Mode Configuration](#kiosk-mode-configuration)
6. [Troubleshooting](#troubleshooting)
7. [Deployment Checklist](#deployment-checklist)

---

## Overview

**What this does:**
- Raspberry Pi boots directly to PouCon interface on touchscreen
- Fullscreen browser in kiosk mode (no address bar, no menus)
- Touch input works for controlling equipment
- Auto-restarts browser if it crashes
- No keyboard/mouse needed

**Use cases:**
- Touchscreen panel mounted in poultry house
- Operator controls equipment directly on-site
- Backup interface if network/WiFi fails
- 24/7 monitoring display

---

## Hardware Options

### Option 1: Standard Raspberry Pi + External Touchscreen

**Components:**
- Raspberry Pi 4 (4GB+ RAM recommended)
- External touchscreen (7"-15")
- Power supply, case, cables

**Connection Types:**
- **DSI Display:** Official Pi 7" touchscreen (plug-and-play)
- **HDMI + USB Touch:** Most aftermarket displays
- **GPIO Touch:** Some resistive touchscreens

**Best for:**
- Budget deployments
- Flexibility in screen size
- Easy component replacement

**Driver Support:** Usually automatic with Raspberry Pi OS

---

### Option 2: Industrial Touch Panel PC with Raspberry Pi

**What is it:**
Complete industrial computer with:
- Raspberry Pi Compute Module built-in
- Integrated touchscreen (7"-15")
- Rugged aluminum/steel enclosure
- IP65/IP67 rated (dust/water resistant)
- Wide operating temperature (-20°C to +70°C)
- 24V DC industrial power supply
- DIN rail or VESA mounting

**Common Manufacturers:**
1. **Waveshare** - Industrial IoT, good documentation
2. **Seeed Studio** - reTerminal, modular design
3. **Advantech** - Enterprise-grade, expensive
4. **IEI Integration** - Industrial automation focus
5. **TE Connectivity** - Rugged military-grade
6. **Kunbus** - RevPi series, automation focus

**Best for:**
- Harsh poultry house environments
- Dust, moisture, temperature extremes
- Professional installations
- Long-term reliability

**Driver Support:** Often requires vendor-specific drivers

---

## Standard Raspberry Pi + Touchscreen Setup

### Quick Setup (Standard Displays)

**Step 1: Hardware Connection**

```bash
# For Official Pi 7" Touchscreen:
# - Connect DSI ribbon cable to DISPLAY port
# - Connect touch cable to I2C pins
# - Power: Either USB-C to Pi or dedicated power

# For HDMI Touchscreens:
# - Connect HDMI cable to Pi HDMI port
# - Connect USB cable for touch (any USB port)
# - Power: Usually powered via USB
```

**Step 2: Flash and Boot**

```bash
# Use Raspberry Pi Imager
# Select: Raspberry Pi OS (64-bit) with Desktop
# Configure: hostname, SSH, WiFi, user
# Flash to SD card
# Boot with touchscreen connected
```

**Step 3: Verify Touch Works**

```bash
# After desktop loads, tap screen
# Should see mouse cursor follow touches

# Verify in terminal:
xinput list
# Should show touch device

# Test events:
xinput test <device-id>
# Tap screen, should show coordinates
```

**Step 4: Deploy PouCon**

```bash
# Copy deployment package
cp /media/pi/*/pou_con_deployment_*.tar.gz ~/
tar -xzf pou_con_deployment_*.tar.gz
cd deployment_package_*/

# Deploy application
sudo ./deploy.sh
sudo systemctl enable pou_con
sudo systemctl start pou_con

# Test in browser
chromium-browser http://localhost:4000
```

**Step 5: Setup Kiosk Mode**

See [Kiosk Mode Configuration](#kiosk-mode-configuration) section below.

---

## Industrial Touch Panel PC Setup

### Understanding Industrial Panel Drivers

**Why special drivers are needed:**

Industrial panels often use:
- **Custom touch controllers** (not standard USB HID)
- **Proprietary communication protocols** (I2C, SPI, custom)
- **Hardware-specific calibration data**
- **Embedded functionality** (GPIO buttons, LEDs, buzzers)

**Driver types:**
1. **Kernel modules** - Compiled for specific kernel version
2. **Device tree overlays** - Configuration files for hardware
3. **Userspace libraries** - Touch daemon running as service
4. **X11 input drivers** - Integration with display server

### Common Industrial Panel Types

#### Type A: Waveshare Industrial IoT Panels

**Models:**
- CM4 Panel 7", 10.1", 13.3"
- reTerminal series

**OS Support:**
- Provides custom Raspberry Pi OS image
- Includes pre-installed drivers
- Touch works out-of-box with their image

**Driver Installation (if using stock Raspberry Pi OS):**

```bash
# Check vendor documentation first
# Example for Waveshare CM4 Panel:

# 1. Install device tree overlay
sudo wget https://files.waveshare.com/upload/panel/dtbo/waveshare-panel.dtbo \
  -O /boot/overlays/waveshare-panel.dtbo

# 2. Edit boot config
sudo nano /boot/config.txt

# Add overlay:
dtoverlay=waveshare-panel

# 3. Reboot
sudo reboot

# 4. Verify touch device
xinput list
ls /dev/input/event*
```

**Recommendation:** Use vendor-provided OS image for guaranteed compatibility.

---

#### Type B: Seeed Studio reTerminal

**Models:**
- reTerminal (CM4, 5" touch)
- reTerminal DM (7" display)

**OS Support:**
- Raspberry Pi OS compatible
- Requires kernel drivers
- Well-documented on Seeed Wiki

**Driver Installation:**

```bash
# Install reTerminal drivers
git clone https://github.com/Seeed-Studio/seeed-linux-dtoverlays
cd seeed-linux-dtoverlays

# Install device tree overlays
sudo ./scripts/install.sh

# Enable reTerminal overlay
sudo nano /boot/config.txt

# Add:
dtparam=i2c_arm=on
dtoverlay=reTerminal

# Install touch screen driver
sudo apt update
sudo apt install -y seeed-voicecard

# Reboot
sudo reboot

# Test touch
evtest /dev/input/event0
```

**Display rotation:**
```bash
# reTerminal is portrait by default
# Rotate to landscape in /boot/config.txt:
display_lcd_rotate=1
```

---

#### Type C: Advantech Industrial Touch Panels

**Models:**
- UTC Series (15"-21")
- UBC Series (10"-15")

**OS Support:**
- Provide custom Ubuntu/Debian images
- Proprietary touch drivers included
- Less Raspberry Pi-focused (use x86 often)

**If using with RPi Compute Module:**

```bash
# Check vendor documentation
# Usually ships with pre-configured OS

# To verify touch driver:
lsmod | grep touch
dmesg | grep -i advantech

# If driver not loaded:
# Contact Advantech support for RPi-specific drivers
# May require custom kernel compilation
```

**Recommendation:** Use vendor OS image or contact support for RPi compatibility.

---

#### Type D: Custom Compute Module Carriers

**Characteristics:**
- Custom carrier board with CM4
- Touch controller on I2C/SPI bus
- Vendor-specific device tree

**Generic Setup Process:**

```bash
# 1. Identify touch controller chip
# Check vendor documentation or board schematic
# Common chips: FT5406, GT911, ILITEK, Goodix

# 2. Find appropriate device tree overlay
ls /boot/overlays/*touch*
ls /boot/overlays/*ft5*
ls /boot/overlays/*gt911*

# 3. Enable overlay in config.txt
sudo nano /boot/config.txt

# Examples:
dtoverlay=rpi-ft5406         # For FT5406 controller
dtoverlay=goodix             # For Goodix GT911
dtoverlay=ads7846            # For resistive touch

# 4. May need I2C/SPI configuration
dtparam=i2c_arm=on
dtparam=spi=on

# 5. Reboot and test
sudo reboot
xinput list
```

---

### Recommended Setup Process for Industrial Panels

**Step 1: Identify Your Panel**

```bash
# Check vendor documentation/stickers
# Note down:
# - Manufacturer and model number
# - Compute Module version (CM3/CM4)
# - Touch controller chip (if documented)
# - Display interface (HDMI/DSI/LVDS)

# On running system:
cat /proc/device-tree/model
# Shows: Raspberry Pi Compute Module 4 ...

lsusb
# Look for touch controller

i2cdetect -y 1
# Shows I2C devices (common for touch controllers)
```

**Step 2: Obtain Vendor OS Image (Recommended)**

**Best practice:** Use vendor-provided Raspberry Pi OS image

**Why:**
- Drivers pre-installed and tested
- Touch calibration pre-configured
- Hardware features working out-of-box
- Less troubleshooting

**Where to find:**
- Manufacturer website (Downloads/Support section)
- Product documentation CD/USB drive
- Contact manufacturer support

**Typical download:**
```bash
# Example: Waveshare CM4 Panel
# Download: CM4_Panel_Raspberry_Pi_OS_2023-12-05.img.xz

# Flash using Raspberry Pi Imager:
# - Choose "Use custom" and select downloaded image
# - Configure hostname, SSH, WiFi
# - Flash to SD card
```

---

**Step 3: Test Vendor Image**

```bash
# Boot vendor image
# Touchscreen should work immediately

# Verify:
xinput list
# Should show touch device with correct name

# Test touch
evtest
# Select touch device, tap screen

# If working, proceed to PouCon deployment
```

---

**Step 4: Deploy PouCon on Vendor Image**

```bash
# Use standard deployment process
# Vendor OS is just Raspberry Pi OS with drivers

# Transfer deployment package
scp pou_con_deployment_*.tar.gz pi@<panel-ip>:~/

# SSH to panel
ssh pi@<panel-ip>

# Deploy
cd ~
tar -xzf pou_con_deployment_*.tar.gz
cd deployment_package_*/
sudo ./deploy.sh
sudo systemctl enable pou_con
sudo systemctl start pou_con

# Test
chromium-browser http://localhost:4000
# Tap screen to verify touch works in PouCon
```

---

**Step 5: Alternative - Manual Driver Installation**

**Only if vendor image not available or you must use stock Raspberry Pi OS:**

```bash
# This is ADVANCED and varies by panel
# Contact vendor support for instructions

# General approach:

# 1. Flash stock Raspberry Pi OS
# 2. Update system
sudo apt update && sudo apt upgrade -y

# 3. Install vendor driver package (if provided)
# Example: Vendor provides .deb package
sudo dpkg -i vendor-panel-drivers_1.0.0_arm64.deb
sudo apt --fix-broken install

# 4. Or install device tree overlay
# Example: Vendor provides .dtbo file
sudo cp vendor-panel.dtbo /boot/overlays/
sudo nano /boot/config.txt
# Add: dtoverlay=vendor-panel

# 5. Configure touch parameters (vendor-specific)
sudo nano /boot/config.txt
# Example parameters:
dtparam=touch_rotation=0
dtparam=touch_swap_xy=0
dtparam=touch_invert_x=0

# 6. Reboot
sudo reboot

# 7. Verify and troubleshoot
dmesg | grep -i touch
xinput list
evtest
```

---

### Industrial Panel Deployment Workflow

**Recommended Workflow:**

```
1. Receive industrial panel from manufacturer
   ↓
2. Download vendor OS image (from website/support)
   ↓
3. Flash vendor image to SD card/eMMC
   ↓
4. Boot and verify touch works on vendor desktop
   ↓
5. Deploy PouCon using standard deployment package
   ↓
6. Configure kiosk mode (see next section)
   ↓
7. Mount panel in poultry house
```

**Time estimate:**
- With vendor image: 30 minutes
- Without vendor image: 2-4 hours (driver troubleshooting)

---

### Industrial Panel Considerations

#### 1. Display Orientation

Industrial panels may be mounted in portrait or landscape:

```bash
# Rotate display
sudo nano /boot/config.txt

# For HDMI displays:
display_hdmi_rotate=1    # 90° clockwise
# 0=normal, 1=90°, 2=180°, 3=270°

# For DSI displays:
display_lcd_rotate=1

# For official Pi touchscreen:
lcd_rotate=2

# Rotate touch input to match
# Add to kiosk script (~/.local/bin/start_kiosk.sh):
xinput set-prop "Touch Device Name" "Coordinate Transformation Matrix" \
  0 1 0 -1 0 1 0 0 1
# Adjust matrix based on rotation angle
```

#### 2. Backlight Control

```bash
# Brightness control (vendor-specific)

# Example 1: sysfs interface
echo 128 | sudo tee /sys/class/backlight/*/brightness
# Values: 0-255

# Example 2: Vendor tool
vendor-brightness-tool --set 50

# Add to kiosk script for auto-dim:
# Bright during day, dim at night
HOUR=$(date +%H)
if [ $HOUR -ge 7 ] && [ $HOUR -le 19 ]; then
    echo 200 | sudo tee /sys/class/backlight/*/brightness
else
    echo 50 | sudo tee /sys/class/backlight/*/brightness
fi
```

#### 3. Hardware Buttons/LEDs

Many industrial panels have GPIO buttons and status LEDs:

```bash
# Check vendor documentation for GPIO mapping

# Example: Panel has USER button on GPIO 17
# Add to kiosk script for emergency restart:

# Monitor button press
python3 << 'EOF' &
import RPi.GPIO as GPIO
import os

GPIO.setmode(GPIO.BCM)
GPIO.setup(17, GPIO.IN, pull_up_down=GPIO.PUD_UP)

def button_pressed(channel):
    # Hold button for 5 seconds to restart PouCon
    os.system("systemctl restart pou_con")

GPIO.add_event_detect(17, GPIO.FALLING, callback=button_pressed, bouncetime=5000)
EOF
```

#### 4. Rugged Environment Settings

```bash
# Disable unnecessary services to reduce heat
sudo systemctl disable bluetooth
sudo systemctl disable avahi-daemon

# Enable hardware watchdog (auto-reboot if frozen)
sudo nano /etc/watchdog.conf
# Uncomment:
watchdog-device = /dev/watchdog
max-load-1 = 24

sudo systemctl enable watchdog
sudo systemctl start watchdog

# Temperature monitoring
# Add to cron:
*/5 * * * * /usr/bin/vcgencmd measure_temp >> /var/log/temp.log
```

---

## Kiosk Mode Configuration

This section applies to **both standard and industrial panels**.

### Method 1: Desktop Auto-start (Recommended)

**For Raspberry Pi OS Desktop:**

```bash
# Install required packages
sudo apt update
sudo apt install -y chromium-browser unclutter xdotool

# Create kiosk script
mkdir -p ~/.local/bin
cat > ~/.local/bin/start_kiosk.sh << 'EOF'
#!/bin/bash

# Wait for PouCon service to be ready
sleep 10

# Hide mouse cursor after 0.1 seconds of inactivity
unclutter -idle 0.1 -root &

# Disable screen blanking
xset s off
xset -dpms
xset s noblank

# Optional: Set brightness (adjust path for your panel)
# echo 200 | sudo tee /sys/class/backlight/*/brightness

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

chmod +x ~/.local/bin/start_kiosk.sh

# Create autostart entry
mkdir -p ~/.config/autostart
cat > ~/.config/autostart/poucon-kiosk.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=PouCon Kiosk
Exec=/home/pi/.local/bin/start_kiosk.sh
X-GNOME-Autostart-enabled=true
EOF
```

**Enable auto-login:**

```bash
# Via raspi-config
sudo raspi-config
# Select: System Options → Boot / Auto Login → Desktop Autologin

# Or manually:
sudo nano /etc/lightdm/lightdm.conf
# Under [Seat:*], set:
autologin-user=pi
```

**Disable screen blanking (permanent):**

```bash
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
```

**Reboot and test:**

```bash
sudo reboot

# Expected: Pi boots to desktop, then Chromium opens fullscreen to PouCon
# No address bar, no UI elements, touch works
```

---

### Method 2: Minimal Kiosk (Raspberry Pi OS Lite)

**For headless deployments with minimal resource usage:**

```bash
# Install minimal X server
sudo apt update
sudo apt install -y \
  --no-install-recommends \
  xserver-xorg \
  x11-xserver-utils \
  xinit \
  openbox \
  chromium-browser \
  unclutter

# Create openbox autostart
mkdir -p ~/.config/openbox
cat > ~/.config/openbox/autostart << 'EOF'
#!/bin/bash

sleep 10
xset s off
xset -dpms
xset s noblank
unclutter -idle 0.1 -root &

chromium-browser \
  --kiosk \
  --noerrdialogs \
  --disable-infobars \
  --no-first-run \
  --disable-pinch \
  http://localhost:4000
EOF

chmod +x ~/.config/openbox/autostart

# Auto-start X on login
cat >> ~/.bash_profile << 'EOF'

if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    startx
fi
EOF

# Enable console auto-login
sudo raspi-config
# System Options → Boot / Auto Login → Console Autologin

# Reboot
sudo reboot
```

---

### Kiosk Automation Script

**Include in deployment package:**

```bash
# Create scripts/setup_kiosk.sh in deployment package
cat > scripts/setup_kiosk.sh << 'EOF'
#!/bin/bash
set -e

echo "=== PouCon Kiosk Mode Setup ==="

# Check PouCon is installed
if [ ! -f /opt/pou_con/bin/pou_con ]; then
    echo "ERROR: PouCon not installed. Run deploy.sh first"
    exit 1
fi

# Install packages
echo "Installing packages..."
sudo apt update
sudo apt install -y chromium-browser unclutter xdotool

# Create kiosk script
mkdir -p ~/.local/bin
cat > ~/.local/bin/start_kiosk.sh << 'EOFINNER'
#!/bin/bash
sleep 10
unclutter -idle 0.1 -root &
xset s off -dpms s noblank
chromium-browser --kiosk --noerrdialogs --disable-infobars \
  --disable-session-crashed-bubble --no-first-run --disable-pinch \
  --overscroll-history-navigation=0 http://localhost:4000
EOFINNER

chmod +x ~/.local/bin/start_kiosk.sh

# Create autostart
mkdir -p ~/.config/autostart
cat > ~/.config/autostart/poucon-kiosk.desktop << 'EOFINNER'
[Desktop Entry]
Type=Application
Name=PouCon Kiosk
Exec=/home/pi/.local/bin/start_kiosk.sh
X-GNOME-Autostart-enabled=true
EOFINNER

# Disable screen blanking
sudo mkdir -p /etc/X11/xorg.conf.d/
sudo cat > /etc/X11/xorg.conf.d/10-monitor.conf << 'EOFINNER'
Section "ServerLayout"
    Identifier "ServerLayout0"
    Option "BlankTime" "0"
    Option "StandbyTime" "0"
    Option "SuspendTime" "0"
    Option "OffTime" "0"
EndSection
EOFINNER

# Enable auto-login if not already
if ! grep -q "autologin-user=pi" /etc/lightdm/lightdm.conf 2>/dev/null; then
    echo "Enabling auto-login..."
    sudo sed -i 's/^#autologin-user=/autologin-user=pi/' /etc/lightdm/lightdm.conf
fi

echo ""
echo "=== Kiosk Setup Complete! ==="
echo "Reboot to start kiosk mode: sudo reboot"
EOF

chmod +x scripts/setup_kiosk.sh
```

---

## Troubleshooting

### Issue: Touchscreen Not Detected

**Diagnosis:**

```bash
# Check USB devices (for USB touch)
lsusb

# Check I2C devices (for I2C touch)
sudo i2cdetect -y 1

# Check kernel messages
dmesg | grep -i touch
dmesg | grep -i hid
dmesg | grep -i input

# List input devices
ls /dev/input/event*
cat /proc/bus/input/devices

# Test raw events
sudo evtest
# Select device, touch screen to see events
```

**Solutions:**

1. **For industrial panels:** Use vendor OS image
2. **For USB touch:** Check cable, try different USB port
3. **For I2C touch:** Enable I2C in `/boot/config.txt`: `dtparam=i2c_arm=on`
4. **Driver issue:** Install correct device tree overlay
5. **Permission issue:** Add user to input group: `sudo usermod -a -G input pi`

---

### Issue: Touch Works in Console but Not in X11

**Diagnosis:**

```bash
# Check X input devices
DISPLAY=:0 xinput list

# Check X logs
cat /var/log/Xorg.0.log | grep -i input
```

**Solutions:**

```bash
# Install X input drivers
sudo apt install -y xserver-xorg-input-evdev xserver-xorg-input-libinput

# Force libinput driver
sudo nano /usr/share/X11/xorg.conf.d/40-libinput.conf

# Add touchscreen section:
Section "InputClass"
    Identifier "libinput touchscreen catchall"
    MatchIsTouchscreen "on"
    MatchDevicePath "/dev/input/event*"
    Driver "libinput"
EndSection

# Restart X
sudo systemctl restart lightdm
```

---

### Issue: Touch Calibration Off

**Diagnosis:**

```bash
# Touch point doesn't match cursor position
# Common with resistive touchscreens
```

**Solution:**

```bash
# Install calibration tool
sudo apt install -y xinput-calibrator

# Run calibration
DISPLAY=:0.0 xinput_calibrator

# Follow on-screen instructions (tap targets)

# Tool outputs calibration config:
Section "InputClass"
    Identifier "calibration"
    MatchProduct "Your Touch Device"
    Option "MinX" "3823"
    Option "MaxX" "253"
    Option "MinY" "3829"
    Option "MaxY" "194"
EndSection

# Save to config file:
sudo nano /usr/share/X11/xorg.conf.d/99-calibration.conf
# Paste the calibration section

# Restart X
sudo systemctl restart lightdm
```

---

### Issue: Browser Doesn't Start on Boot

**Diagnosis:**

```bash
# Check if autostart file exists
cat ~/.config/autostart/poucon-kiosk.desktop

# Check script permissions
ls -l ~/.local/bin/start_kiosk.sh

# Test script manually
~/.local/bin/start_kiosk.sh
```

**Solutions:**

1. **Script not executable:** `chmod +x ~/.local/bin/start_kiosk.sh`
2. **PouCon not running:** `systemctl status pou_con`
3. **Wrong DISPLAY:** Set `DISPLAY=:0` in script
4. **Chromium not installed:** `sudo apt install chromium-browser`

---

### Issue: Screen Goes Black

**Diagnosis:**

```bash
# Check screen saver settings
xset q | grep -A 5 "Screen Saver"

# Check DPMS status
xset q | grep -A 5 "DPMS"
```

**Solution:**

```bash
# Disable via command (temporary)
DISPLAY=:0 xset s off -dpms s noblank

# Permanent: Already in start_kiosk.sh
# Verify xorg.conf.d file exists:
cat /etc/X11/xorg.conf.d/10-monitor.conf

# If missing, recreate as shown in kiosk configuration
```

---

### Issue: Industrial Panel-Specific Problems

#### Vendor OS Image Not Booting

```bash
# Verify SD card is good
sudo badblocks -v /dev/sdX

# Re-flash image
# Use official Raspberry Pi Imager or Balena Etcher

# Check MD5/SHA256 checksum of downloaded image
md5sum vendor_image.img.xz
# Compare with vendor-provided checksum
```

#### Touch Driver Not Loading

```bash
# Check device tree overlay
vcgencmd get_config str | grep dtoverlay

# Check loaded modules
lsmod | grep touch

# Manually load module (if known)
sudo modprobe vendor_touch_driver

# Check kernel ring buffer for errors
dmesg | tail -50
```

#### Vendor Support Contact

**Always have ready:**
- Panel model number and serial
- Raspberry Pi OS version: `cat /etc/os-release`
- Kernel version: `uname -a`
- Output of `dmesg | grep touch`
- Output of `lsusb` and `i2cdetect -y 1`

---

## Deployment Checklist

### For Standard Pi + Touchscreen

- [ ] Flash Raspberry Pi OS Desktop
- [ ] Connect touchscreen
- [ ] Boot and verify touch works
- [ ] Deploy PouCon application
- [ ] Test web interface
- [ ] Run `scripts/setup_kiosk.sh`
- [ ] Enable auto-login
- [ ] Reboot and verify kiosk starts
- [ ] Test touch controls in PouCon
- [ ] Adjust screen orientation if needed
- [ ] Configure brightness

### For Industrial Touch Panel PC

- [ ] Identify manufacturer and model
- [ ] Download vendor OS image
- [ ] Flash vendor image to SD/eMMC
- [ ] Boot and verify touch works with vendor desktop
- [ ] Note any vendor-specific settings
- [ ] Deploy PouCon using standard deployment package
- [ ] Test web interface with touch
- [ ] Run `scripts/setup_kiosk.sh`
- [ ] Verify auto-login enabled (may be pre-configured)
- [ ] Reboot and verify kiosk starts
- [ ] Test in production environment (temperature, dust)
- [ ] Document panel-specific configuration
- [ ] Configure hardware buttons/LEDs if available
- [ ] Test fail-safe features (watchdog, etc.)

---

## Recommended Hardware

### For Standard Deployments

**Budget (Under $150):**
- Raspberry Pi 4 (4GB): $55
- Waveshare 10.1" HDMI Touch: $80
- Case and cables: $15

**Mid-range (Under $250):**
- Raspberry Pi 4 (8GB): $75
- Official 7" Touch Display: $70
- Official Case: $25
- Quality cables: $20

### For Industrial Deployments (Poultry Houses)

**Recommended Minimum Specs:**
- 10" screen size (easy visibility, glove-friendly)
- IP65 rating minimum (dust/moisture protection)
- Capacitive touch (works with light gloves)
- Operating temperature: -20°C to +60°C
- 24V DC power (common in industrial settings)
- Brightness: >400 cd/m² (daylight readable)
- VESA or DIN rail mounting

**Recommended Products:**

1. **Waveshare CM4-Panel-10.1-B** ($200-250)
   - 10.1" IPS touchscreen
   - CM4 built-in
   - Aluminum enclosure
   - Good documentation
   - Available worldwide

2. **Seeed Studio reTerminal DM** ($250-300)
   - 7" industrial display
   - CM4 built-in
   - Modular design
   - Excellent software support
   - Active community

3. **Advantech TPC-1251H** ($500-700)
   - 12" industrial panel PC
   - CM4 compatible
   - IP65 rated
   - Enterprise quality
   - Better for large installations

4. **Custom Solution** ($150-200)
   - Raspberry Pi 4
   - Industrial touchscreen with IP65 enclosure
   - Custom mounting
   - Better component replacement options

**What I recommend for poultry houses:**
- Start with Waveshare CM4-Panel-10.1-B for testing
- If budget allows, go with Advantech for production
- Consider having 1-2 spare CM4 modules for quick replacement

---

## Summary

**Standard Pi + Touchscreen:**
- Plug-and-play with Raspberry Pi OS
- Setup time: 30 minutes
- Good for office/indoor environments
- Easy troubleshooting

**Industrial Touch Panel PC:**
- Use vendor OS image for best results
- Setup time: 30-60 minutes
- Required for harsh poultry house environments
- Better reliability and longevity
- Worth the extra cost for production deployments

**Key Takeaway:**
Industrial panels need vendor drivers, but if you use their OS image, it's as easy as standard setups. The deployment process for PouCon is identical in both cases.

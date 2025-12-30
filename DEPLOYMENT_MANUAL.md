# PouCon Deployment Manual

**Version 1.0 | December 2025**

This is the comprehensive deployment manual for PouCon, an industrial automation and control system for poultry farms built with Elixir and Phoenix LiveView.

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Quick Start](#2-quick-start)
3. [Hardware Requirements](#3-hardware-requirements)
4. [Cross-Platform Build](#4-cross-platform-build)
5. [Deployment Methods](#5-deployment-methods)
   - [5.1 Package Deployment](#51-package-deployment)
   - [5.2 Master Image Deployment](#52-master-image-deployment)
   - [5.3 CM4 Deployment](#53-cm4-deployment)
   - [5.4 Existing System Deployment](#54-existing-system-deployment)
6. [HTTPS & Multi-House Setup](#6-https--multi-house-setup)
   - [6.1 Overview](#61-overview)
   - [6.2 Certificate Authority Setup](#62-certificate-authority-setup)
   - [6.3 House Setup](#63-house-setup)
   - [6.4 Client Device Setup](#64-client-device-setup)
7. [Touchscreen & Kiosk Setup](#7-touchscreen--kiosk-setup)
8. [System Time Recovery](#8-system-time-recovery)
9. [Configuration](#9-configuration)
10. [Backup and Recovery](#10-backup-and-recovery)
11. [Troubleshooting](#11-troubleshooting)
12. [Scripts Reference](#12-scripts-reference)
13. [Quick Reference](#13-quick-reference)

---

# 1. Introduction

## 1.1 Overview

**PouCon** manages the complete lifecycle of poultry farm operations, from environmental climate control to automated feeding, egg collection, and waste management. The system communicates with industrial controllers via Modbus RTU/TCP and provides operators with a real-time web-based interface for monitoring and control.

## 1.2 Key Features

### Hardware Communication & Control
- **Modbus Protocol Support**: Full Modbus RTU/TCP implementation
- **Multi-Port Management**: Support for multiple serial/device ports
- **Real-time Polling**: Efficient caching and polling mechanism
- **Simulation Mode**: Complete hardware simulation for testing

### Equipment Management
- **Climate Control**: Automatic fan control, water pump management, temperature/humidity monitoring
- **Poultry Operations**: Automated feeding, egg collection, multi-position feed input
- **Waste Management**: Horizontal/vertical dung removal systems
- **Lighting**: Automated light scheduling with manual override

### User Interface
- **Real-time Dashboard**: Live equipment status and environmental monitoring
- **Environment Control Panel**: Configure climate parameters and thresholds
- **Device/Equipment Management**: Admin interfaces for configuration
- **Role-based Access**: Admin and User roles with authentication

## 1.3 Technology Stack

- **Language**: Elixir 1.18+
- **Web Framework**: Phoenix 1.8
- **Real-time UI**: Phoenix LiveView
- **Database**: SQLite with Ecto ORM
- **Hardware Protocol**: Modbus RTU/TCP
- **Target Platform**: Raspberry Pi 3B+/4/CM4 (ARM64)

## 1.4 Deployment Scenarios

| Scenario | Method | Time | Best For |
|----------|--------|------|----------|
| Production (Multiple Sites) | Master Image | 5 min/site | Production deployments |
| Testing/Development | Package Deployment | 10-15 min | Single installations |
| CM4 with Vendor OS | CM4 Bookworm | 10-15 min | Industrial panel PCs |
| Emergency Replacement | Master Image + Backup | 5-15 min | Hardware failures |

---

# 2. Quick Start

## 2.1 TL;DR

**On your development machine (one-time setup):**
```bash
./scripts/setup_docker_arm.sh    # Docker for ARM builds
./scripts/setup_ca.sh            # Create Certificate Authority for HTTPS
```

**Every time you want to deploy (10-20 minutes):**
```bash
./scripts/build_and_package.sh
cp pou_con_deployment_*.tar.gz /media/usb_drive/
cp priv/ssl/ca/ca.crt priv/ssl/ca/ca.key /media/usb_drive/  # For HTTPS setup
```

**At poultry house (5-10 minutes, no internet):**
```bash
tar -xzf pou_con_deployment_*.tar.gz
cd deployment_package_*/
sudo ./deploy.sh
sudo systemctl enable pou_con

# Configure house identity and HTTPS
cp /media/usb/ca.* /tmp/          # Copy CA files
./setup_house.sh                   # Prompts for house_id (e.g., h1, h2)
sudo systemctl start pou_con
```

Access at `https://poucon.<house_id>` (e.g., `https://poucon.h1`), login `admin`/`admin`, change password immediately.

**On user devices (one-time):**
- Install `ca.crt` as trusted certificate
- Add to `/etc/hosts` or router DNS: `<pi-ip> poucon.<house_id>`

## 2.2 Detailed Walkthrough

### Phase 1: One-Time Setup (Development Machine)

**Step 1: Setup Docker for ARM builds (once, ~10 minutes)**

```bash
cd /path/to/pou_con

# Run setup script
./scripts/setup_docker_arm.sh

# If prompted to log out/in, do so and run again
```

**Verify setup:**
```bash
docker buildx ls
# Should show 'multiarch' builder with linux/arm64 support
```

### Phase 2: Build for Deployment (Every Release)

**Option A: One Command (Easiest)**

```bash
cd /path/to/pou_con

# Build AND package in one command
./scripts/build_and_package.sh

# Result: pou_con_deployment_YYYYMMDD_HHMMSS.tar.gz
```

**Option B: Step by Step**

```bash
# Build ARM release (~10-20 minutes)
./scripts/build_arm.sh

# Create deployment package (~1 minute)
./scripts/create_deployment_package.sh

# Result: pou_con_deployment_YYYYMMDD_HHMMSS.tar.gz
```

**Copy to USB drive:**
```bash
cp pou_con_deployment_*.tar.gz /media/$USER/<usb-label>/
```

### Phase 3: Deploy at Poultry House (No Internet)

**Prerequisites on Raspberry Pi:**
- Raspberry Pi OS (64-bit) installed
- Basic system packages: `sqlite3`, `openssl`, `ca-certificates`, `libncurses5`
- RS485 USB adapters connected

**Deployment Process (5-10 minutes):**

```bash
# 1. Transfer package to Pi (via USB or network)
cd ~
cp /media/pi/*/pou_con_deployment_*.tar.gz ./

# 2. Extract and deploy
tar -xzf pou_con_deployment_*.tar.gz
cd deployment_package_*/
sudo ./deploy.sh

# 3. Start service
sudo systemctl enable pou_con
sudo systemctl start pou_con

# 4. Verify running
sudo systemctl status pou_con

# 5. Get Pi's IP address
hostname -I
```

### Phase 4: Initial Configuration (Web Interface)

1. Access: `http://<pi-ip>:4000`
2. Login: `admin` / `admin`
3. **CHANGE PASSWORD IMMEDIATELY**
4. Configure Hardware:
   - Admin → Ports (add RS485 ports)
   - Admin → Devices (add Modbus devices)
   - Admin → Equipment (configure fans, pumps, etc.)
5. Configure Automation:
   - Environment control
   - Lighting schedules
   - Feeding schedules

---

# 3. Hardware Requirements

## 3.1 Storage Requirements

| Component | Size | Notes |
|-----------|------|-------|
| **Operating System** | | |
| Raspberry Pi OS Lite | 500 MB - 1 GB | Headless (no GUI) |
| Raspberry Pi OS Desktop | 2 - 3 GB | With GUI for kiosk mode |
| **Runtime Environment** | | |
| Erlang VM + Elixir | 150 - 250 MB | Bundled in release |
| System dependencies | 100 - 200 MB | LibSSL, etc. |
| **PouCon Application** | | |
| Compiled release | 50 - 100 MB | Phoenix + dependencies |
| SQLite database | 10 - 50 MB | With 30-day retention |
| Logs and temp files | 100 - 200 MB | System logs, crash dumps |
| **Web Browser (Optional)** | | |
| Chromium browser | 150 - 250 MB | For kiosk mode |
| **Safety Buffer** | 2 - 4 GB | OS updates, temp files |

### Recommended Storage

- **Minimum (Headless)**: 8 GB
- **Recommended (Headless)**: 16 GB
- **With Local Browser**: 16-32 GB
- **Production Safe**: 32 GB

## 3.2 RAM Requirements

| Process | RAM Usage | Notes |
|---------|-----------|-------|
| Linux kernel + services | 100 - 200 MB | Idle state |
| GUI (if used) | 150 - 300 MB | Minimal window manager |
| **PouCon Application** | | |
| BEAM VM base | 50 - 100 MB | Erlang runtime |
| Phoenix server | 100 - 200 MB | LiveView processes |
| Equipment controllers | 50 - 100 MB | GenServers |
| DeviceManager + ETS | 20 - 50 MB | Device cache |
| Automation services | 30 - 50 MB | Schedulers |
| **Peak Application Total** | 250 - 500 MB | Under normal load |
| Chromium (if kiosk) | 200 - 500 MB | Single tab |

### Recommended RAM

- **Minimum (Headless)**: 1 GB
- **Recommended (Headless)**: 2 GB
- **With Local Browser**: 2-4 GB
- **Heavy Load/Debugging**: 4 GB

## 3.3 Hardware Recommendations

### Standard Configuration (Recommended)

| Item | Model/Spec | Price |
|------|-----------|-------|
| Raspberry Pi 4 | 4GB Model B | $55 |
| SD Card | SanDisk High Endurance 32GB | $12 |
| Power Supply | Official Pi 5V 3A USB-C | $10 |
| Enclosure | DIN rail mountable | $15 |
| **Total** | | **$92** |

### With Touchscreen

| Item | Model/Spec | Price |
|------|-----------|-------|
| Raspberry Pi 4 | 4GB Model B | $55 |
| SD Card | SanDisk High Endurance 32GB | $12 |
| Power Supply | Official Pi 5V 3A USB-C | $10 |
| Touchscreen | Official 7" DSI | $80 |
| Enclosure | Touchscreen compatible | $25 |
| **Total** | | **$182** |

### Industrial CM4 Options

For harsh environments or production deployments:

1. **Waveshare CM4-Panel-10.1-B** ($200-250) - Good documentation, worldwide availability
2. **Seeed Studio reTerminal DM** ($250-300) - Excellent software support
3. **Advantech TPC Series** ($500-700) - Enterprise-grade

**Minimum specs for poultry environment:**
- 10" screen (glove-friendly)
- IP65 rating (dust/moisture)
- Operating temp: -20°C to +60°C
- 24V DC power

## 3.4 SD Card Recommendations

**Recommended Brands:**
1. **SanDisk High Endurance** - Best for 24/7 use
2. **Samsung PRO Endurance** - Similar reliability

**Avoid:**
- Generic/cheap cards
- Cards rated for cameras only
- Amazon Basics (not industrial rated)

---

# 4. Cross-Platform Build

## 4.1 The Problem

Your development machine is **x86_64** (AMD64), but Raspberry Pi uses **ARM** architecture. Some dependencies use **NIFs** (Native Implemented Functions) - compiled C code that's architecture-specific.

**PouCon dependencies with NIFs:**
- `bcrypt_elixir` - Password hashing
- `ecto_sqlite3` - SQLite database bindings
- `circuits_uart` - Serial port communication

**This means you CANNOT directly copy a release built on x86_64 to ARM Raspberry Pi.**

## 4.2 Solutions Comparison

| Solution | Build Time | Setup Complexity | Recommended |
|----------|------------|------------------|-------------|
| Build on Pi | Slow (30-60 min) | Simple | For 1-2 deployments |
| **Docker ARM Emulation** | Medium (10-20 min) | Medium | **Best for multiple sites** |
| Pi Build Server | Fast (5-10 min) | Simple | Best overall if you have spare Pi |

## 4.3 Docker ARM Emulation (Recommended)

### One-Time Setup

```bash
# Run setup script
./scripts/setup_docker_arm.sh

# This installs:
# - Docker (if not already installed)
# - QEMU for ARM emulation
# - Docker buildx for multi-architecture builds
```

### Building for ARM

```bash
# Build ARM release
./scripts/build_arm.sh

# Creates: output/pou_con_release_arm.tar.gz
# Build time: ~10-20 minutes
```

### How It Works

The `Dockerfile.arm` uses Docker buildx with QEMU emulation:

```dockerfile
FROM hexpm/elixir:1.18.4-erlang-27.3.4.1-debian-bookworm-20251117-slim AS builder

# Build dependencies, compile, create release
# All happens in ARM64 emulation

FROM scratch AS export
COPY --from=builder /app/pou_con_release_arm.tar.gz /
```

## 4.4 Pi Build Server (Alternative)

If Docker feels too complex, use a spare Pi as build server:

```bash
# On development machine
cat > build_on_pi.sh << 'EOF'
#!/bin/bash
BUILD_PI="pi@build-pi.local"
rsync -av --delete \
  --exclude '_build' --exclude 'deps' --exclude '.git' \
  ./ "$BUILD_PI:~/pou_con/"

ssh "$BUILD_PI" << 'REMOTE'
cd ~/pou_con
export MIX_ENV=prod
mix deps.get --only prod
mix compile
mix assets.deploy
mix release
cd _build/prod/rel/pou_con
tar -czf ~/pou_con_release.tar.gz .
REMOTE

scp "$BUILD_PI:~/pou_con_release.tar.gz" ./
EOF
chmod +x build_on_pi.sh
```

**Build time: 5-10 minutes** (after initial setup, deps are cached)

---

# 5. Deployment Methods

## 5.1 Package Deployment

Best for: Single installations, testing new versions

### Creating the Package

```bash
./scripts/build_and_package.sh

# Or step by step:
./scripts/build_arm.sh
./scripts/create_deployment_package.sh
```

### Package Contents

```
deployment_package_YYYYMMDD_HHMMSS/
├── pou_con/           # Application release
├── deploy.sh          # Deployment script
├── backup.sh          # Backup script
├── uninstall.sh       # Uninstall script
├── setup_kiosk.sh     # Kiosk setup (optional)
└── README.txt         # Quick guide
```

### Deployment Steps

```bash
# 1. Transfer to Pi
scp pou_con_deployment_*.tar.gz pi@<pi-ip>:~/

# 2. SSH to Pi
ssh pi@<pi-ip>

# 3. Extract and deploy
tar -xzf pou_con_deployment_*.tar.gz
cd deployment_package_*/
sudo ./deploy.sh

# 4. Start service
sudo systemctl enable pou_con
sudo systemctl start pou_con
```

### What deploy.sh Does

1. Creates `pou_con` system user
2. Installs to `/opt/pou_con`
3. Creates database directory at `/var/lib/pou_con`
4. Configures serial port permissions
5. Installs systemd service
6. Generates SECRET_KEY_BASE
7. Runs database migrations

## 5.2 Master Image Deployment

**Best for: Multiple poultry houses, production deployments**

### Strategy

1. **Build once**: Create a "golden master" SD card with everything pre-installed
2. **Image it**: Create an image file from the master SD card
3. **Replicate**: Flash the image to new SD cards for each site
4. **Customize**: Run setup script for site-specific settings

### Phase 1: Create Master SD Card

**Step 1: Prepare Fresh Pi**

```bash
# Install Raspberry Pi OS, then:
sudo apt update
sudo apt upgrade -y
sudo apt install -y sqlite3 openssl ca-certificates locales libncurses5

# Set timezone
sudo timedatectl set-timezone Asia/Kuala_Lumpur
sudo locale-gen en_US.UTF-8
```

**Step 2: Deploy PouCon**

```bash
# Copy deployment package to Pi
scp pou_con_deployment_*.tar.gz pi@<pi-ip>:~/

# SSH and deploy
ssh pi@<pi-ip>
tar -xzf pou_con_deployment_*.tar.gz
cd deployment_package_*/
sudo ./deploy.sh
sudo systemctl enable pou_con
# Don't start yet - configure per-site later
```

**Step 3: Create Setup Script**

```bash
sudo nano /usr/local/bin/poucon-setup
```

Add the site configuration script (prompts for site name, hostname, static IP, etc.)

**Step 4: Create Image**

```bash
# On development machine with SD card reader
# Find SD card device
lsblk

# Create image (replace /dev/sdX with your device)
sudo dd if=/dev/sdX of=poucon_master_image.img bs=4M status=progress

# Compress (reduces ~32GB to ~2-4GB)
gzip -9 poucon_master_image.img
```

### Phase 2: Deploy to Sites

**Flash SD Card:**

```bash
# Linux
gunzip -c poucon_master_image.img.gz | sudo dd of=/dev/sdX bs=4M status=progress

# Windows: Use Balena Etcher or Raspberry Pi Imager
```

**At Site:**

```bash
# Boot Pi, then:
sudo poucon-setup

# Follow prompts for site name, hostname, IP, etc.
```

### Time Comparison

| Method | Time | Complexity |
|--------|------|------------|
| **Master Image** | **5 min** | **Very Low** |
| Package Deployment | 10 min | Low |
| Manual Setup | 30 min | Medium |

## 5.3 CM4 Deployment

### CM4 Types

**CM4 Lite (No eMMC):**
- Uses microSD card
- Deployment: **Identical to standard Pi**

**CM4 with eMMC:**
- Built-in storage
- Requires USB boot + rpiboot

### For CM4 Lite (SD Card)

Use any standard deployment method - works exactly the same as Pi 4.

### For CM4 with eMMC

**Prerequisites (one-time on dev machine):**

```bash
# Linux
sudo apt install git libusb-1.0-0-dev
git clone --depth=1 https://github.com/raspberrypi/usbboot
cd usbboot
make
```

**Flashing Process:**

1. Set boot jumper to USB Boot mode
2. Connect USB cable to CM4 carrier's slave port
3. Run rpiboot:
   ```bash
   sudo ./rpiboot
   ```
4. eMMC appears as USB storage (~10-20 seconds)
5. Flash with Raspberry Pi Imager or dd
6. Remove jumper, disconnect USB, boot normally

### CM4 with Vendor OS (Bookworm)

**For industrial panels with pre-installed OS:**

```bash
# 1. On dev machine - Build using Docker buildx
./scripts/build_arm.sh

# Creates output/pou_con_release_arm.tar.gz

# 2. Deploy to CM4
./scripts/deploy_to_cm4.sh <CM4-IP>

# Or build only (for manual deployment):
./scripts/deploy_to_cm4.sh --build-only
```

**Manual deployment:**

```bash
# Transfer release
scp output/pou_con_release_arm.tar.gz pi@<CM4-IP>:/tmp/

# SSH to CM4
ssh pi@<CM4-IP>

# Install dependencies (if not already)
sudo apt install -y sqlite3 libsqlite3-dev openssl

# Extract and configure
sudo mkdir -p /opt/pou_con
sudo tar -xzf /tmp/pou_con_release_arm.tar.gz -C /opt/pou_con
sudo chown -R pi:pi /opt/pou_con

# Create environment file
cat > /opt/pou_con/.env << 'EOF'
DATABASE_PATH=/opt/pou_con/data/pou_con_prod.db
SECRET_KEY_BASE=$(openssl rand -base64 48)
PHX_HOST=localhost
PORT=4000
MIX_ENV=prod
SIMULATE_DEVICES=0
EOF

# Initialize and start
mkdir -p /opt/pou_con/data
cd /opt/pou_con
export $(cat .env | xargs)
./bin/pou_con eval "PouCon.Release.migrate()"
```

### Vendor-Specific Drivers

**IMPORTANT:** Many CM4 industrial products require vendor-specific drivers.

**If vendor provides custom OS image, you MUST use it as base!**

| Product | Custom Drivers | Why |
|---------|---------------|-----|
| Waveshare CM4-Panel | YES | Custom touchscreen controller |
| Seeed reTerminal DM | YES | Custom display + touch + RTC |
| Advantech TPC series | YES | Proprietary I/O |
| Official CM4 IO Board | NO | Standard Pi hardware |

**Process with Vendor OS:**

1. Flash vendor OS image
2. Boot and verify hardware works (touch, display)
3. Deploy PouCon package on top
4. Create master image from configured unit
5. Flash to all other identical units

## 5.4 Existing System Deployment

For CM4 with Raspberry Pi OS Desktop already installed:

### Quick Start

```bash
# 1. Build using Bookworm Docker
./scripts/deploy_to_cm4.sh <CM4-IP>

# Or manually:
# Build
./scripts/build_arm.sh

# Transfer
scp output/pou_con_release_arm.tar.gz pi@<CM4-IP>:/tmp/

# SSH and install
ssh pi@<CM4-IP>
sudo apt update && sudo apt install -y sqlite3 libsqlite3-dev
sudo mkdir -p /opt/pou_con
sudo tar -xzf /tmp/pou_con_release_arm.tar.gz -C /opt/pou_con
sudo chown -R pi:pi /opt/pou_con
```

### Desktop Optimization

**Option 1: Headless (Best Performance)**

```bash
# Boot to console only (saves ~400MB RAM)
sudo raspi-config
# Choose: System Options → Boot → Console
# Or:
sudo systemctl set-default multi-user.target
```

**Option 2: Kiosk Mode (On-Site Display)**

See [Section 6: Touchscreen & Kiosk Setup](#6-touchscreen--kiosk-setup)

**Option 3: Keep Desktop (Convenience)**

```bash
# Disable unnecessary services
sudo systemctl disable bluetooth
sudo systemctl disable avahi-daemon
```

---

# 6. HTTPS & Multi-House Setup

## 6.1 Overview

PouCon supports secure HTTPS access across multiple poultry houses on the same network. Each house runs its own instance with a unique identifier.

**Architecture:**
```
Network (same router)
├── House 1: https://poucon.h1 (Pi @ 192.168.1.101)
├── House 2: https://poucon.h2 (Pi @ 192.168.1.102)
├── House 3: https://poucon.h3 (Pi @ 192.168.1.103)
└── User devices: iPad/mobile with CA cert installed
    └── /etc/hosts or router DNS maps hostnames to IPs
```

**Key Files:**
| File | Location | Purpose |
|------|----------|---------|
| `house_id` | `/etc/pou_con/house_id` | House identifier (e.g., "h1") |
| `server.crt` | `/etc/pou_con/ssl/server.crt` | SSL certificate for this house |
| `server.key` | `/etc/pou_con/ssl/server.key` | SSL private key |
| `ca.crt` | `/etc/pou_con/ssl/ca.crt` | CA certificate (same on all houses) |

**Ports:**
- HTTP (80): Redirects to HTTPS
- HTTPS (443): Main application

## 6.2 Certificate Authority Setup

Run **once** on your development machine to create a CA that signs certificates for all houses.

```bash
./scripts/setup_ca.sh
```

This creates:
- `priv/ssl/ca/ca.crt` - CA certificate (distribute to user devices)
- `priv/ssl/ca/ca.key` - CA private key (KEEP SECRET, use for signing)

**IMPORTANT:** Back up these files securely. If lost, you must regenerate and reinstall CA on all devices.

## 6.3 House Setup

Run on **each Raspberry Pi** to configure house identity and generate SSL certificate.

### Prerequisites

1. PouCon deployed via `deploy.sh` or `cm4_first_setup.sh`
2. CA files copied to Pi: `scp priv/ssl/ca/* pi@<pi-ip>:/tmp/`

### Setup Process

```bash
# SSH to the Pi
ssh pi@<pi-ip>

# Run house setup
./setup_house.sh
# Or if using deployment package:
/opt/pou_con/scripts/setup_house.sh
```

**Prompts:**
1. **House ID**: Enter identifier (e.g., `h1`, `house2`, `farm_a`)
   - Will be uppercased in UI display
   - Used to construct hostname: `poucon.<house_id>`

2. **Set system hostname?**: Recommended yes
   - Sets Pi's hostname to `poucon.<house_id>`

**What it does:**
1. Writes house_id to `/etc/pou_con/house_id`
2. Generates SSL certificate for `poucon.<house_id>`
3. Signs certificate with your CA
4. Installs certificates to `/etc/pou_con/ssl/`
5. Optionally sets system hostname

### After Setup

```bash
# Restart service to apply HTTPS
sudo systemctl restart pou_con

# Verify HTTPS is working
curl -k https://localhost
```

## 6.4 Client Device Setup

Users need two things to access houses via HTTPS:

### 1. Install CA Certificate (One-Time)

The CA certificate must be installed on each device that will access PouCon.

**iOS/iPadOS:**
1. Transfer `ca.crt` to device (AirDrop, email, or USB)
2. Open the file → "Profile Downloaded" notification appears
3. Settings → General → VPN & Device Management
4. Tap the profile and Install
5. Settings → General → About → Certificate Trust Settings
6. Enable full trust for your CA

**Android:**
1. Copy `ca.crt` to device
2. Settings → Security → Install from storage
3. Select `ca.crt`, name it (e.g., "PouCon Farm")
4. Install as "CA certificate"

**Windows:**
1. Double-click `ca.crt`
2. Install Certificate → Local Machine → Trusted Root Certification Authorities

**macOS:**
1. Double-click `ca.crt` to add to Keychain
2. Keychain Access → Find certificate → Get Info
3. Trust → Always Trust

### 2. Configure Hostname Resolution

Devices need to resolve `poucon.<house_id>` to the Pi's IP address.

**Option A: Router DNS (Recommended for multiple devices)**
- Access router admin panel
- Add DNS entries:
  ```
  poucon.h1 → 192.168.1.101
  poucon.h2 → 192.168.1.102
  ```

**Option B: Device /etc/hosts (Per-device)**

On each device, add to `/etc/hosts`:
```
192.168.1.101  poucon.h1
192.168.1.102  poucon.h2
192.168.1.103  poucon.h3
```

**iOS/Android:** Requires jailbreak/root or use a local DNS app.

### 3. Access the Application

Open browser and navigate to:
```
https://poucon.h1
https://poucon.h2
```

No port number needed (uses standard HTTPS port 443).

## 6.5 Troubleshooting HTTPS

**Certificate warnings in browser:**
- CA certificate not installed or not trusted
- Hostname doesn't match certificate (check `/etc/pou_con/house_id`)

**Connection refused:**
- Service not running: `sudo systemctl status pou_con`
- Firewall blocking ports 80/443: `sudo ufw allow 80,443/tcp`

**"NET::ERR_CERT_AUTHORITY_INVALID":**
- CA not trusted on device
- Re-install CA certificate and enable full trust

**Check certificate details:**
```bash
openssl x509 -in /etc/pou_con/ssl/server.crt -text -noout
```

---

# 7. Touchscreen & Kiosk Setup

## 7.1 Overview

**What kiosk mode does:**
- Pi boots directly to PouCon interface
- Fullscreen browser (no address bar, no menus)
- Touch input for controlling equipment
- Auto-restarts browser if it crashes
- No keyboard/mouse needed

## 7.2 Hardware Options

### Standard Pi + External Touchscreen

**Connection Types:**
- **DSI Display:** Official Pi 7" touchscreen (plug-and-play)
- **HDMI + USB Touch:** Most aftermarket displays

**Driver Support:** Usually automatic with Raspberry Pi OS

### Industrial Touch Panel PC

**Requires vendor drivers** - Use vendor's OS image as base.

**Recommended for poultry houses:**
- Waveshare CM4-Panel-10.1-B ($200-250)
- Seeed Studio reTerminal DM ($250-300)

## 7.3 Kiosk Setup

### Quick Setup

```bash
# After deploying PouCon
cd deployment_package_*/
./setup_kiosk.sh
sudo reboot
```

### Manual Setup

**Install packages:**

```bash
sudo apt update
sudo apt install -y chromium-browser unclutter xdotool
```

**Create kiosk script:**

```bash
mkdir -p ~/.local/bin
cat > ~/.local/bin/start_kiosk.sh << 'EOF'
#!/bin/bash
sleep 10
unclutter -idle 0.1 -root &
xset s off -dpms s noblank
chromium-browser \
  --kiosk \
  --noerrdialogs \
  --disable-infobars \
  --disable-session-crashed-bubble \
  --no-first-run \
  --disable-pinch \
  http://localhost:4000
EOF
chmod +x ~/.local/bin/start_kiosk.sh
```

**Create autostart entry:**

```bash
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
sudo raspi-config
# Select: System Options → Boot → Desktop Autologin
```

**Disable screen blanking:**

```bash
sudo mkdir -p /etc/X11/xorg.conf.d/
sudo cat > /etc/X11/xorg.conf.d/10-monitor.conf << 'EOF'
Section "ServerLayout"
    Identifier "ServerLayout0"
    Option "BlankTime" "0"
    Option "StandbyTime" "0"
    Option "SuspendTime" "0"
    Option "OffTime" "0"
EndSection
EOF
```

## 7.4 Industrial Panel Setup

**For vendor-provided panels:**

1. Download vendor OS image
2. Flash to panel
3. Verify touch works with vendor desktop
4. Deploy PouCon
5. Run kiosk setup
6. Test thoroughly

**Display orientation (if needed):**

```bash
sudo nano /boot/config.txt

# For HDMI:
display_hdmi_rotate=1  # 90° clockwise

# For DSI:
display_lcd_rotate=1
```

---

# 8. System Time Recovery

## 8.1 Problem: RTC Battery Failure

When the Raspberry Pi's RTC battery dies, the system clock resets after power failure. This causes:
- Log entries with wrong timestamps
- Scheduler confusion
- Report generation issues

## 8.2 One-Time Setup

Enable web-based time setting:

```bash
# Run once during deployment
sudo bash setup_sudo.sh
```

This allows the web application to set system time without password.

## 8.3 Recovery Steps

### Via Web Interface (Recommended)

1. Navigate to **Admin > System Time**
2. Click **"Use My Device's Current Time"**
3. Click **"Set System Time & Sync Hardware Clock"**
4. Click **"Time is Correct - Resume Logging"**

### Via SSH

```bash
ssh pi@<pi-ip>

# Set system time
sudo date -s "2025-12-29 14:30:00"

# Sync hardware clock
sudo hwclock --systohc

# Verify
date
```

## 8.4 Prevention

**Replace the RTC battery (CR2032)** - proper long-term fix.

**Enable NTP (if internet available):**

```bash
sudo timedatectl set-ntp true
```

---

# 9. Configuration

## 9.1 Environment Variables

Environment variables are stored in systemd service file:
`/etc/systemd/system/pou_con.service`

### Required Variables

| Variable | Purpose | Default |
|----------|---------|---------|
| `DATABASE_PATH` | SQLite database file | `/var/lib/pou_con/pou_con_prod.db` |
| `SECRET_KEY_BASE` | Cryptographic key | Auto-generated |

### Optional Variables

| Variable | Purpose | Default |
|----------|---------|---------|
| `PORT` | HTTP server port | `4000` |
| `PHX_HOST` | Hostname for URLs | `localhost` |
| `MIX_ENV` | Environment | `prod` |
| `POOL_SIZE` | DB connection pool | `5` |

## 9.2 Changing Configuration

```bash
# 1. Stop service
sudo systemctl stop pou_con

# 2. Edit service file
sudo nano /etc/systemd/system/pou_con.service

# 3. Modify Environment lines
# Example: Environment="PORT=8080"

# 4. Reload and restart
sudo systemctl daemon-reload
sudo systemctl start pou_con
```

## 9.3 Network Configuration

### Static IP

```bash
sudo nano /etc/dhcpcd.conf

# Add at the end:
interface eth0
static ip_address=192.168.1.100/24
static routers=192.168.1.1
static domain_name_servers=192.168.1.1 8.8.8.8

sudo systemctl restart dhcpcd
```

### WiFi

```bash
sudo nano /etc/wpa_supplicant/wpa_supplicant.conf

# Add:
network={
    ssid="YourNetworkName"
    psk="YourPassword"
}

sudo systemctl restart wpa_supplicant
```

---

# 10. Backup and Recovery

## 10.1 Automated Backup

```bash
# Schedule daily backups via cron
sudo crontab -e

# Add:
0 2 * * * /opt/pou_con_deployment/backup.sh
```

## 10.2 Manual Backup

```bash
# Create instant backup
sudo /opt/pou_con_deployment/backup.sh

# Copy to USB
sudo cp /var/backups/pou_con/pou_con_backup_*.tar.gz /media/pi/USB/
```

## 10.3 Restore from Backup

```bash
# Stop service
sudo systemctl stop pou_con

# Restore database
cd /tmp
tar -xzf /path/to/pou_con_backup_YYYYMMDD.tar.gz
sudo cp pou_con_prod.db /var/lib/pou_con/
sudo chown pou_con:pou_con /var/lib/pou_con/pou_con_prod.db

# Start service
sudo systemctl start pou_con
```

## 10.4 Replacing Failed Controller

**Quick Swap Process:**

1. Flash master image to new SD card (or use pre-flashed spare)
2. Boot new Pi
3. Run `sudo poucon-setup` (or deploy from package)
4. Restore database from backup
5. Verify operation

**Downtime: 5-15 minutes**

---

# 11. Troubleshooting

## 11.1 Service Won't Start

```bash
# Check logs
sudo journalctl -u pou_con -n 50

# Common fixes:
# 1. Database migration
sudo -u pou_con DATABASE_PATH=/var/lib/pou_con/pou_con_prod.db \
  /opt/pou_con/bin/pou_con eval "PouCon.Release.migrate"

# 2. Permission issues
sudo chown -R pou_con:pou_con /opt/pou_con /var/lib/pou_con

# 3. Port conflict
sudo netstat -tlnp | grep 4000
```

## 11.2 Cannot Access Web Interface

```bash
# Check service
systemctl status pou_con

# Test locally
curl http://localhost:4000

# Check firewall
sudo ufw allow 4000/tcp

# Find IP
hostname -I
```

## 11.3 Modbus Communication Errors

```bash
# Check USB devices
ls -l /dev/ttyUSB*

# Check permissions
sudo usermod -a -G dialout pou_con
sudo systemctl restart pou_con
```

## 11.4 Database Issues

```bash
# Check integrity
sqlite3 /var/lib/pou_con/pou_con_prod.db "PRAGMA integrity_check;"

# Reset (DELETES ALL DATA)
sudo systemctl stop pou_con
rm /var/lib/pou_con/pou_con_prod.db*
sudo -u pou_con DATABASE_PATH=/var/lib/pou_con/pou_con_prod.db \
  /opt/pou_con/bin/pou_con eval "PouCon.Release.migrate"
sudo systemctl start pou_con
```

## 11.5 Disk Space Issues

```bash
# Check usage
df -h

# Clean old logs
sudo journalctl --vacuum-time=7d
```

## 11.6 Touchscreen Issues

**Touch not detected:**
```bash
# Check devices
xinput list
ls /dev/input/event*

# Test events
sudo evtest
```

**Touch works in console but not X11:**
```bash
sudo apt install -y xserver-xorg-input-libinput
sudo systemctl restart lightdm
```

**Touch calibration off:**
```bash
sudo apt install xinput-calibrator
DISPLAY=:0.0 xinput_calibrator
```

## 11.7 Build Fails

**Docker not found:**
```bash
./scripts/setup_docker_arm.sh
```

**Permission denied:**
```bash
sudo usermod -aG docker $USER
# Log out and back in
```

**Platform not supported:**
```bash
docker buildx rm multiarch
./scripts/setup_docker_arm.sh
```

---

# 12. Scripts Reference

## 12.1 Build Scripts

| Script | Purpose |
|--------|---------|
| `setup_docker_arm.sh` | One-time Docker + buildx setup |
| `build_arm.sh` | Build ARM release using Dockerfile.arm |
| `create_deployment_package.sh` | Create deployment tarball |
| `build_and_package.sh` | All-in-one: build + package |

## 12.2 Deployment Scripts

| Script | Purpose |
|--------|---------|
| `deploy_to_cm4.sh` | Automated deployment to CM4 |
| `cm4_first_setup.sh` | First-time CM4 setup |
| `setup_ca.sh` | Create Certificate Authority (run once) |
| `setup_house.sh` | Configure house_id + SSL cert (run per house) |
| `setup_kiosk.sh` | Configure kiosk mode |

## 12.3 Package Scripts (Inside deployment package)

| Script | Purpose |
|--------|---------|
| `deploy.sh` | Install PouCon on Pi |
| `backup.sh` | Create database backup |
| `uninstall.sh` | Remove PouCon |

## 12.4 Usage Examples

```bash
# Build and package
./scripts/build_and_package.sh

# Deploy to CM4 with IP
./scripts/deploy_to_cm4.sh 192.168.1.100

# Build only (no deploy)
./scripts/deploy_to_cm4.sh --build-only

# Setup kiosk on Pi
./scripts/setup_kiosk.sh
```

---

# 13. Quick Reference

## 13.1 Service Commands

```bash
sudo systemctl start pou_con      # Start
sudo systemctl stop pou_con       # Stop
sudo systemctl restart pou_con    # Restart
sudo systemctl status pou_con     # Status
sudo systemctl enable pou_con     # Enable on boot
```

## 13.2 Log Commands

```bash
sudo journalctl -u pou_con -f          # Follow logs
sudo journalctl -u pou_con -n 100      # Last 100 lines
sudo journalctl -u pou_con --since today
```

## 13.3 System Commands

```bash
hostname -I                       # Get IP address
df -h                             # Check disk space
free -h                           # Check memory
ls -l /dev/ttyUSB*                # Check USB devices
sudo reboot                       # Reboot
sudo shutdown -h now              # Shutdown
```

## 13.4 Database Commands

```bash
sqlite3 /var/lib/pou_con/pou_con_prod.db
# Inside SQLite:
.tables                           # List tables
.schema equipment                 # Show table schema
SELECT * FROM equipment;          # Query data
.quit                             # Exit
```

## 13.5 File Locations

**On Development Machine:**
```
pou_con/
├── Dockerfile.arm                 # ARM build definition
├── scripts/
│   ├── setup_docker_arm.sh        # One-time Docker setup
│   ├── build_arm.sh               # Build ARM release
│   ├── create_deployment_package.sh
│   ├── build_and_package.sh       # All-in-one
│   ├── deploy_to_cm4.sh           # CM4 deployment
│   ├── cm4_first_setup.sh         # CM4 first setup
│   └── setup_kiosk.sh             # Kiosk setup
├── output/
│   └── pou_con_release_arm.tar.gz # ARM release
└── pou_con_deployment_*.tar.gz    # Deployment package
```

**On Raspberry Pi:**
```
/opt/pou_con/                      # Application
/var/lib/pou_con/                  # Database
/var/log/pou_con/                  # Logs
/var/backups/pou_con/              # Backups
/etc/systemd/system/pou_con.service # Service config
/etc/pou_con/house_id              # House identifier
/etc/pou_con/ssl/                  # SSL certificates
  ├── server.crt                   # Server certificate
  ├── server.key                   # Server private key
  └── ca.crt                       # CA certificate
```

## 13.6 Default Credentials

- **Web Interface:** `admin` / `admin`
- **SSH:** `pi` / (your password)

**CHANGE DEFAULT PASSWORDS IMMEDIATELY!**

## 13.7 Port Numbers

| Service | Port | Notes |
|---------|------|-------|
| PouCon HTTPS | 443 | Production (with HTTPS setup) |
| PouCon HTTP | 80 | Redirects to HTTPS |
| PouCon Dev | 4000 | Development mode |
| SSH | 22 | |
| Modbus TCP (if used) | 502 | |

---

# Appendix: Deployment Checklist

## Pre-Deployment (Office)

- [ ] Build production release
- [ ] Create deployment package
- [ ] Run `setup_ca.sh` (if not already done)
- [ ] Copy CA files (ca.crt, ca.key) to USB drive
- [ ] Prepare master SD card image (if applicable)
- [ ] Copy deployment package to USB drive
- [ ] Pack hardware (Pi, SD cards, adapters, cables)

## On-Site Deployment

- [ ] Flash SD card (if new Pi)
- [ ] Connect RS485 adapters
- [ ] Boot Pi and verify USB devices detected
- [ ] Deploy application
- [ ] Enable service
- [ ] Run `setup_house.sh` (enter house_id, generate SSL cert)
- [ ] Start service
- [ ] Verify HTTPS accessible (`https://poucon.<house_id>`)
- [ ] **Change admin password**
- [ ] Configure ports and devices
- [ ] Configure equipment
- [ ] Test manual control
- [ ] Configure automation
- [ ] Test automation
- [ ] Create initial backup
- [ ] Document IP address, house_id, and location
- [ ] Label Pi with house_id

## Post-Deployment

- [ ] Configure client devices:
  - [ ] Install CA certificate on iPads/phones
  - [ ] Add hostname to router DNS or device /etc/hosts
- [ ] Monitor for 24 hours
- [ ] Review logs for errors
- [ ] Train operators
- [ ] Schedule maintenance check
- [ ] Update deployment inventory

---

**Document Version:** 1.0
**Last Updated:** December 2025
**Generated from:** Combined project documentation files

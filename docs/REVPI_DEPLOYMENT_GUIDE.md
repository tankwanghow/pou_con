# RevPi Connect 5 Deployment Guide

This guide covers deploying PouCon on a Revolution Pi Connect 5 industrial controller.

## Hardware Overview

| Feature | RevPi Connect 5 | Raspberry Pi 4 | Impact on PouCon |
|---------|-----------------|----------------|------------------|
| CPU | ARM Cortex-A76 @ 2.4GHz | ARM Cortex-A72 @ 1.5GHz | Faster, no code change |
| RAM | 4GB or 8GB | 1-8GB | More headroom |
| OS | Raspberry Pi OS (Debian) | Raspberry Pi OS | **Same - no code change** |
| Ethernet | 2x Gigabit PCIe | 1x Gigabit | Better for Modbus TCP |
| RS485 | Optional built-in | USB adapter required | Different port path |
| Form Factor | DIN rail industrial | Consumer SBC | No code change |
| Temperature | -40°C to 55°C | 0°C to 50°C | Better for farm |
| Certifications | CE, UL, FCC | CE, FCC | Industrial grade |

## Code Changes Required

### Summary: Minimal to Zero Changes

The PouCon adapter-based architecture means **no application code changes** are needed. Only configuration may need adjustment:

| Component | Change Required | Details |
|-----------|-----------------|---------|
| Equipment Controllers | None | Hardware-agnostic |
| DataPointManager | None | Uses adapter pattern |
| Modbus Adapter | None | Same library works |
| Phoenix/LiveView | None | Standard Elixir |
| Database (SQLite) | None | Works everywhere |
| Build Process | Minor | Same Dockerfile |
| Serial Port Path | Config only | `/dev/ttyAMA0` vs `/dev/ttyUSB0` |

### Serial Port Configuration

The only difference is the serial port path if using RevPi's **built-in RS485**:

| Hardware | Serial Port Path | Notes |
|----------|------------------|-------|
| USB Adapter (current) | `/dev/ttyUSB0` | Works on RevPi too |
| RevPi Built-in RS485 | `/dev/ttyAMA0` or `/dev/serial0` | Built-in option |
| RevPi RS485 Module | `/dev/ttyRS485` | Expansion module |

**No code change needed** - you configure the port path in the Admin UI when adding ports.

## RevPi Connect 5 Variants

| Model | Part Number | RAM | RS485 | CAN | WiFi | Price |
|-------|-------------|-----|-------|-----|------|-------|
| RevPi Connect 5 | 100564 | 4GB | No | No | No | ~$280 |
| RevPi Connect 5 8GB | 100565 | 8GB | No | No | No | ~$320 |
| RevPi Connect 5 RS485 | 100566 | 4GB | **Yes** | No | No | ~$300 |
| RevPi Connect 5 8GB RS485 | 100567 | 8GB | **Yes** | No | No | ~$340 |
| RevPi Connect 5 CAN | 100568 | 4GB | No | Yes | No | ~$300 |
| RevPi Connect 5 WiFi | 100572 | 4GB | No | No | Yes | ~$300 |

**Recommended for PouCon**: RevPi Connect 5 RS485 (100566) or 8GB RS485 (100567)
- Built-in RS485 eliminates USB adapter
- More reliable industrial-grade RS485 transceiver
- 4-pin screw terminals for easy wiring

## Deployment Steps

### Phase 1: Order Hardware

**Required:**
- RevPi Connect 5 RS485 (100566 or 100567)
- 24V DC power supply (9-36V DC input range)
- DIN rail for mounting

**Optional but Recommended:**
- RevPi flat ribbon cable (for expansion modules)
- Additional RS485 USB adapter (if more than 1 RS485 bus needed)

### Phase 2: Prepare RevPi (First Boot)

1. **Download RevPi Image**
   - Go to: https://revolutionpi.com/tutorials/downloads
   - Download: "RevPi Bookworm Image" (Debian 12-based)
   - Write to SD card using Raspberry Pi Imager

2. **First Boot Setup**
   ```bash
   # Default credentials
   Username: pi
   Password: raspberry

   # CHANGE PASSWORD IMMEDIATELY
   passwd

   # Enable SSH (if not enabled)
   sudo systemctl enable ssh
   sudo systemctl start ssh

   # Update system
   sudo apt update && sudo apt upgrade -y
   ```

3. **Configure Network**
   ```bash
   # RevPi has 2 Ethernet ports - configure static IP for control network
   sudo nmcli con mod "Wired connection 1" ipv4.addresses 192.168.1.100/24
   sudo nmcli con mod "Wired connection 1" ipv4.gateway 192.168.1.1
   sudo nmcli con mod "Wired connection 1" ipv4.method manual
   sudo nmcli con up "Wired connection 1"
   ```

### Phase 3: Verify Hardware

Run the hardware verification script (included in deployment package):

```bash
# After extracting deployment package
sudo ./verify_revpi_hardware.sh
```

Expected output:
```
═══════════════════════════════════════════
  RevPi Connect 5 Hardware Verification
═══════════════════════════════════════════

1. System Information
   Model: RevPi Connect 5
   CPU: ARM Cortex-A76 (4 cores @ 2.4GHz)
   RAM: 8GB
   OS: Debian GNU/Linux 12 (bookworm)
   Kernel: 6.6.x-revpi

2. Serial Ports
   ✓ /dev/ttyAMA0 - Built-in RS485 (if RS485 variant)
   ✓ /dev/ttyUSB0 - USB Serial Adapter (if connected)

3. Network Interfaces
   ✓ eth0: 192.168.1.100/24 (up)
   ✓ eth1: not configured (up)

4. Storage
   ✓ eMMC: 32GB (28GB free)
   ✓ SD Card: not present

5. RevPi Specific
   ✓ PiBridge communication: OK
   ✓ RS485 interface: Available at /dev/ttyAMA0

═══════════════════════════════════════════
  All checks passed - ready for deployment
═══════════════════════════════════════════
```

### Phase 4: First-Time Setup (Optional)

For fresh RevPi installations, you can run the first-time setup script to prepare the system:

```bash
# On RevPi Connect 5 (run once for new installations)
sudo ./revpi_first_setup.sh
```

This script:
- Updates system packages
- Installs system dependencies
- Creates the `pou_con` user with home directory at `/home/pou_con`
- Adds `pou_con` to required groups (dialout, video, input, render, audio)
- Configures serial ports and log rotation
- Sets up file descriptor limits for BEAM

### Phase 5: Deploy PouCon

The deployment process is **identical** to Raspberry Pi:

```bash
# On your development machine
./scripts/build_arm.sh
./scripts/create_deployment_package.sh

# Copy to USB drive
cp pou_con_deployment_*.tar.gz /media/usb-drive/

# On RevPi Connect 5
cd /media/pi/usb-drive/
tar -xzf pou_con_deployment_*.tar.gz
cd deployment_package_*/
sudo ./deploy.sh
```

The `deploy.sh` script will create the `pou_con` user if it doesn't exist (as a regular user with home directory).

### Phase 6: Configure Ports

After deployment, configure your Modbus ports via Admin UI:

**If using built-in RS485:**
```
Admin → Ports → Add Port
  Name: modbus_rs485
  Type: Modbus RTU
  Device Path: /dev/ttyAMA0   ← RevPi built-in RS485
  Baud Rate: 9600
  Parity: None
  Stop Bits: 1
```

**If using USB adapter:**
```
Admin → Ports → Add Port
  Name: modbus_usb
  Type: Modbus RTU
  Device Path: /dev/ttyUSB0   ← Same as Raspberry Pi
  Baud Rate: 9600
  Parity: None
  Stop Bits: 1
```

## Serial Port Wiring (Built-in RS485)

RevPi Connect 5 RS485 uses 4-pin screw terminals:

```
┌─────────────────────────────────────┐
│  RevPi Connect 5 RS485 Terminals    │
├─────────────────────────────────────┤
│  Pin 1: A+ (Data+)                  │
│  Pin 2: B- (Data-)                  │
│  Pin 3: GND (Signal Ground)         │
│  Pin 4: Shield (optional)           │
└─────────────────────────────────────┘

Wiring to Waveshare Modbus IO:
  RevPi A+  ──────── Waveshare A+
  RevPi B-  ──────── Waveshare B-
  RevPi GND ──────── Waveshare GND
```

**Important**: RS485 is differential signaling - polarity matters!

## Troubleshooting

### Serial Port Not Found

```bash
# Check if RS485 interface is enabled
ls -la /dev/ttyAMA* /dev/serial*

# If not found, check device tree
cat /boot/config.txt | grep uart

# Enable UART if needed
echo "enable_uart=1" | sudo tee -a /boot/config.txt
sudo reboot
```

### Permission Denied on Serial Port

```bash
# Add pou_con user to dialout group
sudo usermod -a -G dialout pou_con

# Restart service
sudo systemctl restart pou_con
```

### Built-in RS485 vs GPIO UART

RevPi Connect 5 RS485 variant has a **dedicated RS485 transceiver** (not just GPIO UART):
- Automatic direction control (DE/RE)
- ESD protection
- Better noise immunity
- No need for external RS485-to-UART converter

## RevPi-Specific Features (Future)

The RevPi Connect 5 has additional features that could be leveraged in future:

### 1. PiBridge Expansion Bus
Connect RevPi I/O modules directly without Modbus:
- RevPi DIO (digital I/O)
- RevPi AIO (analog I/O)
- RevPi MIO (mixed I/O)

This would require a new adapter implementation but could provide faster, more reliable I/O.

### 2. Dual Ethernet
- Use eth0 for control network (Modbus devices)
- Use eth1 for management network (web UI access)

### 3. Real-Time Kernel
RevPi supports PREEMPT_RT patches for deterministic timing - useful for time-critical control loops.

## Comparison: RevPi vs Raspberry Pi for PouCon

| Aspect | RevPi Connect 5 | Raspberry Pi 4 | Winner |
|--------|-----------------|----------------|--------|
| **Reliability** | Industrial-grade, -40°C to 55°C | Consumer-grade, 0°C to 50°C | RevPi |
| **RS485** | Built-in option (robust) | USB adapter (can disconnect) | RevPi |
| **Mounting** | DIN rail included | Needs case/bracket | RevPi |
| **Certifications** | CE, UL, FCC | CE, FCC | RevPi |
| **Price** | ~$300-350 | ~$75 + case + adapter | RPi cheaper |
| **Availability** | Industrial distributors | Consumer retail | RPi easier |
| **Support** | KUNBUS (German company) | Raspberry Pi Foundation | Both good |
| **PouCon Compatibility** | 100% | 100% | Tie |

## Conclusion

RevPi Connect 5 is an excellent upgrade path for PouCon deployments requiring:
- Industrial reliability
- Extreme temperature environments
- Built-in RS485 communication
- DIN rail mounting
- Professional certifications

**The PouCon code runs unchanged** - only the serial port path configuration differs when using built-in RS485.

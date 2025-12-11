# Raspberry Pi CM4 Deployment Notes

This document covers deployment differences when using Raspberry Pi Compute Module 4 (CM4) instead of standard Raspberry Pi.

## CM4 Overview

The Compute Module 4 (CM4) is a compact form factor of Raspberry Pi designed for embedded and industrial applications. It's commonly found in:
- Industrial panel PCs
- Custom carrier boards
- DIN rail mounted controllers
- Rugged industrial enclosures

### CM4 Variants

**CM4 Lite** (No eMMC):
- Uses microSD card on carrier board
- Deployment: **Identical to standard Raspberry Pi**
- Storage: 16GB+ microSD card recommended

**CM4 with eMMC** (Most common in industrial products):
- Built-in 8GB, 16GB, or 32GB eMMC storage
- Deployment: **Different process** (see below)
- Storage: Faster and more reliable than SD cards

## Deployment Methods by CM4 Type

### For CM4 Lite (With SD Card Slot)

**Deployment: 100% Same as Standard Pi**

Use any of these methods:
1. ⭐ **Master Image Deployment** (recommended)
   - Flash image to microSD card
   - Insert into carrier board SD slot
   - Boot and run setup

2. **Package Deployment**
   - Boot Raspberry Pi OS from SD card
   - Deploy package normally

See **[MASTER_IMAGE_DEPLOYMENT.md](MASTER_IMAGE_DEPLOYMENT.md)** - works exactly the same.

### For CM4 with eMMC (No SD Card)

**Deployment: Requires USB Boot & rpiboot**

The eMMC storage must be flashed via USB using the `rpiboot` tool.

#### Prerequisites

**On your development machine (one-time install):**

**Linux:**
```bash
sudo apt install git libusb-1.0-0-dev
git clone --depth=1 https://github.com/raspberrypi/usbboot
cd usbboot
make
sudo ./rpiboot
```

**Windows:**
- Download Raspberry Pi Imager
- Or download rpiboot installer from https://github.com/raspberrypi/usbboot/raw/master/win32/rpiboot_setup.exe

**macOS:**
```bash
brew install libusb
git clone --depth=1 https://github.com/raspberrypi/usbboot
cd usbboot
make
sudo ./rpiboot
```

#### Flashing eMMC Storage

**Method 1: Using Raspberry Pi Imager (Easiest)**

1. **Put CM4 into USB boot mode:**
   - On carrier board: Set "Boot" jumper or switch to "USB Boot"
   - Common locations:
     - Waveshare boards: J14 jumper (disable eMMC boot)
     - Official IO Board: Fit jumper on J2 (disable eMMC boot)
   - Connect USB to carrier board's USB slave port (usually micro-USB)

2. **Run rpiboot to expose eMMC as USB storage:**
   ```bash
   sudo ./rpiboot
   ```

   After 10-20 seconds, eMMC appears as USB storage device

3. **Flash with Raspberry Pi Imager:**
   - Open Raspberry Pi Imager
   - Select your master image or Raspberry Pi OS
   - Select the CM4 eMMC device (usually shows as "RPi-MSD-xxxx")
   - Click "Write"

4. **Disconnect and boot normally:**
   - Remove USB cable
   - Remove boot jumper (re-enable eMMC boot)
   - Power on CM4

**Method 2: Using dd (Advanced)**

```bash
# 1. Put CM4 in USB boot mode (jumper + USB connection)
sudo ./rpiboot

# 2. Find eMMC device
lsblk
# Look for device named similar to /dev/sda or /dev/mmcblk0

# 3. Flash master image
gunzip -c poucon_master_image.img.gz | sudo dd of=/dev/sda bs=4M status=progress

# 4. Sync and disconnect
sync
sudo eject /dev/sda
```

## IMPORTANT: Vendor-Specific Drivers and OS Images

### ⚠️ Critical Consideration for Industrial Products

**Many CM4-based industrial products require vendor-specific drivers:**

- **Touchscreen drivers** (especially resistive or multi-touch panels)
- **Display drivers** (custom LCD controllers, LVDS, MIPI-DSI)
- **GPIO expanders** (additional I/O on carrier board)
- **CAN bus controllers** (industrial communication)
- **RS485/RS232 drivers** (some carriers use USB-serial chips)
- **RTC (Real-Time Clock)** drivers
- **Watchdog timer** drivers
- **Custom power management**

### **IMPORTANT RULE:**

**If the vendor provides a custom OS image, you MUST use it as the base!**

❌ **DO NOT** flash generic Raspberry Pi OS to products with custom hardware
✅ **DO** use vendor's OS image and deploy PouCon on top

### How to Check if You Need Vendor OS

**Before deploying, check vendor documentation for:**

1. **"System Image Download"** section
2. **"Custom drivers required"** warnings
3. **"Touch calibration"** instructions
4. **"Hardware-specific setup"** notes

**If any of these exist → Use vendor OS image as base**

### Examples of Products Requiring Vendor OS

| Product | Custom Drivers Needed | Why |
|---------|----------------------|-----|
| Waveshare CM4-Panel series | YES | Custom touchscreen controller |
| Seeed reTerminal DM | YES | Custom display + touch + RTC |
| Advantech TPC series | YES | Proprietary I/O, watchdog |
| Official CM4 IO Board | NO | Standard Raspberry Pi hardware |
| Generic CM4 carrier boards | MAYBE | Check if uses standard Pi GPIO/HDMI |

## Master Image Creation for CM4

### Decision Tree: Which OS Base to Use?

```
Does vendor provide custom OS image?
│
├─ YES → Use vendor OS as base
│   │
│   ├─ Flash vendor OS to CM4
│   ├─ Deploy PouCon package (not master image)
│   └─ Test ALL hardware (touch, display, I/O)
│
└─ NO → Can use generic Raspberry Pi OS
    │
    └─ Create master image normally
```

### Option A: Vendor OS Base (RECOMMENDED for Industrial Products)

**Use this when:**
- Vendor provides custom OS image
- Product has touchscreen
- Product has custom I/O or peripherals
- Product manual mentions "custom drivers"

**Process:**

1. **Download vendor OS image:**
   ```bash
   # Example: Waveshare CM4-Panel-10.1-B
   # Download from: https://www.waveshare.com/wiki/CM4-Panel-10.1-B
   # File: CM4-Panel-10.1-B-image-xxxx-xx-xx.img.xz
   ```

2. **Flash vendor OS to one CM4:**
   ```bash
   # Decompress if needed
   unxz CM4-Panel-10.1-B-image.img.xz

   # Flash via rpiboot (for eMMC) or to SD card
   sudo ./rpiboot
   sudo dd if=CM4-Panel-10.1-B-image.img of=/dev/sda bs=4M status=progress
   ```

3. **Boot and verify hardware works:**
   - Test touchscreen
   - Test display
   - Test GPIO/I/O if applicable
   - Test RS485/serial ports

4. **Deploy PouCon on top of vendor OS:**
   ```bash
   # SSH to the CM4 running vendor OS
   scp pou_con_deployment_*.tar.gz pi@<cm4-ip>:~/

   ssh pi@<cm4-ip>
   tar -xzf pou_con_deployment_*.tar.gz
   cd deployment_package_*/
   sudo ./deploy.sh
   sudo systemctl enable pou_con
   sudo systemctl start pou_con
   ```

5. **Create master image from this CM4:**
   ```bash
   # Put CM4 back in USB boot mode
   sudo ./rpiboot

   # Create master image with vendor OS + PouCon
   sudo dd if=/dev/sda of=poucon_waveshare_cm4_master.img bs=4M status=progress
   gzip -9 poucon_waveshare_cm4_master.img
   ```

6. **Flash this master to all other identical units:**
   ```bash
   # All units of same model get this image
   gunzip -c poucon_waveshare_cm4_master.img.gz | sudo dd of=/dev/sda bs=4M
   ```

**Result:** Master image includes vendor drivers + PouCon

### Option B: Generic Raspberry Pi OS Base

**Only use when:**
- Official CM4 IO Board (no custom hardware)
- Generic carrier board using standard Pi GPIO/HDMI
- Vendor confirms "Standard Raspberry Pi OS compatible"
- No touchscreen or uses standard DSI/HDMI touch

**This works!** ✅

Raspberry Pi OS is compatible across all Pi models (Pi 3B+, Pi 4, CM4).

1. Create master image on standard Pi 4
2. Flash to CM4 eMMC
3. First boot will auto-detect CM4 hardware

**Note:** Image size must fit on eMMC (e.g., 16GB image fits on 16GB+ eMMC)

### Option C: Create on CM4, Use on CM4 (Generic OS)

**For generic carrier boards without custom drivers** ✅

If you have CM4 IO Board or generic carrier:
1. Set up PouCon on CM4 with IO board
2. Boot CM4 in USB boot mode
3. Run rpiboot on dev machine
4. Create image from eMMC:
   ```bash
   sudo dd if=/dev/sda of=poucon_cm4_master.img bs=4M status=progress
   gzip -9 poucon_cm4_master.img
   ```

## Vendor-Specific Deployment Examples

### Example 1: Waveshare CM4-Panel-10.1-B

**Hardware:**
- 10.1" capacitive touchscreen
- Custom touch controller (goodix)
- Custom display driver
- RTC with battery

**Requires:** Vendor OS image ✅

**Process:**

```bash
# 1. Download from Waveshare wiki
wget https://files.waveshare.com/upload/...CM4-Panel-10.1-B-image.img.xz

# 2. Decompress
unxz CM4-Panel-10.1-B-image.img.xz

# 3. Flash to first panel (via USB boot mode)
sudo ./rpiboot
sudo dd if=CM4-Panel-10.1-B-image.img of=/dev/sda bs=4M status=progress

# 4. Boot and verify touch works
# 5. Deploy PouCon package
scp pou_con_deployment_*.tar.gz pi@<panel-ip>:~/
ssh pi@<panel-ip>
tar -xzf pou_con_deployment_*.tar.gz
cd deployment_package_*/
sudo ./deploy.sh

# 6. Set up kiosk mode (from TOUCHSCREEN_KIOSK_SETUP.md)
sudo ./setup_kiosk.sh

# 7. Test thoroughly (touch, display, PouCon interface)

# 8. Create master image
sudo ./rpiboot
sudo dd if=/dev/sda of=poucon_waveshare_panel_master.img bs=4M status=progress
gzip -9 poucon_waveshare_panel_master.img

# 9. Flash to all other Waveshare panels
gunzip -c poucon_waveshare_panel_master.img.gz | sudo dd of=/dev/sda bs=4M
```

**Result:** All Waveshare panels work perfectly with touch + PouCon

### Example 2: Seeed Studio reTerminal DM

**Hardware:**
- 7" touchscreen
- Built-in RTC, accelerometer, buzzer
- Watchdog timer
- DIN rail enclosure

**Requires:** Seeed vendor OS ✅

**Key differences:**
- Uses custom device tree overlays
- Requires specific kernel modules
- Touch driver built into kernel

**Download vendor OS from:** https://wiki.seeedstudio.com/reTerminal-DM/

**Process:** Same as Waveshare example above

### Example 3: Generic DIN Rail CM4 Carrier

**Hardware:**
- CM4 on basic carrier board
- Standard Raspberry Pi GPIO
- RS485 via standard USB-serial adapter
- HDMI display (no touch)

**Requires:** Generic Raspberry Pi OS ✅

**Process:**
```bash
# Can use standard Pi 4 master image
# OR create on CM4 IO Board
# No vendor drivers needed
```

## Industrial Panel PCs with CM4

Many industrial touch panel PCs use CM4 internally. Common brands:
- Waveshare CM4 Panel Series
- Seeed Studio reTerminal DM
- Advantech TPC Series
- Variscite VAR-DT8M

### Typical Deployment Process

1. **Check vendor documentation:**
   - Does it use CM4 Lite (SD card) or CM4 with eMMC?
   - Where is the USB slave port?
   - How to enable USB boot mode?

2. **For CM4 with eMMC panels:**
   - Most have accessible USB port and boot jumper/switch
   - Use rpiboot method to flash eMMC
   - Some vendors provide custom OS images (use those as base)

3. **For CM4 Lite panels:**
   - Flash SD card normally
   - Insert into panel's SD slot

### Example: Waveshare CM4-Panel-10.1-B

**Specifications:**
- CM4 module: Can be ordered with or without eMMC
- Storage: CM4 eMMC or microSD slot on board
- USB Boot: J14 jumper to disable eMMC

**Deployment:**

**If ordered with CM4 Lite (SD card):**
```bash
# Flash SD card normally
gunzip -c poucon_master_image.img.gz | sudo dd of=/dev/sdX bs=4M

# Insert into panel SD slot, boot
```

**If ordered with CM4 eMMC:**
```bash
# 1. Set J14 jumper (disable eMMC)
# 2. Connect micro-USB to host
# 3. Power on panel

# 4. On dev machine:
sudo ./rpiboot

# 5. Flash eMMC
gunzip -c poucon_master_image.img.gz | sudo dd of=/dev/sda bs=4M status=progress

# 6. Disconnect, remove jumper, reboot
```

## Carrier Board Compatibility

### Official Raspberry Pi CM4 IO Board

**Perfect for testing and development**
- Full breakout of all CM4 features
- PCIe slot, dual HDMI, Gigabit Ethernet
- USB boot jumper (J2)
- SD card slot (for CM4 Lite)

**Deployment same as standard Pi**

### Industrial Carrier Boards

Examples:
- Waveshare CM4-IO-BASE-A/B/C
- Seeed Studio reComputer (DIN rail)
- Advantech VEGA-300 series
- Custom OEM boards

**Check for:**
- eMMC vs SD card
- Location of USB boot enable (jumper/switch/button)
- USB slave port location
- Power input requirements

## eMMC vs SD Card Considerations

### eMMC Advantages (Recommended for Production)

✅ **Reliability:**
- No physical removal/insertion wear
- Better vibration/shock resistance
- Lower failure rate

✅ **Performance:**
- Faster read/write speeds
- Lower latency
- Better suited for industrial environments

✅ **Security:**
- Can't be easily removed and copied
- More difficult to tamper with

### eMMC Disadvantages

❌ **Deployment complexity:**
- Requires rpiboot tool
- Requires USB connection to dev machine
- Can't swap like SD cards

❌ **Recovery:**
- Can't just swap SD card for quick fix
- Need USB boot process for reflashing

### Recommendation

**For production poultry houses:** Use CM4 with eMMC
- More reliable in dusty/humid environments
- Better long-term durability
- Worth the extra deployment complexity

**For development/testing:** Use CM4 Lite or standard Pi
- Easy to swap SD cards
- Quick iteration
- Standard workflow

## Deployment Workflow Comparison

### Standard Pi / CM4 Lite (SD Card)

```bash
# At office: Flash SD card
gunzip -c poucon_master_image.img.gz | sudo dd of=/dev/sdX bs=4M

# At site: Insert and boot
# Done in 5 minutes
```

### CM4 with eMMC

```bash
# At office: Prepare CM4
# 1. Set boot jumper
# 2. Connect USB
sudo ./rpiboot
gunzip -c poucon_master_image.img.gz | sudo dd of=/dev/sda bs=4M

# At site: Install in enclosure
# 1. Remove jumper
# 2. Boot normally
# Done in 10 minutes
```

## Common CM4 Carrier Boards Reference

| Carrier Board | Storage | USB Boot | Notes |
|---------------|---------|----------|-------|
| Official IO Board | eMMC or SD | J2 jumper | Best for dev/test |
| Waveshare CM4-IO-BASE-B | eMMC or SD | J14 jumper | DIN rail option available |
| Seeed reComputer | eMMC | Button on board | Includes aluminum case |
| Waveshare CM4-Panel-10.1 | eMMC or SD | J14 jumper | Touchscreen included |
| Advantech VEGA-300 | eMMC | BIOS setting | Industrial grade |

## Troubleshooting CM4 Deployment

### rpiboot not detecting CM4

**Check:**
```bash
# Verify USB connection
lsusb | grep -i "Raspberry\|Broadcom"
# Should show: "ID 0a5c:2711 Broadcom Corp. BCM2711 Boot"
```

**If not detected:**
1. Verify boot jumper is set correctly
2. Check USB cable (data cable, not charge-only)
3. Try different USB port
4. Power cycle the CM4

### eMMC appears as /dev/sda but won't flash

**Issue:** eMMC smaller than image size

**Solution:**
```bash
# Check eMMC size
sudo fdisk -l /dev/sda

# If image is 32GB but eMMC is 16GB:
# Option 1: Shrink image first (use pishrink)
# Option 2: Create smaller master image
```

### CM4 boots but no display on panel PC

**Issue:** May need vendor-specific display drivers

**Solution:**
1. Check vendor documentation for "System Image Download"
2. Download and use vendor's base OS image
3. Flash vendor OS first, verify display works
4. Deploy PouCon package on top of vendor OS

### Touch not working after flashing

**Issue:** Missing touchscreen drivers

**Symptoms:**
- Display works but touch doesn't respond
- `evtest` shows no touch devices
- `/dev/input/event*` missing touch device

**Solution:**
```bash
# 1. Verify you used vendor OS (not generic Pi OS)
cat /etc/os-release
# Should show vendor-specific version

# 2. Check if touch driver loaded
dmesg | grep -i touch
dmesg | grep -i goodix  # For Waveshare
dmesg | grep -i ft5406  # For official Pi touch

# 3. Check device tree overlays
ls /boot/overlays/
# Should have vendor-specific .dtbo files

# 4. If missing, reflash vendor OS image
```

### Wrong display resolution or orientation

**Issue:** Display drivers not configured for panel

**Solution:**
```bash
# Check vendor documentation for:
# - Required config.txt settings
# - Display rotation settings
# - Resolution settings

# Example: Waveshare 10.1" panel requires
sudo nano /boot/config.txt
# Add vendor-specific settings:
hdmi_group=2
hdmi_mode=87
hdmi_cvt=1280 800 60 6 0 0 0
```

### RS485/Serial ports not appearing

**Issue:** USB-serial drivers not loaded

**Check:**
```bash
# List USB devices
lsusb

# Check for serial devices
ls -l /dev/ttyUSB*
ls -l /dev/ttyAMA*

# Check kernel modules
lsmod | grep -i serial
lsmod | grep -i ftdi  # For FTDI chips
lsmod | grep -i ch341 # For CH341 chips
```

**Solution:**
- Ensure vendor OS includes required USB-serial drivers
- Some industrial carriers use specific USB-serial chips
- Check vendor documentation for required kernel modules

### eMMC Boot vs USB Boot confusion

**Boot priority (default):**
1. eMMC (if present and boot enabled)
2. SD card (if present)
3. USB boot (if enabled by jumper)

**To flash eMMC:**
- MUST disable eMMC boot (jumper/switch)
- USB boot becomes active
- rpiboot can access eMMC via USB

## Best Practices for CM4 Deployments

### 1. Hardware Selection

**Buy consistent hardware:**
- Order all CM4s with same eMMC size (16GB or 32GB)
- Same carrier board model for all sites
- Same vendor, same product SKU
- Easier to maintain single master image

**Verify vendor support:**
- Check vendor provides OS image downloads
- Verify vendor maintains updates
- Check forum/wiki for community support
- Avoid obscure brands with poor documentation

### 2. Documentation and Testing

**Before bulk purchase:**
- Buy 1-2 units first for testing
- Verify ALL hardware works (touch, display, I/O, serial)
- Test with vendor OS + PouCon deployment
- Document any quirks or special procedures

**Document your carrier board:**
- Take photos of jumper locations
- Note USB boot procedure
- Screenshot vendor wiki pages
- Keep PDF manuals in deployment kit
- Record required config.txt settings

### 3. Master Image Strategy

**Create vendor-specific master images:**
```
poucon_waveshare_cm4_panel_v1.0.img.gz    # For Waveshare panels
poucon_seeed_reterminal_v1.0.img.gz       # For Seeed reTerminal
poucon_generic_cm4_v1.0.img.gz            # For generic carriers
```

**Version and label:**
- Include vendor name in filename
- Include PouCon version in filename
- Include date in filename
- Store separate master per hardware type
- Keep changelog of what's included

**Test thoroughly:**
- Flash test image to 2-3 units
- Verify all hardware functions
- Run for 24 hours minimum
- Test power cycling
- Test all PouCon features

### 4. Vendor OS Maintenance

**Stay up to date:**
```bash
# Check vendor website monthly for OS updates
# Subscribe to vendor newsletter/RSS feed

# When new vendor OS released:
# 1. Download new image
# 2. Flash to test unit
# 3. Deploy PouCon on top
# 4. Test thoroughly
# 5. Create new master image
# 6. Update all units (during maintenance window)
```

**Keep old versions:**
- Don't delete previous master images
- You may need to roll back
- Label with dates clearly

### 5. Deployment Toolkit

**Physical tools:**
- Laptop with rpiboot installed
- Multiple USB cables (USB-A to micro-USB, USB-C)
- Jumper wires (for boot jumpers)
- Small screwdrivers (for opening panels)
- SD card reader (for CM4 Lite units)
- Label maker (for marking units)

**Software tools:**
```
deployment_laptop/
├── rpiboot/                           # USB boot tool
├── master_images/
│   ├── poucon_waveshare_v1.0.img.gz
│   ├── poucon_seeed_v1.0.img.gz
│   └── poucon_generic_v1.0.img.gz
├── vendor_os/
│   ├── waveshare_original.img.xz
│   └── seeed_original.img.xz
├── deployment_packages/
│   └── pou_con_deployment_latest.tar.gz
└── documentation/
    ├── waveshare_manual.pdf
    ├── seeed_manual.pdf
    └── deployment_checklist.txt
```

### 6. Pre-Deployment Process

**At office before field deployment:**

1. **Flash all units:**
   ```bash
   # Flash correct master image for hardware type
   for i in {1..10}; do
     echo "Flash unit $i"
     gunzip -c poucon_waveshare_v1.0.img.gz | sudo dd of=/dev/sda bs=4M
     # Wait for completion, swap to next unit
   done
   ```

2. **Boot test each unit:**
   - Power on
   - Verify display
   - Test touch
   - Check PouCon loads
   - Label unit with site name

3. **Reduce on-site work:**
   - Units arrive ready to boot
   - Only need to run `poucon-setup` script
   - 5 minutes per site

### 7. Troubleshooting Preparation

**Common issues to prepare for:**

1. **Keep vendor OS image on USB stick**
   - If unit has driver issues
   - Quick reflash at site

2. **Document driver verification commands:**
   ```bash
   # Create site_check.sh script
   #!/bin/bash
   echo "=== Hardware Check ==="

   # Check touch
   ls /dev/input/event* | grep event

   # Check display
   fbset

   # Check serial ports
   ls -l /dev/ttyUSB* /dev/ttyAMA*

   # Check vendor OS version
   cat /etc/os-release

   # Check PouCon service
   systemctl status pou_con
   ```

3. **Emergency recovery procedure:**
   - Keep one pre-configured spare unit
   - Backup of critical site configs
   - Quick swap procedure documented

### 8. Label Everything

**Label each unit with:**
- Site name
- Unit serial number
- CM4 type (Lite vs eMMC, RAM size)
- Carrier board model
- Deployment date
- Master image version used

**Label locations:**
- Physical label on enclosure
- Digital inventory spreadsheet
- Site deployment log

## Summary

### CM4 Lite (SD Card)
- ✅ Deploy exactly like standard Pi
- ✅ Use master image deployment guide as-is
- ✅ Easy field swaps
- ❌ Less reliable long-term

### CM4 with eMMC
- ✅ More reliable for production
- ✅ Better performance
- ❌ Requires rpiboot + USB connection
- ❌ Slightly more complex deployment

**Recommendation:** For production poultry house controllers, use **CM4 with eMMC** on industrial carrier board or panel PC. The reliability benefits outweigh the minor deployment complexity.

---

**See also:**
- [MASTER_IMAGE_DEPLOYMENT.md](MASTER_IMAGE_DEPLOYMENT.md) - Master image creation
- [TOUCHSCREEN_KIOSK_SETUP.md](TOUCHSCREEN_KIOSK_SETUP.md) - Panel PC setup
- Official Raspberry Pi CM4 documentation: https://www.raspberrypi.com/products/compute-module-4/

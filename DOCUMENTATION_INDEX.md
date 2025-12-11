# PouCon Documentation Index

Quick reference to all deployment and setup documentation.

## Core Documentation

### 1. **CLAUDE.md** - Project Guide
- **Purpose:** Main project documentation for development
- **For:** Developers working on the codebase
- **Contains:**
  - Project architecture
  - Development commands
  - Code organization
  - Testing approach
  - Domain structure

### 2. ⭐ **MASTER_IMAGE_DEPLOYMENT.md** - Burn and Boot (RECOMMENDED)
- **Purpose:** Fastest deployment method for production
- **For:** Production deployments, multiple sites
- **Contains:**
  - Creating master SD card image (one-time)
  - Flashing images to SD cards (10 min each)
  - Simple on-site setup script (5 min)
  - Updating master images
  - Multi-site deployment strategy

**Use this for:** Deploying to 2+ poultry houses. **This is the easiest way!**

### 2.5 ⭐ **CM4_BOOKWORM_DEPLOYMENT_SUMMARY.md** - Deploy to Existing CM4 (NEW)
- **Purpose:** Deploy to vendor-provided CM4 with pre-installed OS
- **For:** CM4 modules with vendor OS (Raspberry Pi OS Bookworm Desktop 64-bit)
- **Contains:**
  - Automated deployment scripts
  - Bookworm-specific build process
  - Desktop OS optimizations (headless/kiosk/desktop modes)
  - First-time setup workflow
  - Quick reference for daily operations

**Use this for:** CM4 boards that came with vendor hardware and pre-installed OS.

### 2.6 **EXISTING_SYSTEM_DEPLOYMENT.md** - Comprehensive CM4 Guide
- **Purpose:** Detailed deployment guide for existing CM4 systems
- **For:** Advanced users, custom deployments
- **Contains:**
  - Build compatibility (Debian Bookworm)
  - Manual step-by-step deployment
  - Environment configuration
  - Systemd service setup
  - Desktop optimization strategies
  - Hardware integration (Waveshare, Cytron)
  - Security hardening
  - Troubleshooting guide

**Use this for:** Reference when customizing deployment or troubleshooting issues.

### 3. **DEPLOYMENT_GUIDE.md** - Complete Deployment Manual
- **Purpose:** Full deployment procedures for field installation
- **For:** System administrators, field technicians
- **Contains:**
  - Offline deployment workflow
  - Initial build preparation
  - Creating deployment packages
  - Field deployment (no internet)
  - Replacing failed controllers
  - Post-deployment configuration
  - Touchscreen kiosk overview
  - Backup and recovery
  - Troubleshooting

**Use this for:** Reference guide for all deployment scenarios

### 4. **CROSS_PLATFORM_BUILD.md** - Building for Raspberry Pi
- **Purpose:** How to build ARM releases on x86_64 development machines
- **For:** Developers, build engineers
- **Contains:**
  - Why cross-platform build is needed
  - 4 solutions comparison
  - Docker ARM emulation setup (recommended)
  - Pi build server setup
  - Build verification
  - Troubleshooting builds

**Use this for:** Understanding the build process and setting up Docker

### 4. **QUICKSTART_OFFLINE_DEPLOY.md** - TL;DR Deployment
- **Purpose:** Quick reference for experienced users
- **For:** Technicians who've already done deployments
- **Contains:**
  - One-command setup
  - Quick workflow overview
  - Common commands
  - Fast troubleshooting

**Use this for:** Daily deployment operations after initial learning

### 5. **TOUCHSCREEN_KIOSK_SETUP.md** - Touchscreen Configuration
- **Purpose:** Complete guide for touchscreen kiosk installations
- **For:** Field technicians installing on-site displays
- **Contains:**
  - Hardware options comparison
  - Standard Pi + touchscreen setup
  - **Industrial Touch Panel PC setup** (vendor drivers)
  - Kiosk mode configuration
  - Display orientation and calibration
  - Troubleshooting touchscreen issues
  - Hardware recommendations

**Use this for:** Any deployment with touchscreen display

## Hardware Documentation

### 6. **HARDWARE_REQUIREMENTS.md** - Hardware Specifications
- **Purpose:** Required and recommended hardware
- **For:** Procurement, system design
- **Contains:**
  - Raspberry Pi requirements
  - Modbus hardware (RS485 adapters)
  - Sensors and I/O modules
  - Power supply requirements
  - Networking equipment

### 7. **brain_recommendation.md** - Industrial Hardware Guide
- **Purpose:** Recommendations for production deployments
- **For:** Project managers, engineers
- **Contains:**
  - Industrial-grade hardware options
  - HMI recommendations
  - Rugged panel PCs
  - Production deployment strategies

## Quick Decision Tree

### "I have a CM4 with vendor OS already installed"

**Your board came with Raspberry Pi OS pre-installed? (Bookworm Desktop 64-bit)**

**YES → Use:**
1. ⭐ **CM4_BOOKWORM_DEPLOYMENT_SUMMARY.md** (start here!)
2. Run: `./scripts/deploy_to_cm4.sh <CM4-IP>`
3. **EXISTING_SYSTEM_DEPLOYMENT.md** (reference when needed)

This is the easiest path for vendor-provided CM4 boards!

### "I want to deploy PouCon to a poultry house (fresh install)"

**Do you have a touchscreen?**

**NO → Use:**
1. **CROSS_PLATFORM_BUILD.md** (one-time setup)
2. **QUICKSTART_OFFLINE_DEPLOY.md** (daily workflow)
3. **DEPLOYMENT_GUIDE.md** (reference when stuck)

**YES → Use:**
1. **CROSS_PLATFORM_BUILD.md** (one-time setup)
2. **QUICKSTART_OFFLINE_DEPLOY.md** (build and deploy)
3. **TOUCHSCREEN_KIOSK_SETUP.md** (after deployment)

### "I need to deploy to multiple sites"

**Use:** ⭐ **MASTER_IMAGE_DEPLOYMENT.md**
- Create one master image
- Flash to multiple SD cards
- Fastest deployment method

### "I need to understand the build process"

**Start here:**
1. **CROSS_PLATFORM_BUILD.md** - Understand why and how

### "I have an Industrial Touch Panel PC"

**Start here:**
1. **TOUCHSCREEN_KIOSK_SETUP.md** → Section: "Industrial Touch Panel PC Setup"
2. Get vendor OS image
3. Follow standard deployment
4. Run kiosk setup script

### "Something isn't working"

**Check in order:**
1. **QUICKSTART_OFFLINE_DEPLOY.md** → Troubleshooting section
2. **DEPLOYMENT_GUIDE.md** → Troubleshooting section
3. **TOUCHSCREEN_KIOSK_SETUP.md** → Troubleshooting (if touchscreen)
4. **CLAUDE.md** → Architecture details (if system behavior)

## Workflow Cheat Sheet

### First-Time Setup (Development Machine)

```bash
# 1. Setup Docker for ARM builds
./scripts/setup_docker_arm.sh

# Done! This is one-time only
```

### Every Deployment

```bash
# 1. Build and package (at office, 20 min)
./scripts/build_and_package.sh
cp pou_con_deployment_*.tar.gz /media/usb_drive/

# 2. Deploy (at site, 10 min, no internet)
tar -xzf pou_con_deployment_*.tar.gz
cd deployment_package_*/
sudo ./deploy.sh
sudo systemctl enable pou_con
sudo systemctl start pou_con

# 3. Optional: Setup touchscreen kiosk
./setup_kiosk.sh
sudo reboot
```

### Backup and Replace

```bash
# Backup old Pi
sudo ./backup.sh
cp /var/backups/pou_con/pou_con_backup_*.tar.gz /media/usb/

# Deploy to new Pi (same as above)
# Then restore:
sudo systemctl stop pou_con
tar -xzf pou_con_backup_*.tar.gz
sudo cp pou_con_prod.db /var/lib/pou_con/
sudo chown pou_con:pou_con /var/lib/pou_con/pou_con_prod.db
sudo systemctl start pou_con
```

## File Locations Reference

### Documentation Files
```
CLAUDE.md                           # Project guide
DEPLOYMENT_GUIDE.md                 # Main deployment manual
CROSS_PLATFORM_BUILD.md             # ARM build guide
QUICKSTART_OFFLINE_DEPLOY.md        # Quick reference
TOUCHSCREEN_KIOSK_SETUP.md          # Touchscreen setup
MASTER_IMAGE_DEPLOYMENT.md          # Burn and boot method
CM4_BOOKWORM_DEPLOYMENT_SUMMARY.md  # CM4 with vendor OS (quick start)
EXISTING_SYSTEM_DEPLOYMENT.md       # CM4 with vendor OS (detailed)
HARDWARE_REQUIREMENTS.md            # Hardware specs
brain_recommendation.md             # Industrial hardware
DOCUMENTATION_INDEX.md              # This file
```

### Build Scripts
```
scripts/
├── setup_docker_arm.sh           # One-time Docker setup
├── build_arm.sh                  # Build ARM release
├── create_deployment_package.sh  # Package for deployment
├── build_and_package.sh          # All-in-one build
├── setup_kiosk.sh                # Touchscreen kiosk setup
├── deploy_to_cm4.sh              # Automated CM4 deployment
└── cm4_first_setup.sh            # First-time CM4 setup
```

### Build Artifacts
```
Dockerfile.arm                    # ARM build definition
output/
└── pou_con_release_arm.tar.gz   # ARM release
pou_con_deployment_*.tar.gz       # Deployment package
```

### Deployment Package Contents
```
deployment_package_*/
├── pou_con/                      # Application
├── deploy.sh                     # Deployment script
├── backup.sh                     # Backup script
├── uninstall.sh                  # Uninstall script
├── setup_kiosk.sh                # Kiosk setup (optional)
└── README.txt                    # Quick guide
```

### On Raspberry Pi (After Deployment)
```
/opt/pou_con/                     # Application
/var/lib/pou_con/                 # Database
/var/log/pou_con/                 # Logs
/var/backups/pou_con/             # Backups
/etc/systemd/system/pou_con.service  # Service
```

## Getting Help

### Common Questions

**Q: How do I build for Raspberry Pi on my x86_64 machine?**
A: See **CROSS_PLATFORM_BUILD.md** → Solution 2 (Docker ARM Emulation)

**Q: How do I deploy without internet at the site?**
A: See **QUICKSTART_OFFLINE_DEPLOY.md** → Phase 2 and 3

**Q: My Industrial Touch Panel PC touch isn't working**
A: See **TOUCHSCREEN_KIOSK_SETUP.md** → Industrial Touch Panel PC Setup → Use vendor OS image

**Q: How do I backup and restore configuration?**
A: See **DEPLOYMENT_GUIDE.md** → Backup and Recovery

**Q: What hardware do I need?**
A: See **HARDWARE_REQUIREMENTS.md** and **brain_recommendation.md**

**Q: The browser isn't starting in kiosk mode**
A: See **TOUCHSCREEN_KIOSK_SETUP.md** → Troubleshooting → Browser Doesn't Start

**Q: How do I update PouCon at deployed sites?**
A: Build new deployment package, deploy over existing (keeps database)

## Support and Contributing

For issues, bugs, or feature requests, refer to the project repository documentation.

For architecture and development questions, see **CLAUDE.md**.

## Version History

- **2025-12-10:** Initial comprehensive documentation set
  - Added cross-platform build guide
  - Added touchscreen kiosk guide
  - Added industrial panel PC section
  - Added quick start guide
  - Updated deployment guide

---

**Start Here:** If this is your first time, read **CROSS_PLATFORM_BUILD.md** and **QUICKSTART_OFFLINE_DEPLOY.md** in that order. Everything else is reference material.

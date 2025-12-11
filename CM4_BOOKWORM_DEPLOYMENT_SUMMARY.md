# CM4 Bookworm Deployment - Quick Reference

## Your Setup
- **Hardware**: Raspberry Pi Compute Module 4
- **OS**: Raspberry Pi OS Desktop 64-bit (Bookworm, Debian 12)
- **Architecture**: aarch64 (ARM 64-bit)
- **Vendor Hardware**: Pre-configured with drivers

## ✅ Compatibility Confirmed

Your CM4 with **Bookworm** will work perfectly. Build the release using **Bookworm Docker container** to match the OS version and avoid GLIBC compatibility issues.

## Deployment Methods

### Method 1: Automated Deployment (Recommended)

Use the provided deployment script for easy updates:

```bash
# On your development machine
cd /home/tankwanghow/Projects/elixir/pou_con

# Deploy to CM4 (builds + deploys)
./scripts/deploy_to_cm4.sh 192.168.1.100

# Or just build the release package
./scripts/deploy_to_cm4.sh - --build-only
```

**First-time setup on CM4:**
```bash
# On the CM4 (after transfer)
bash ~/cm4_first_setup.sh
```

This script:
- ✓ Installs all dependencies
- ✓ Extracts release to /opt/pou_con
- ✓ Creates .env configuration
- ✓ Initializes database
- ✓ Sets up systemd service
- ✓ Configures serial port access
- ✓ Starts the application

### Method 2: Manual Deployment

Follow the comprehensive guide in **EXISTING_SYSTEM_DEPLOYMENT.md**

## Key Commands

### On Development Machine (Build)

```bash
# Build using Bookworm Docker (matches CM4 OS)
docker run -it --rm \
  -v $(pwd):/app \
  -w /app \
  hexpm/elixir:1.15.7-erlang-26.1.2-debian-bookworm-20231009-slim \
  bash -c "mix local.hex --force && mix local.rebar --force && \
           mix deps.get --only prod && MIX_ENV=prod mix assets.deploy && \
           MIX_ENV=prod mix release"

# Package
tar -czf pou_con_release.tar.gz -C _build/prod/rel/pou_con .

# Transfer
scp pou_con_release.tar.gz pi@192.168.1.100:/home/pi/
```

### On CM4 (First Time)

```bash
# Run setup script
bash ~/cm4_first_setup.sh

# Or manually:
sudo apt update && sudo apt install -y erlang-base sqlite3 libsqlite3-dev
sudo mkdir -p /opt/pou_con
sudo tar -xzf ~/pou_con_release.tar.gz -C /opt/pou_con
sudo chown -R pi:pi /opt/pou_con

# Create .env, initialize database, setup systemd
# (See EXISTING_SYSTEM_DEPLOYMENT.md for details)
```

### On CM4 (Daily Operations)

```bash
# Check status
sudo systemctl status pou_con

# View logs
sudo journalctl -u pou_con -f

# Restart service
sudo systemctl restart pou_con

# Stop service
sudo systemctl stop pou_con

# Start service
sudo systemctl start pou_con
```

## Desktop OS Optimizations

Your CM4 has desktop GUI running. Choose one:

### Option A: Headless Mode (Best Performance)
Saves ~400MB RAM by disabling GUI:
```bash
sudo systemctl set-default multi-user.target
sudo reboot
```

### Option B: Kiosk Mode (Best for On-Site Display)
Full-screen browser showing PouCon dashboard:
```bash
# See EXISTING_SYSTEM_DEPLOYMENT.md for kiosk setup
```

### Option C: Keep Desktop (Most Flexible)
Access via VNC, use GUI for configuration when needed.

## Web Interface Access

After deployment:
```
http://<CM4-IP>:4000
```

Default login (if created admin):
- Username: `admin`
- Password: `admin123` ⚠️ **Change immediately!**

## Configuration Workflow

1. **Admin → Ports**: Add RS485 serial ports (e.g., `/dev/ttyUSB0`)
2. **Admin → Devices**: Add Modbus devices (Waveshare IO, Cytron sensors)
3. **Admin → Equipment**: Create equipment (fans, pumps) and link to devices
4. **Admin → Interlocks**: Define safety rules
5. **Automation Pages**: Configure schedules and auto-control

## Hardware Integration

### Waveshare Modbus RTU IO 8CH
- Protocol: Modbus RTU
- Connection: RS485 (A/B terminals)
- Baud rate: 9600, 8N1
- Default address: 1 (check DIP switches)

### Cytron RS485 Temperature/Humidity Sensor
- Protocol: Modbus RTU
- Connection: RS485
- Read registers for temp/humidity

### Serial Port Permissions
```bash
# Already configured by setup script
sudo usermod -a -G dialout pi
# Log out and back in for changes to take effect
```

## Troubleshooting

### Application won't start
```bash
sudo journalctl -u pou_con -n 100
cat /opt/pou_con/.env
ls -la /opt/pou_con/bin/pou_con
```

### Serial port access denied
```bash
groups pi  # Should include 'dialout'
ls -la /dev/ttyUSB*  # Should show crw-rw---- root dialout
# If not in dialout: sudo usermod -a -G dialout pi && reboot
```

### Database issues
```bash
ls -la /opt/pou_con/data/
# Reset database (deletes all data!):
rm /opt/pou_con/data/pou_con_prod.db*
cd /opt/pou_con && export $(cat .env | xargs)
./bin/pou_con eval "PouCon.Release.migrate()"
```

### View device states
```bash
cd /opt/pou_con
./bin/pou_con remote
# In console:
PouCon.Hardware.DeviceManager.get_all_device_data()
# Press Ctrl+D to exit
```

## Updating PouCon

```bash
# On dev machine: Build and transfer new release
./scripts/deploy_to_cm4.sh 192.168.1.100

# Or manually:
scp pou_con_release.tar.gz pi@192.168.1.100:/home/pi/
ssh pi@192.168.1.100
sudo systemctl stop pou_con
sudo tar -xzf ~/pou_con_release.tar.gz -C /opt/pou_con
cd /opt/pou_con && export $(cat .env | xargs)
./bin/pou_con eval "PouCon.Release.migrate()"
sudo systemctl start pou_con
```

## Backup

```bash
# On CM4
sudo tar -czf ~/pou_con_backup_$(date +%Y%m%d).tar.gz \
  /opt/pou_con/data/ \
  /opt/pou_con/.env

# Transfer off CM4
scp pou_con_backup_*.tar.gz user@backup-server:/backups/
```

## Security Checklist

- [ ] Change default admin password
- [ ] Set static IP address (recommended for production)
- [ ] Enable firewall: `sudo ufw allow 22,4000/tcp && sudo ufw enable`
- [ ] Disable SSH password auth (use keys only)
- [ ] Set up automatic security updates

See **EXISTING_SYSTEM_DEPLOYMENT.md** for detailed security hardening.

## Important Notes

1. **Always build on Bookworm**: Use the Docker command above to ensure binary compatibility
2. **Serial port permissions**: Log out/in after first setup for dialout group membership
3. **Database migrations**: Run automatically during updates via deployment script
4. **RTC battery**: If time resets on boot, use Admin → System Settings → Set System Time
5. **Log rotation**: Configured automatically to prevent SD card filling up
6. **Desktop RAM usage**: Consider headless mode if you don't need GUI

## Documentation

- **EXISTING_SYSTEM_DEPLOYMENT.md**: Comprehensive deployment guide
- **CLAUDE.md**: Project architecture and development guide
- **LOGGING_INTEGRATION_GUIDE.md**: Logging system details
- **TOUCHSCREEN_KIOSK_SETUP.md**: Kiosk mode configuration

## Quick Health Check

```bash
# On CM4
sudo systemctl status pou_con          # Should be 'active (running)'
curl http://localhost:4000              # Should return HTML
ls -la /dev/ttyUSB*                     # Serial devices detected
free -h                                 # Check available memory
df -h /opt/pou_con                      # Check disk space
sudo journalctl -u pou_con -n 20        # Recent logs
```

## Support

If you encounter issues:
1. Check systemd logs: `sudo journalctl -u pou_con -n 100`
2. Verify .env file: `cat /opt/pou_con/.env`
3. Test hardware: Check serial devices exist
4. Review architecture: See CLAUDE.md
5. Report issues: https://github.com/anthropics/claude-code/issues

---

**Ready to deploy?** Run `./scripts/deploy_to_cm4.sh <CM4-IP>` and follow the prompts!

# Hardware Requirements for PouCon Deployment

This document provides detailed storage and memory requirements for deploying PouCon on embedded hardware.

## Storage (eMMC/SD Card) Requirements

### Component Breakdown

| Component | Size | Notes |
|-----------|------|-------|
| **Operating System** | | |
| Raspberry Pi OS Lite | 500 MB - 1 GB | Headless (no GUI) |
| Raspberry Pi OS Desktop | 2 - 3 GB | With minimal GUI for local browser |
| **Runtime Environment** | | |
| Erlang VM + Elixir | 150 - 250 MB | BEAM runtime and stdlib |
| System dependencies | 100 - 200 MB | LibSSL, build tools if needed |
| **PouCon Application** | | |
| Compiled release | 50 - 100 MB | Phoenix + dependencies |
| SQLite database | 10 - 50 MB | With 30-day retention (105 KB/day × 43 items) |
| Logs and temporary files | 100 - 200 MB | System logs, crash dumps |
| **Web Browser (Optional)** | | |
| Chromium browser | 150 - 250 MB | For kiosk mode |
| **Safety Buffer** | 2 - 4 GB | OS updates, temporary files, swap |

### Recommended Storage

- **Minimum (Headless)**: 4 GB eMMC/SD Card
- **Recommended (Headless)**: 8 GB
- **With Local Browser**: 16 GB
- **Production Safe**: 32 GB (allows for growth, backups, updates)

## RAM Requirements

### Runtime Memory Usage

| Process | RAM Usage | Notes |
|---------|-----------|-------|
| **Operating System** | | |
| Linux kernel + services | 100 - 200 MB | Idle state |
| GUI (if used) | 150 - 300 MB | Minimal window manager |
| **PouCon Application** | | |
| BEAM VM base | 50 - 100 MB | Erlang runtime |
| Phoenix server | 100 - 200 MB | LiveView processes |
| Equipment controllers | 50 - 100 MB | 43 GenServers (~2 MB each) |
| DeviceManager + ETS | 20 - 50 MB | Device cache and polling |
| Automation services | 30 - 50 MB | Schedulers, environment control |
| **Peak Application Total** | 250 - 500 MB | Under normal load |
| **Web Browser (Optional)** | | |
| Chromium | 200 - 500 MB | Single tab, depends on page complexity |
| **Safety Buffer** | 200 - 500 MB | For spikes, temporary data |

### Recommended RAM

- **Minimum (Headless)**: 512 MB (tight, may swap)
- **Recommended (Headless)**: 1 GB
- **With Local Browser**: 2 GB minimum, 4 GB recommended
- **Heavy Load/Debugging**: 4 GB

## Hardware Recommendations by Deployment Type

### 1. Headless Production (Recommended)
Access UI from tablets/phones on local network

```
Storage: 8-16 GB eMMC/SD Card
RAM: 1-2 GB
Example: Raspberry Pi 3B+, Pi 4 (2GB model)
```

**Pros**: Lower power, reliable, no screen needed
**Cons**: Requires network access to UI

### 2. Kiosk Mode with Local Display
Dedicated touchscreen showing dashboard

```
Storage: 16-32 GB eMMC/SD Card
RAM: 2-4 GB
Example: Raspberry Pi 4 (4GB model) + touchscreen
```

**Pros**: Standalone operation, touch control
**Cons**: Higher power, more expensive

### 3. Development/Testing
For testing with simulated devices

```
Storage: 16-32 GB
RAM: 2-4 GB
Example: Any modern PC/laptop, Raspberry Pi 4
```

## Write Cycle Considerations (SD Card vs eMMC)

Your logging system writes:
- **Equipment events**: ~105 KB/day with async writes
- **Sensor snapshots**: Every 30 minutes (1440 writes/month)
- **Daily summaries**: Once per day
- **Vacuum**: Once per week

**Recommendation**:
- Use **industrial-grade eMMC** or **SLC SD cards** for production (designed for 100K+ write cycles)
- Avoid consumer SD cards (may wear out in 1-2 years with continuous writes)
- Your cleanup tasks and 30-day retention help minimize writes significantly

## Tested Configuration

Based on your hardware setup (Waveshare Modbus RTU IO 8CH + RS485 sensors):

```
Recommended Hardware:
- Raspberry Pi 4B (2GB RAM model) - $45
- 16 GB industrial eMMC or SLC SD card - $15-30
- Headless deployment (no local browser)
- Access via tablets/phones on farm WiFi

Storage Usage:
- OS: 1 GB
- App: 500 MB
- Database: 50 MB (with 365-day summaries)
- Free space: 14.5 GB (for growth, backups)

RAM Usage:
- OS: 150 MB
- PouCon: 400 MB peak
- Free: 1.5 GB (comfortable buffer)
```

## Cost-Effective Option

```
Raspberry Pi 3B+ (1GB RAM) + 8GB SLC SD Card
- Storage: Sufficient for headless
- RAM: Tight but functional if headless only
- Cost: ~$35 + $10 = $45 total
- Limitation: Cannot run local browser reliably
```

## Summary

**For your poultry farm deployment (headless recommended):**
- **eMMC/Storage**: 8-16 GB (16 GB for safety)
- **RAM**: 1-2 GB (2 GB for comfort)
- **Hardware**: Raspberry Pi 4B (2GB model) is the sweet spot
- **Storage Type**: Industrial eMMC or SLC SD card for reliability

The application itself is quite lightweight (~500 MB total with database), but you need headroom for the OS, runtime, and future growth. The 2GB RAM model gives you enough buffer to handle peak loads during simultaneous operations (multiple equipment starting, browser connections, logging bursts).

## Monitoring Recommendations

### Storage Monitoring
```bash
# Check available space
df -h

# Check SD card health (if supported)
sudo smartctl -a /dev/mmcblk0
```

### RAM Monitoring
```bash
# Check memory usage
free -h

# Check BEAM VM memory
# In IEx console:
:erlang.memory()
```

### Production Alerts
Consider setting up alerts when:
- Free storage drops below 1 GB
- RAM usage exceeds 80%
- Database size exceeds expected growth rate
- Write errors occur on storage device

## Future Scaling Considerations

If you need to scale beyond current capacity:
- **More equipment items**: Add +50 MB RAM per 20 items
- **Longer retention**: Add +2 MB storage per day of retention
- **More frequent snapshots**: Add +20 MB RAM for logging buffer
- **Historical analytics**: Consider external storage or database offloading

# System Time Recovery Guide

## Problem: RTC Battery Failure After Power Loss

When the Raspberry Pi's RTC (Real-Time Clock) battery dies, the system clock resets to an incorrect time after power failure. This causes:
- Log entries with wrong timestamps
- Scheduler confusion (lighting, feeding, egg collection)
- Report generation issues

## Solution: Automatic Detection and Manual Recovery

PouCon now automatically detects this problem on startup by comparing the current system time with the last logged event timestamp. If the last event is in the future, logging is paused until you fix the time.

## One-Time Setup (Required for Web Form)

To enable the web-based time setting form, you must configure passwordless sudo once:

```bash
# SSH into the device
ssh pi@192.168.x.x

# Navigate to PouCon directory
cd /path/to/pou_con

# Run the setup script (only needed once)
sudo bash setup_sudo.sh
```

This allows the web application to run `date` and `hwclock` commands without entering a password.

**If you skip this setup**, the web form won't work, and you'll need to use the SSH method (see below).

## Recovery Steps (Offline Deployments)

### Step 1: Notice the Problem

After system boot, you'll see:
- Error message in console logs: `⚠️ SYSTEM TIME VALIDATION FAILED ⚠️`
- No new events being logged (logging is paused)

### Step 2: Navigate to System Time Page

1. Open the PouCon web interface
2. Log in as admin
3. Navigate to **Admin > System Time** (`/admin/system_time`)

You'll see:
- **Red warning banner** showing the time validation failed
- Current incorrect device time
- Last event timestamp (which is in the "future")

### Step 3: Set the Correct Time

**Option A: Use Web Form (Recommended)**

1. Check the current time on your phone, watch, or other reliable source
2. Click **"↻ Use My Device's Current Time"** button
   - This auto-fills the form with your browser's time (from your phone/laptop)
3. Review the date and time fields
4. Click **"Set System Time & Sync Hardware Clock"**
5. Click **"✓ Time is Correct - Resume Logging"**

**Option B: Manual SSH Method**

If the web form doesn't work:
```bash
# SSH into the Raspberry Pi
ssh pi@192.168.x.x

# Set the system time (adjust to current time)
sudo date -s "2025-12-09 14:30:00"

# Sync the hardware clock
sudo hwclock --systohc

# Verify
date
```

Then return to the web interface and click **"✓ Time is Correct - Resume Logging"**

### Step 4: Verify

Once you click the resume button:
- If successful: Green message "System time validated successfully. Logging resumed."
- If still invalid: Error message with details

## Prevention

**Replace the RTC Battery**

The proper long-term fix is to replace the dead CR2032 battery on your Raspberry Pi:
1. Power down the Pi completely
2. Locate the CR2032 battery holder on the board
3. Replace with a new CR2032 battery
4. Power on - the Pi will now maintain time during power failures

**For Locations With Internet (Optional)**

If your deployment site has internet access, you can enable NTP auto-sync:

```bash
sudo systemctl enable systemd-timesyncd
sudo systemctl start systemd-timesyncd
sudo timedatectl set-ntp true
```

This will automatically sync time from internet time servers on boot.

## Technical Details

### How Detection Works

1. On startup, `SystemTimeValidator` queries the last `equipment_events` record
2. Compares `last_event.inserted_at` with current `DateTime.utc_now()`
3. If last event is >10 seconds in the future → time is invalid
4. Sets `time_valid?` flag to `false`
5. All logging modules check this flag and skip writes

### What Gets Paused

When time is invalid, these operations are skipped:
- Equipment event logging (start, stop, error events)
- Sensor snapshots (every 30 minutes)
- Daily summaries (midnight generation)

Equipment controllers continue to operate normally - only the logging is paused.

### Files Involved

- `lib/pou_con/system_time_validator.ex` - Detection and validation logic
- `lib/pou_con/logging/equipment_logger.ex` - Checks before logging events
- `lib/pou_con/logging/periodic_logger.ex` - Checks before sensor snapshots
- `lib/pou_con/logging/daily_summary_task.ex` - Checks before summaries
- `lib/pou_con_web/live/admin/system_time/index.ex` - Admin UI for recovery
- `assets/js/app.js` - JavaScript hook for "Use My Device's Time" button

## Troubleshooting

**Problem: "Set System Time" button doesn't work**

Cause: Sudo permissions not configured for www-data user

Solution: Add sudoers entry:
```bash
sudo visudo
# Add this line:
www-data ALL=(ALL) NOPASSWD: /bin/date, /sbin/hwclock, /bin/timedatectl
```

**Problem: Time keeps resetting after power loss**

Cause: RTC battery is dead

Solution: Replace the CR2032 battery on the Raspberry Pi board

**Problem: Can't access admin page**

Cause: Not logged in as admin user

Solution: Log out and log in with admin credentials

## Quick Reference Commands

```bash
# Check current system time
date

# Check hardware clock time
sudo hwclock --show

# Set system time manually
sudo date -s "YYYY-MM-DD HH:MM:SS"

# Sync hardware clock from system time
sudo hwclock --systohc

# Sync system time from hardware clock
sudo hwclock --hctosys

# Check NTP status (if internet available)
timedatectl status

# Enable NTP (if internet available)
sudo timedatectl set-ntp true
```

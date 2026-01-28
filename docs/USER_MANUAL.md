# PouCon User Manual

**Version 1.3**

A comprehensive guide to operating the PouCon Poultry Farm Automation System.

---

## Table of Contents

1. [Introduction](#introduction)
2. [Getting Started](#getting-started)
3. [Critical Alert Banners](#critical-alert-banners)
4. [Navigation](#navigation)
5. [Dashboard](#dashboard)
6. [Equipment Monitoring](#equipment-monitoring)
7. [Operations & Tasks](#operations--tasks)
8. [Flock Management](#flock-management)
9. [Scheduling (Admin)](#scheduling-admin)
10. [Environment Control (Admin)](#environment-control-admin)
11. [Alarm System (Admin)](#alarm-system-admin)
12. [Interlock System (Admin)](#interlock-system-admin)
13. [Reports & Logs](#reports--logs)
14. [System Administration](#system-administration)
15. [Troubleshooting](#troubleshooting)
16. [On-Screen Keyboard](#on-screen-keyboard)

---

## Introduction

PouCon is an industrial automation and control system designed specifically for poultry farms. It provides real-time monitoring and control of farm equipment including:

- **Climate Control**: Fans, pumps, temperature, humidity, CO2, and NH3 sensors
- **Poultry Operations**: Feeding systems, egg collection, lighting
- **Waste Management**: Dung/manure removal systems
- **Safety Systems**: Alarms, sirens, interlocks, power monitoring

The system communicates with industrial hardware via Modbus RTU/TCP protocol and provides a web-based interface accessible from any device with a web browser.

### User Roles

PouCon has two user roles:

| Role | Access Level |
|------|--------------|
| **Admin** | Full access to all features including configuration, schedules, and settings |
| **User** | View-only access to monitoring pages; can complete operations tasks |

### Key Concepts

- **Equipment**: A controllable device (fan, pump, light, etc.)
- **Auto Mode**: Equipment is controlled automatically by schedules or environment control
- **Manual Mode**: Equipment is controlled manually by the physical panel switch
- **Interlock**: A safety rule that prevents equipment from starting unless conditions are met
- **Alarm Rule**: A condition that triggers a siren when thresholds are exceeded

---

## Getting Started

### First-Time Setup

When you access PouCon for the first time, you'll be prompted to create an admin password:

1. Navigate to the system URL (e.g., `http://poucon.local:4000`)
2. The **Initial Admin Setup** page appears
3. Enter a password (minimum 6 characters)
4. Confirm the password
5. Click **Create Admin Account**

After setup, you'll be redirected to the login page.

### Logging In

1. Click the **Menu** button (hamburger icon) in the top-left corner
2. Click **Login** at the bottom of the sidebar
3. Enter your password:
   - **Admin password**: Full access to all features
   - **User password**: Limited access (if configured)
4. Click **Sign In**

### Logging Out

1. Open the sidebar menu
2. Click **Logout** at the bottom (only visible when logged in as admin)

### System Permissions (Raspberry Pi Only)

For full functionality on deployed Raspberry Pi devices, run this command once via SSH:
```bash
sudo bash /opt/pou_con/setup_sudo.sh
```

This enables:
- **System Time**: Set date/time from the web interface (for RTC battery failure recovery)
- **System Management**: Reboot/shutdown from the web interface
- **Screen Saver**: Control screen blank timeout on Wayland (Bookworm) systems

Without this setup, these features will show permission errors or "Setup Required" messages.

---

## Critical Alert Banners

When critical system issues occur, PouCon displays a prominent banner at the top of every page. These banners ensure operators notice and address important problems.

### Banner Types

| Banner | Color | Meaning |
|--------|-------|---------|
| **SYSTEM TIME INVALID** | Orange | System clock has incorrect time (RTC battery may be dead) |
| **FAN CONFIGURATION ERROR** | Red | Failsafe fan requirements not met |

### Banner Behavior

- Banners appear on **all pages** until the issue is resolved
- Banners **pulse/animate** to draw attention
- Click the **Fix Now** link to go directly to the settings page
- The screen will **stay awake** (no blanking) while critical alerts are active

### Resolving Alerts

**System Time Invalid:**
1. Click "Fix Now" or navigate to Admin → System Time
2. Set the correct date and time
3. Click "Set System Time & Sync Hardware Clock"
4. The banner disappears once time is valid

**Fan Configuration Error:**
1. Click "Fix Now" or navigate to Admin → Environment
2. Check that required fans are in AUTO mode and available
3. Ensure the failsafe configuration matches available equipment
4. The banner disappears once requirements are met

---

## Navigation

### Sidebar Menu

Access the sidebar by clicking the **Menu** button (three horizontal lines) in the top-left corner of any page.

The sidebar is organized into sections:

#### Navigation (Public)
- **Dashboard** - Main overview of all equipment

#### Control & Schedules (Admin Only)
- **Environment** - Temperature/humidity automation settings
- **Lighting** - Light on/off schedules
- **Egg Collection** - Egg collection schedules
- **Feeding** - Feeding schedule configuration
- **Flocks** - Flock management
- **Tasks** - Operations task templates

#### Configuration (Admin Only)
- **Settings** - Password and house ID configuration
- **Interlocks** - Safety interlock rules
- **Alarm Rules** - Alarm condition configuration
- **Ports** - Communication port settings
- **Data Points** - Data point configuration for hardware I/O
- **Equipment** - Equipment definitions
- **Simulation** - Device simulation (development only)

#### System (Admin Only)
- **Reports** - Equipment events, sensor data, daily summaries
- **Backup & Restore** - Database backup and restore functions
- **System Management** - System utilities and maintenance
- **Screen Saver** - Configure screen saver settings

### Dashboard Link

Every page includes a **Dashboard** button in the header to quickly return to the main dashboard.

---

## Dashboard

The Dashboard is the main monitoring page, providing an at-a-glance view of all equipment and farm status.

### Summary Cards

The dashboard displays summary cards for each equipment category:

| Card | Information Displayed |
|------|----------------------|
| **Flock Summary** | Current flock name, age, quantity, egg production |
| **Tasks Summary** | Overdue, due today, and upcoming operations tasks |
| **Power Indicators** | Status of power supply indicators (if configured) |
| **Sensors** | Average temperature and humidity readings |
| **CO2/NH3 Sensors** | Gas sensor readings (if configured) |
| **Water Meters** | Current water consumption |
| **Power Meters** | Current power usage |
| **Egg Collection** | Egg collection system status |
| **Pumps** | Number of pumps running vs total |
| **Fans** | Number of fans running vs total |
| **Feeding** | Feeding system status |
| **Lighting** | Light status (on/off) |
| **Sirens** | Siren status and muted alarms |
| **Dung/Manure** | Waste removal system status |

### Color Coding

Equipment cards use color coding to indicate status:

| Color | Meaning |
|-------|---------|
| **Green** | Running/Active |
| **Violet/Gray** | Stopped/Inactive |
| **Red/Rose** | Error condition |
| **Amber/Yellow** | Warning or interlocked |
| **Blue** | Auto mode indicator |

### Clicking Summary Cards

Click on any summary card to navigate to the detailed equipment page for that category.

---

## Equipment Monitoring

Each equipment type has a dedicated monitoring page accessible from the dashboard or sidebar.

### Common Equipment Controls

Most equipment cards display:

- **Title**: Equipment name/label
- **Status**: Running/Stopped/Error
- **Mode Indicator**: AUTO or MANUAL
- **Visual Animation**: Spinning fan, flowing pump, etc.

### Auto vs Manual Mode

| Mode | Description | Control |
|------|-------------|---------|
| **AUTO** | Controlled by automation (schedules, environment control) | Software-controlled |
| **MANUAL** | Controlled by physical panel switch | Panel-controlled |

When equipment is in MANUAL mode, software commands are ignored. The physical switch on the electrical panel has override priority.

### Fans Page (`/fans`)

Displays all ventilation fans with:
- Running status (spinning animation when active)
- Current draw (if sensor configured)
- Mode (Auto/Manual)

**Controls** (when in virtual mode):
- Click the power button to turn on/off
- Toggle mode between Auto and Manual

### Pumps Page (`/pumps`)

Displays cooling/water pumps with similar controls to fans.

### Temperature Sensors (`/temp`)

Displays all temperature sensors with:
- Current temperature reading (°C)
- Sensor status (online/offline)

### Humidity Sensors (`/hum`)

Displays all humidity sensors with:
- Current humidity reading (%)
- Sensor status (online/offline)

### CO2 Sensors (`/co2`)

Displays carbon dioxide sensors with:
- Current CO2 reading (ppm)
- Sensor status (online/offline)

### NH3 Sensors (`/nh3`)

Displays ammonia sensors with:
- Current NH3 reading (ppm)
- Sensor status (online/offline)

### Average Sensors (`/averages`)

Displays calculated average values from multiple sensors:
- Aggregated temperature averages
- Aggregated humidity averages
- Configurable sensor groupings

### Lighting Page (`/lighting`)

Displays all light rows with:
- On/Off status
- Mode (Auto/Manual)

Click a light card to toggle it on/off (if in virtual mode and manual mode).

### Sirens & Alarms Page (`/sirens`)

Displays all sirens and active alarm conditions.

#### Active Alarms Panel

When an alarm is triggered, a panel appears showing:
- **ALARM** (red, pulsing): Active alarm requiring attention
- **MUTED** (amber): Alarm temporarily silenced
- **ACKNOWLEDGED** (blue): Manual alarm waiting for condition to clear

#### Alarm Controls

| Action | Description |
|--------|-------------|
| **Mute** | Temporarily silence the siren (configurable duration) |
| **Unmute** | Re-enable the siren |
| **Acknowledge** | For manual-clear alarms, confirm you're aware |

### Egg Collection Page (`/egg_collection`)

Displays egg collection belt systems with:
- Running status
- Position information
- Mode (Auto/Manual)

### Feeding Page (`/feed`)

Displays feeding systems including:
- **Feeding Carts**: Main feeding distribution systems
- **Feed In Hoppers**: Feed filling systems

### Dung/Manure Page (`/dung`)

Displays waste removal systems:
- **Dung Exit**: Vertical exit systems
- **Dung Horizontal**: Horizontal scraper systems
- **Dung**: Standard scraper systems

### Power Indicators (`/power_indicators`)

Displays power supply status indicators (MCCB, PSU status).

### Water Meters (`/water_meters`)

Displays water consumption data:
- Current flow rate
- Cumulative usage
- Temperature and pressure (if available)

### Power Meters (`/power_meters`)

Displays electrical power data:
- Voltage per phase
- Total power consumption
- Power factor
- Energy usage (kWh)

---

## Operations & Tasks

The Operations Tasks system helps track recurring farm maintenance activities.

### Accessing Tasks

1. Log in with admin or user credentials
2. Access Operations Tasks by:
   - Clicking the **Tasks Summary** card on the dashboard, or
   - Navigating directly to `/operations/tasks`

Note: Operations Tasks is accessible to both admin and user roles, but is not listed in the sidebar menu. Admin users can configure task templates via **Tasks** in the sidebar.

### Task Summary

The top of the page shows:
- **Overdue**: Tasks past their due date
- **Due Today**: Tasks that should be completed today
- **Done Today**: Tasks already completed
- **Upcoming**: Future scheduled tasks

### Task Filters

Filter tasks by clicking:
- **Today**: Tasks due today
- **Overdue**: Only overdue tasks
- **This Week**: Tasks due this week
- **All**: All configured tasks

### Completing Tasks

1. Find the task you want to complete
2. Click **Mark Done**
3. Add notes if required (some tasks require notes)
4. Click **Confirm Done**

### Undoing a Completion

If you marked a task done by mistake:
1. Find the completed task (shows "DONE" badge)
2. Click **Undo**

### Task Frequencies

Tasks can be configured with different frequencies:
- **Daily**: Due every day
- **Weekly**: Due on specific days of the week
- **Biweekly**: Due every two weeks
- **Monthly**: Due on specific days of the month

---

## Flock Management

Manage your poultry flocks, track production, and record events.

### Accessing Flock Management

1. Log in as admin
2. Navigate to **Flocks** in the sidebar

### Flock List

The flock list shows:
- **Status**: ACTIVE or SOLD
- **Name**: Flock identifier
- **DOB**: Date of birth
- **Quantity**: Number of birds
- **Breed**: Bird breed
- **Sold Date**: When flock was sold (if applicable)
- **Notes**: Additional information

### Creating a New Flock

1. Click **New Flock**
2. Fill in the flock details:
   - Name (required)
   - Date of Birth (required)
   - Quantity (required)
   - Breed
   - Notes
3. Click **Save**

### Activating a Flock

Only one flock can be active at a time. To activate a flock:

1. Find the flock in the list
2. Click the **Play** button
3. Confirm the activation

The previously active flock will be marked as sold.

### Viewing Flock Logs

Click the **Clipboard** icon to view production logs for a flock:
- Daily egg production
- Mortality records
- Feed consumption
- Notes

### Recording Daily Yields

1. Navigate to a flock's logs
2. Click **Daily Yields**
3. Enter production data for each day

---

## Scheduling (Admin)

Admin users can configure automated schedules for various equipment.

### Lighting Schedules (`/admin/lighting/schedules`)

Configure automatic light on/off times.

#### Creating a Light Schedule

1. Select the **Light** from the dropdown
2. Set the **On Time** (when lights turn on)
3. Set the **Off Time** (when lights turn off)
4. Check **Enabled** to activate the schedule
5. Click **Create**

#### Editing a Schedule

1. Click **Edit** on the schedule row
2. Modify the times
3. Click **Update**

#### Toggling a Schedule

Click the **ON/OFF** button to enable or disable a schedule without deleting it.

#### Important Notes

- Schedules only work when lights are in **AUTO** mode
- If a light is in MANUAL mode, schedules are ignored
- Schedules are checked every minute

### Egg Collection Schedules (`/admin/egg_collection/schedules`)

Configure automatic egg collection times with start and stop times.

### Feeding Schedules (`/admin/feeding_schedule`)

Configure feeding system schedules including:
- Move to back limit time
- Move to front limit time
- Feed hopper assignment

---

## Environment Control (Admin)

The Environment Control system automatically manages fans and pumps based on temperature and humidity.

### Accessing Environment Control

1. Log in as admin
2. Navigate to **Environment** in the sidebar

### Configuration Overview

The system uses a **step-based** approach:
- Up to 10 temperature steps can be configured
- Each step defines a target temperature and which equipment to activate
- Steps are evaluated in ascending temperature order
- Set temperature to 0°C to skip a step

### Configuring Steps

1. Click on a step tab (showing the temperature or "skipped")
2. Set the **Target Temperature**
3. Select which **Fans** should run at this step
4. Select which **Pumps** should run at this step
5. Repeat for other steps

### Global Settings

| Setting | Description |
|---------|-------------|
| **Stagger Delay** | Seconds between starting each fan (prevents power surge) |
| **Delay Between Steps** | Minimum seconds before changing to a different step |
| **Humidity Minimum** | Below this %, pumps are turned off |
| **Humidity Maximum** | Above this %, pumps are turned off |
| **Poll Interval** | How often to check sensors (milliseconds) |
| **Enable Automation** | Master switch for the entire system |

### Panel-Controlled Equipment Warning

If any fan or pump shows in the amber "Panel Controlled" section, it means that equipment's physical switch is not in AUTO position. The software cannot control it until the panel switch is moved to AUTO.

### Saving Configuration

Click **Save Configuration** at the bottom to apply changes.

---

## Alarm System (Admin)

Configure conditions that trigger sirens when thresholds are exceeded.

### Accessing Alarm Rules

1. Log in as admin
2. Navigate to **Alarm Rules** in the sidebar

### Alarm Rule Components

Each alarm rule has:
- **Name**: Descriptive name for the alarm
- **Sirens**: Which siren(s) to trigger
- **Logic**: How conditions are evaluated (ANY or ALL)
- **Auto Clear**: Whether alarm clears automatically or requires acknowledgment
- **Max Mute**: Maximum minutes an alarm can be muted
- **Conditions**: The actual trigger conditions

### Logic Modes

| Logic | Description |
|-------|-------------|
| **ANY** | Alarm triggers if ANY condition is true (OR logic) |
| **ALL** | Alarm triggers only if ALL conditions are true (AND logic) |

### Clear Modes

| Mode | Description |
|------|-------------|
| **Auto** | Alarm clears automatically when conditions return to normal |
| **Manual** | Alarm requires acknowledgment even after conditions clear |

### Creating an Alarm Rule

1. Click **New Alarm Rule**
2. Enter the rule name
3. Select the siren(s) to trigger
4. Choose logic mode (ANY/ALL)
5. Configure auto-clear and max mute time
6. Add conditions:
   - **Sensor conditions**: Above/below temperature, humidity, etc.
   - **Equipment conditions**: Equipment off, not running, in error
7. Click **Save**

### Condition Types

#### Sensor Conditions
| Condition | Description |
|-----------|-------------|
| **above** | Value exceeds threshold |
| **below** | Value falls below threshold |
| **equals** | Value equals threshold |

#### Equipment Conditions
| Condition | Description |
|-----------|-------------|
| **off** | Equipment is turned off |
| **not_running** | Equipment is not running (may be commanded on but not responding) |
| **error** | Equipment has an error condition |

### Example Configurations

**High Temperature Alarm**:
- Logic: ANY
- Auto Clear: Yes
- Conditions: temp_sensor_1 above 35, temp_sensor_2 above 35
- Result: Siren triggers if any sensor exceeds 35°C

**Ventilation Failure**:
- Logic: ALL
- Auto Clear: Yes
- Conditions: temp_sensor_1 above 32, fan_1 not_running
- Result: Siren only triggers if both high temp AND fan not running

---

## Interlock System (Admin)

Interlocks are safety rules that prevent equipment from starting unless prerequisites are met.

### Accessing Interlock Rules

1. Log in as admin
2. Navigate to **Interlocks** in the sidebar

### How Interlocks Work

An interlock defines a dependency between two pieces of equipment:
- **Upstream Equipment**: The equipment that must be running
- **Downstream Equipment**: The equipment that cannot start without upstream

**Example**: Pump cannot start if Fan is not running
- Upstream: Fan
- Downstream: Pump
- Result: Trying to start the pump will be blocked if the fan isn't running

### Creating an Interlock Rule

1. Click **New Rule**
2. Select the **Upstream Equipment** (must be running)
3. Select the **Downstream Equipment** (depends on upstream)
4. Ensure **Enabled** is checked
5. Click **Save**

### Toggling Interlocks

Click the **ON/OFF** button to temporarily disable an interlock without deleting it.

---

## Reports & Logs

View historical data, equipment events, and sensor readings.

### Accessing Reports

1. Log in as admin
2. Navigate to **Reports** from the sidebar (under the System section)

### Report Types

#### Equipment Events

View all equipment state changes, starts, stops, and errors.

**Filters**:
- **Equipment**: Filter by specific equipment
- **Event Type**: All, Start, Stop, or Error
- **Mode**: All, Auto, or Manual
- **Time Range**: Last 6 hours, 24 hours, 3 days, or 7 days

**Columns**:
- Time
- Equipment name
- Event type (START/STOP/ERROR)
- State change (from → to)
- Mode (AUTO/MANUAL)
- Triggered by (user, schedule, auto_control, etc.)
- Details/metadata

#### Sensor Data

View temperature and humidity readings from sensors.

1. Select a sensor from the buttons
2. View the readings table showing:
   - Time
   - Temperature (°C)
   - Humidity (%)
   - Dew Point (°C)

Snapshots are recorded every 30 minutes.

#### Water Meters

View water consumption data:
- **Daily Consumption**: Last 7 days summary
- **Raw Data**: Flow rate, cumulative, temperature, pressure, battery

#### Power Meters

View electrical data:
- Voltage per phase (L1, L2, L3)
- Total power
- Power factor
- Frequency
- Energy consumption

#### Daily Summaries

View aggregated daily statistics:
- Select date range (From/To)
- View per-equipment summaries including:
  - Average temperature/humidity
  - Total runtime (minutes)
  - Total cycles (on/off)
  - Error count

#### Errors

View only error events with filtering by time range. Shows:
- Time
- Equipment name
- Previous state
- Mode
- Error details

---

## System Administration

### Settings (`/admin/settings`)

Configure system-wide settings:

#### User Password

Set a password for the "user" role (limited access):
1. Enter new password
2. Confirm password
3. Click **Save Settings**

#### House ID

Set an identifier for this installation:
- Used for multi-house deployments
- Stored in uppercase
- Example: H1, HOUSE_A, FARM_1

#### Timezone

Select the timezone for displaying dates and times.

### Port Configuration (`/admin/ports`)

Configure communication ports for hardware devices.

#### Protocol Types

| Protocol | Use Case |
|----------|----------|
| **Modbus RTU** | RS485 serial communication |
| **Siemens S7** | Siemens PLC via TCP/IP |
| **Virtual** | Simulated devices for testing |

#### Modbus RTU Settings

- **Device Path**: Serial port (e.g., `/dev/ttyUSB0`)
- **Speed**: Baud rate (typically 9600)
- **Parity**: none, even, or odd
- **Data Bits**: Usually 8
- **Stop Bits**: Usually 1

#### Siemens S7 Settings

- **IP Address**: PLC IP address
- **Rack**: Usually 0
- **Slot**: 1 for ET200SP, 2 for S7-300/400

### Data Points (`/admin/data_points`)

Configure data point mappings for reading/writing hardware values. Data points define the connection between equipment and physical I/O:

- **Name**: Unique identifier for the data point
- **Port**: Which communication port to use
- **Address**: Device/slave address on the bus
- **Register**: Register number or memory location
- **Type**: Data type (coil, input, holding register, etc.)

Data points are protocol-agnostic and work with Modbus RTU, Siemens S7, or Virtual protocols.

### Equipment (`/admin/equipment`)

Define equipment with their associated data points.

#### Equipment Types

| Type | Description |
|------|-------------|
| `fan` | Ventilation fan |
| `pump` | Water/cooling pump |
| `light` | Lighting row |
| `egg` | Egg collection belt |
| `feeding` | Feeding cart |
| `feed_in` | Feed hopper |
| `dung` | Manure scraper |
| `dung_horz` | Horizontal scraper |
| `dung_exit` | Vertical exit |
| `temp_sensor` | Temperature sensor |
| `humidity_sensor` | Humidity sensor |
| `co2_sensor` | Carbon dioxide sensor |
| `nh3_sensor` | Ammonia sensor |
| `average_sensor` | Calculated average from multiple sensors |
| `water_meter` | Water flow meter |
| `power_meter` | Power meter |
| `siren` | Alarm siren |
| `power_indicator` | Power status indicator |

#### Data Point Tree

Each equipment type requires specific data points in JSON format:

```json
{
  "on_off_coil": "relay_1",
  "running_feedback": "di_1",
  "auto_manual": "di_auto_1"
}
```

Required keys vary by equipment type and are displayed when editing.

### Task Templates (`/admin/tasks`)

Configure recurring operations tasks.

#### Task Properties

- **Name**: Task description
- **Description**: Detailed instructions
- **Category**: Grouping category
- **Frequency**: daily, weekly, biweekly, monthly
- **Time Window**: Expected completion time
- **Priority**: low, normal, high, urgent
- **Requires Notes**: Whether notes are mandatory

### System Time (`/admin/system_time`)

View and manually set system time for embedded devices. This feature is primarily used when:
- The RTC (Real-Time Clock) battery has failed and time resets on power loss
- The device has no network connection for automatic NTP sync
- Time needs to be corrected after extended power outages

#### Features

| Function | Description |
|----------|-------------|
| **Current Time** | Shows system time and whether NTP sync is active |
| **Set Date/Time** | Manually set the system clock |
| **Sync to Hardware** | Write system time to the RTC chip |
| **Enable NTP** | Turn on automatic network time sync |

#### Setup Required

System time management requires sudo permissions. Run once during deployment:
```bash
sudo bash /opt/pou_con/setup_sudo.sh
```

This enables the web interface to run `date`, `hwclock`, and `timedatectl` commands.

#### Why Time Matters

Accurate time is critical for:
- Equipment event logs (when did the pump start?)
- Scheduled operations (lighting, feeding, egg collection)
- Daily summary reports
- Alarm history timestamps

If the RTC battery fails and power is lost, the system may boot with an incorrect date (often January 1970). Use this page to correct the time before normal operations resume.

### Backup & Restore (`/admin/backup`)

Manage database backups:

#### Creating a Backup
1. Click **Create Backup**
2. The system creates a timestamped backup file
3. Download the backup for off-site storage

#### Restoring from Backup
1. Select a backup file to upload
2. Click **Restore**
3. Confirm the restore operation

**Warning**: Restoring a backup will overwrite all current data.

### System Management (`/admin/system`)

System utilities and maintenance functions:

| Function | Description |
|----------|-------------|
| **System Info** | View hardware details, OS version, uptime |
| **Reboot** | Restart the Raspberry Pi |
| **Shutdown** | Power off the system safely |
| **Service Status** | Check if PouCon service is running |

#### Setup Required

Reboot and shutdown functions require sudo permissions. Run once during deployment:
```bash
sudo bash /opt/pou_con/setup_sudo.sh
```

This is the same script used for System Time and Screen Saver setup.

### Screen Saver (`/admin/screensaver`)

Configure screen blanking timeout to prevent screen burn-in and reduce power consumption on kiosk deployments.

#### How It Works

The screen timeout feature turns off the display after a period of inactivity. Touch the screen to wake it up.

| Setting | Description |
|---------|-------------|
| **Timeout Presets** | Quick selection: 1, 3, 5, 10, 15, 30 minutes, or Never |

The active preset is highlighted with a green border. Click any preset to change the screen timeout immediately.

#### Setup Required

Screen blanking requires the setup script to be run once during deployment:
```bash
sudo bash /opt/pou_con/setup_sudo.sh
```

This configures passwordless sudo for the screen timeout script, which controls swayidle on Wayland (labwc).

#### Backlight Device Paths

Different hardware uses different backlight paths in `/sys/class/backlight/`:

| Device | Backlight Path |
|--------|---------------|
| reTerminal DM | `lcd_backlight` or `10-0045` |
| Official 7" Display | `rpi_backlight` |
| DSI Displays | `10-0045` |

PouCon automatically discovers the correct backlight path.

#### Troubleshooting Screen Blanking

**"Setup Required" message appears:**
- Run `sudo bash /opt/pou_con/setup_sudo.sh` on the Raspberry Pi
- Refresh the page after running the script

**"No display detected" message:**
- Screen controls only work on deployed Raspberry Pi hardware
- This is normal when testing on a development machine

**Screen doesn't blank on Wayland:**
1. Check if labwc is running: `pgrep labwc`
2. Check if swayidle is running: `pgrep -u pou_con swayidle`
3. Verify autostart file exists: `cat /home/pou_con/.config/labwc/autostart`
4. Test backlight manually: `echo 0 | sudo tee /sys/class/backlight/lcd_backlight/brightness`

**Screen doesn't wake on touch:**
- Ensure the resume command is configured in swayidle
- Check max_brightness value: `cat /sys/class/backlight/lcd_backlight/max_brightness`
- Manually wake: `echo 5 | sudo tee /sys/class/backlight/lcd_backlight/brightness`

#### Technical Details

Screen blanking on Raspberry Pi OS Bookworm (Wayland/labwc) uses:
- `swayidle` daemon to detect inactivity (runs as `pou_con` user)
- Direct backlight control via sysfs (`/sys/class/backlight/*/brightness`)
- Configuration stored in `/home/pou_con/.config/labwc/autostart`

---

## Troubleshooting

### Equipment Shows "OFFLINE"

**Cause**: No communication with the hardware device.

**Solutions**:
1. Check the physical connection (cables, power)
2. Verify port configuration matches hardware settings
3. Check if the Modbus slave address is correct
4. Try reloading the ports (Dashboard → Reload)

### Equipment Shows Error State

**Common Errors**:

| Error | Meaning | Solution |
|-------|---------|----------|
| `timeout` | No response from hardware | Check connections |
| `command_failed` | Write command rejected | Check wiring/settings |
| `on_but_not_running` | Commanded ON but not running | Check motor, circuit breaker |
| `off_but_running` | Commanded OFF but still running | Check contactor, wiring |
| `invalid_data` | Sensor reading out of range | Check sensor calibration |

### Schedules Not Working

**Check**:
1. Is the schedule enabled? (Toggle should show ON)
2. Is the equipment in AUTO mode? (Panel switch position)
3. Is the time correct? (System time settings)
4. Is the main automation enabled? (Environment Control page)

### Alarm Not Triggering

**Check**:
1. Is the alarm rule enabled?
2. Are the conditions correctly configured?
3. Are the sensors providing valid data?
4. Check Reports → Errors for any equipment issues

### Cannot Log In

1. If you forgot the admin password, you'll need to reset it via the database
2. If you get "Invalid password", double-check caps lock
3. User password may not be set - ask admin to configure it

### Page Not Loading

1. Check network connection
2. Verify the server is running
3. Check browser console for errors
4. Try refreshing the page or clearing browser cache

---

## On-Screen Keyboard

PouCon includes a built-in on-screen keyboard for touchscreen devices, eliminating the need for external system keyboards.

### Keyboard Toggle Button

A floating button appears in the **bottom-right corner** of every page:

| Button | Mode | Behavior |
|--------|------|----------|
| **⌨A** (blue) | Auto | Keyboard shows when you tap an input field, hides when you tap away |
| **⌨S** (green) | Always Show | Keyboard remains visible at all times |
| **⌨H** (gray) | Always Hide | Keyboard never appears (use when physical keyboard is connected) |

**To change modes**: Click/tap the toggle button to cycle through: Auto → Always Show → Always Hide → Auto

The selected mode is saved and persists across page reloads and browser sessions.

### Keyboard Layout

The on-screen keyboard includes:

| Key | Function |
|-----|----------|
| **⇧** (Shift) | Toggle uppercase letters and symbols |
| **⌫** (Backspace) | Delete character before cursor |
| **Tab ⇥** | Move to the next input field |
| **Space** | Insert space character |

### Using the Keyboard

1. **Auto Mode** (Default):
   - Tap any text input field to show the keyboard
   - The keyboard appears at the bottom center of the screen
   - Tap outside input fields to hide the keyboard

2. **Always Show Mode**:
   - Useful for data entry tasks with multiple fields
   - Keyboard stays visible even when no field is focused
   - Switch to this mode when filling forms

3. **Always Hide Mode**:
   - Use when a physical USB/Bluetooth keyboard is connected
   - Prevents accidental keyboard popup on touch

### Tips for Touch Devices

- The keyboard automatically scrolls the focused input field into view
- Use the **Tab** key to quickly move through form fields
- The keyboard takes up 50% of screen width for comfortable typing
- Body content adjusts to prevent the keyboard from covering inputs

### Raspberry Pi Kiosk Mode

When running PouCon in fullscreen/kiosk mode on Raspberry Pi:
- Kiosk mode runs as the `pou_con` user (same user as the PouCon service)
- **Disable the system on-screen keyboard** (Onboard) to avoid conflicts
- Use PouCon's built-in keyboard instead
- The web-based keyboard always appears above page content

To disable Raspbian's Onboard keyboard for the kiosk user:
```bash
sudo -u pou_con mkdir -p /home/pou_con/.config/autostart
echo -e "[Desktop Entry]\nHidden=true" | sudo -u pou_con tee /home/pou_con/.config/autostart/onboard-autostart.desktop
```

---

## Technical Support

For technical issues:
1. Check the error logs in Reports → Errors
2. Document the issue with screenshots
3. Note the equipment name and time of occurrence
4. Contact your system administrator

---

*PouCon - Industrial Automation for Modern Poultry Farming*

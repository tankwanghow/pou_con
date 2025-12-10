# Industrial Computer and HMI Recommendations for PouCon

This document provides hardware recommendations for deploying PouCon in poultry farm environments.

## Current Hardware Setup

- **Digital I/O**: Waveshare Modbus RTU IO 8CH (https://www.waveshare.com/wiki/Modbus_RTU_IO_8CH)
- **Sensors**: Cytron Industrial Grade RS485 Temperature/Humidity Sensor
- **Electrical Panel**: Provided by contractor (relays, contactors, limit switches, motors, power supply)
- **Communication**: RS485 Modbus RTU

## Industrial Raspberry Pi Options

### 🏆 Top Recommendation: Revolution Pi (RevPi)

**RevPi Connect 4** (~$180-250 USD)
- Built on RPi Compute Module 4
- DIN rail mountable
- Industrial temperature range (-40°C to +55°C)
- 24V power input (standard industrial)
- Real-time clock with battery backup
- Watchdog timer (auto-restart on hang)
- CE certified for industrial use

**Why it's best for PouCon:**
```
✅ Designed for 24/7 industrial automation
✅ Built-in RS485 interface (native Modbus support)
✅ Can mount directly in electrical panel
✅ Survives poultry farm conditions (dust, humidity, temp swings)
✅ 24V power = same as Waveshare modules
✅ Large community in industrial automation
```

**Alternative RevPi models:**
- **RevPi Core 3+** (~$150) - Cheaper, RPi 3 based, still solid
- **RevPi Connect S** (~$300) - Premium, more I/O options

**Where to buy:**
- https://revolutionpi.com/
- Distributors worldwide

### 🥈 Alternative 1: UniPi Neuron

**UniPi Neuron M503** (~$200-280 USD)
- RPi Compute Module 3+ based
- DIN rail mountable
- Built-in I/O (can reduce need for Waveshare modules)
- Built-in Modbus support
- Industrial enclosure

**Pros:**
```
✅ Built-in I/O might replace some Waveshare modules
✅ DIN rail mount
✅ Industrial grade
```

**Cons:**
```
❌ Older RPi 3 hardware (slower than CM4)
❌ Less community support than RevPi
```

### 🥉 Alternative 2: Compute Blade (with enclosure)

**Compute Blade CM4** (~$120 blade + $80 enclosure)
- Uses RPi CM4
- Modular design
- Can add industrial enclosure separately

**Pros:**
```
✅ Modern CM4 hardware (same as RevPi Connect 4)
✅ Upgradeable/modular
✅ Lower base cost
```

**Cons:**
```
❌ Need to buy industrial enclosure separately
❌ Not pre-certified for industrial use
❌ More DIY assembly required
```

### ⚠️ NOT Recommended: Standard RPi 4/5

**Why avoid consumer RPi:**
```
❌ Not rated for industrial temperatures
❌ No DIN rail mounting
❌ Plastic case won't survive panel environment
❌ No watchdog timer (needs software workaround)
❌ MicroSD cards fail in 24/7 operation
❌ 5V power is finicky in industrial panels
```

If budget is tight, at least use:
- Industrial SD card (SLC flash, not consumer MLC)
- Metal case with fan
- UPS or 5V rail with capacitors
- External watchdog module

## Touch Screen / HMI Options

### 🏆 Top Recommendation: Industrial HMI Touch Panel

**Weintek cMT-SVR** (~$300-400 USD)
- 7" or 10" industrial touch screen
- Panel mount (fits in electrical panel door)
- Built-in web browser (access your Phoenix LiveView app)
- IP65 rated front panel (dust/water resistant)
- Wide temperature range (-20°C to +60°C)
- 24V power input

**Perfect for PouCon because:**
```
✅ Runs standard web browser → Your LiveView app works as-is
✅ Panel mount → Professional installation
✅ IP65 → Survives poultry farm (washdowns, dust)
✅ 24V power → Same as other equipment
✅ No additional software needed
✅ Touch works with gloves (resistive or capacitive options)
```

**URL Configuration:**
```
Just point browser to: http://<revpi-ip>:4000
Kiosk mode: Full screen, no browser UI
Auto-start on boot
```

**Alternative HMI brands:**
- **Advantech** (WebOP-3000 series)
- **Siemens** (SIMATIC HMI Comfort Panels)
- **Maple Systems** (HMI5000 series)

### 🥈 Alternative: Industrial Raspberry Pi Touch Screen

**Waveshare Industrial 10.1" HDMI LCD** (~$150-200 USD)
- HDMI + USB touch
- Metal enclosure
- Can mount behind panel window
- Capacitive touch

**Setup:**
```bash
# Install Chromium in kiosk mode on the RevPi/screen
sudo apt-get install chromium-browser unclutter

# Create kiosk startup script
# /home/poucon/start_kiosk.sh
#!/bin/bash
xset s off
xset -dpms
xset s noblank
unclutter -idle 0 &
chromium-browser --kiosk --disable-infobars \
  --noerrdialogs --disable-session-crashed-bubble \
  http://localhost:4000
```

**Pros:**
```
✅ Cheaper than dedicated HMI
✅ Direct HDMI connection to RevPi
✅ Good resolution (1280x800)
```

**Cons:**
```
❌ Need to manage Linux desktop environment
❌ Less rugged than dedicated HMI
❌ Not IP-rated (need separate enclosure for panel mount)
```

### 🥉 Budget Option: Tablet in Industrial Enclosure

**Amazon Fire HD 10 + RAM Mounts Panel Dock** (~$150 + $100)
- Commercial Android tablet
- Industrial mounting solution
- WiFi connection

**Pros:**
```
✅ Cheapest option (~$250 total)
✅ Easy to replace if damaged
✅ Good screen quality
✅ Touch works well
```

**Cons:**
```
❌ Consumer device (will fail faster)
❌ WiFi dependency (add industrial WAP)
❌ Need kiosk mode app (Android)
❌ Battery swells in heat (safety issue!)
```

**If using tablet:**
1. Remove battery (run on USB power only)
2. Use kiosk mode app (Fully Kiosk Browser)
3. Industrial enclosure with cooling
4. Consider it disposable (replace yearly)

## Complete System Architecture

```
┌─────────────────────────────────────────────────────────┐
│ ELECTRICAL PANEL                                        │
│                                                         │
│  ┌──────────────────┐    24V Power Supply             │
│  │  RevPi Connect 4 │    ↓ ↓ ↓ ↓ ↓                    │
│  │  (Brain)         │    │ │ │ │ │                    │
│  │  - Phoenix App   │────┤ │ │ │ │                    │
│  │  - DeviceManager │    │ │ │ │ │                    │
│  └─────────┬────────┘    │ │ │ │ │                    │
│            │ RS485       │ │ │ │ │                    │
│            ├─────────────┴─┴─┴─┴─┴──── A/B/GND        │
│            │                                           │
│  ┌─────────┴────────────┐  ┌──────────────────┐      │
│  │ Waveshare Modbus IO  │  │ Cytron Temp/Hum  │      │
│  │ (Digital I/O)        │  │ Sensor           │      │
│  │ - 8 relay outputs    │  │ (RS485)          │      │
│  │ - 8 digital inputs   │  └──────────────────┘      │
│  └──────────────────────┘                             │
│           ↓ Relay Outputs                             │
│  ┌────────────────────────────────────┐               │
│  │ Contactors / Relays                │               │
│  │ → Fans, Pumps, Lights, Feeders     │               │
│  └────────────────────────────────────┘               │
│           ↑ Limit Switches / Sensors                  │
│  ┌────────────────────────────────────┐               │
│  │ Field Devices                      │               │
│  │ → Limit switches, motor feedback   │               │
│  └────────────────────────────────────┘               │
└─────────────────────────────────────────────────────────┘
                      │ Ethernet
                      ↓
              ┌───────────────┐
              │ HMI Panel     │  (Mounted on panel door)
              │ (Touch Screen)│  IP65 front, web browser
              │ 7" or 10"     │  → http://revpi:4000
              └───────────────┘
```

## Complete Bill of Materials (BOM)

### Professional Grade Setup

| Item | Model | Price (USD) | Notes |
|------|-------|-------------|-------|
| **Brain** | RevPi Connect 4 | $220 | Industrial RPi CM4 |
| **I/O Module** | Waveshare RTU IO 8CH | $85 | Already owned |
| **Sensor** | Cytron RS485 Temp/Hum | $45 | Already owned |
| **Touch Screen** | Weintek cMT-SVR 7" | $350 | Industrial HMI panel |
| **24V Power Supply** | Mean Well HDR-100-24 | $40 | DIN rail mount |
| **RS485 Cable** | Shielded twisted pair | $20 | 100m spool |
| **Network Switch** | Industrial 5-port | $60 | DIN rail, RevPi ↔ HMI |
| **MicroSD Card** | Industrial SLC 32GB | $30 | RevPi boot drive |
| **USB Drive** | Industrial USB 32GB | $25 | Database storage |
| **Enclosure Extras** | DIN rail, terminals | $50 | Mounting hardware |
| **TOTAL** | | **~$925** | Complete system |

### Budget Alternative (~$600)

| Item | Model | Price (USD) | Notes |
|------|-------|-------------|-------|
| **Brain** | RevPi Core 3+ | $150 | RPi 3 based (slower) |
| **I/O Module** | Waveshare RTU IO 8CH | $85 | Already owned |
| **Sensor** | Cytron RS485 Temp/Hum | $45 | Already owned |
| **Touch Screen** | Waveshare 10.1" Industrial LCD | $180 | Direct HDMI connection |
| **24V Power Supply** | Mean Well HDR-100-24 | $40 | DIN rail mount |
| **RS485 Cable** | Shielded twisted pair | $20 | 100m spool |
| **Network Switch** | TP-Link 5-port | $25 | Desktop switch |
| **MicroSD Card** | SanDisk High Endurance 32GB | $15 | Consumer grade |
| **USB Drive** | SanDisk USB 3.0 32GB | $10 | Database storage |
| **Enclosure Extras** | DIN rail, terminals | $50 | Mounting hardware |
| **TOTAL** | | **~$620** | Budget system |

## Network Configuration

### Option 1: Ethernet (Recommended)
```
RevPi: eth0 = 192.168.1.10 (static IP)
HMI:         = 192.168.1.50 (static IP)
Connect via industrial switch in panel
```

**Configure static IP on RevPi:**
```bash
# /etc/network/interfaces
auto eth0
iface eth0 inet static
    address 192.168.1.10
    netmask 255.255.255.0
    gateway 192.168.1.1
```

### Option 2: WiFi (If HMI is far from panel)
```
Add industrial WiFi access point in panel
RevPi: eth0 (hardwired to switch)
HMI: WiFi to access point
Still works with LiveView WebSocket
```

## Storage Considerations

**CRITICAL for 24/7 operation:**

### RevPi Boot Drive
```bash
# Use industrial SD card OR move to USB
# Industrial SD: SanDisk Industrial, ATP, Innodisk
# OR USB drive (more reliable than consumer SD)

# In config.exs - reduce SD writes
config :logger,
  backends: [:console],  # Don't log to file
  level: :info  # Less verbose

# Database on USB instead of SD
DATABASE_PATH=/mnt/usb/pou_con.db mix phx.server
```

### Mount USB Drive for Database
```bash
# Format USB drive as ext4
sudo mkfs.ext4 /dev/sda1

# Create mount point
sudo mkdir -p /mnt/usb

# Add to /etc/fstab for auto-mount
UUID=xxxx-xxxx-xxxx /mnt/usb ext4 defaults,noatime 0 2

# Mount
sudo mount -a

# Verify
df -h /mnt/usb
```

### Configure PouCon for USB Database
```bash
# Create systemd service
# /etc/systemd/system/poucon.service
[Unit]
Description=PouCon Industrial Automation
After=network.target local-fs.target

[Service]
Type=simple
User=poucon
WorkingDirectory=/home/poucon/pou_con
Environment="PORT=4000"
Environment="DATABASE_PATH=/mnt/usb/pou_con.db"
Environment="SECRET_KEY_BASE=<your-secret>"
Environment="MIX_ENV=prod"
ExecStart=/home/poucon/pou_con/_build/prod/rel/pou_con/bin/pou_con start
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

## Power Supply Recommendations

**Mean Well HDR-100-24** ($40)
```
✅ DIN rail mount
✅ 24V/4.2A output (100W)
✅ Powers: RevPi + Waveshare + Cytron + HMI
✅ 85-264VAC input (universal)
✅ Industrial grade, -30°C to +70°C
```

**Wiring:**
```
120/240VAC → HDR-100-24 → 24VDC bus
                          ├→ RevPi (12-24V tolerant)
                          ├→ Waveshare IO (24V)
                          ├→ Cytron Sensor (24V)
                          └→ HMI Panel (24V)
```

**Power Calculation:**
```
RevPi Connect 4:     ~15W (0.6A @ 24V)
Waveshare IO:        ~5W  (0.2A @ 24V)
Cytron Sensor:       ~3W  (0.1A @ 24V)
HMI Panel 7":        ~10W (0.4A @ 24V)
Network Switch:      ~5W  (0.2A @ 24V)
───────────────────────────────────────
Total:               ~38W (1.5A @ 24V)
HDR-100-24 capacity: 100W (4.2A @ 24V) ✓ 62% headroom
```

## Additional Considerations

### 1. UPS / Battery Backup

For graceful shutdown during power failures:

**Phoenix Contact QUINT UPS (24V)** - $150
- 24V battery backup
- 10-15 minutes runtime
- Shutdown signal to RevPi

```elixir
# lib/pou_con/ups_monitor.ex
defmodule PouCon.UPSMonitor do
  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    # Check UPS status every 10 seconds
    :timer.send_interval(10_000, :check_power)
    {:ok, state}
  end

  def handle_info(:check_power, state) do
    case check_ups_status() do
      :battery_low ->
        Logger.error("UPS battery low, shutting down gracefully")
        # Stop accepting new requests
        Phoenix.Endpoint.broadcast("system", "shutdown_warning", %{})
        # Give 30 seconds for cleanup
        Process.sleep(30_000)
        System.cmd("sudo", ["shutdown", "-h", "now"])
      :on_battery ->
        Logger.warning("Running on UPS battery")
      :ac_power ->
        :ok
    end
    {:noreply, state}
  end

  defp check_ups_status do
    # Read UPS status from GPIO or Modbus
    # Implementation depends on UPS model
    :ac_power
  end
end
```

Add to supervision tree in `application.ex`:
```elixir
children = [
  # ... existing children
  PouCon.UPSMonitor
]
```

### 2. Watchdog Timer

RevPi has built-in watchdog, enable it:

```bash
# Enable hardware watchdog
# /boot/config.txt
dtparam=watchdog=on

# Install watchdog daemon
sudo apt-get install watchdog

# Configure watchdog
# /etc/watchdog.conf
watchdog-device = /dev/watchdog
watchdog-timeout = 15
interval = 5
max-load-1 = 24

# Enable service
sudo systemctl enable watchdog
sudo systemctl start watchdog
```

Phoenix app keeps watchdog alive via heartbeat (automatic with systemd).

### 3. Temperature Management

Poultry farms get hot (35°C+):

**Thermal considerations:**
```
✅ RevPi rated to +55°C (good for poultry farms)
✅ Add ventilation holes in panel door (with dust filter)
⚠️ HMI generates heat (backlight) - consider passive cooling
⚠️ Keep SD card backups (heat degrades flash memory)
⚠️ Industrial SD cards are rated for higher temps
```

**Monitoring temperature:**
```elixir
# Read RevPi internal temperature
defmodule PouCon.SystemMonitor do
  def get_cpu_temp do
    case File.read("/sys/class/thermal/thermal_zone0/temp") do
      {:ok, temp_str} ->
        temp_millidegrees = String.trim(temp_str) |> String.to_integer()
        temp_celsius = temp_millidegrees / 1000.0
        {:ok, temp_celsius}
      error ->
        error
    end
  end

  def check_thermal_throttling do
    # Log warning if CPU is thermal throttling
    case get_cpu_temp() do
      {:ok, temp} when temp > 75.0 ->
        Logger.warning("High CPU temperature: #{temp}°C")
      _ ->
        :ok
    end
  end
end
```

### 4. Humidity / Dust Protection

**Environmental ratings:**
```
- Panel: IP54 minimum (dust/splash proof)
- Cable glands: IP68 for RS485 cables entering panel
- HMI: IP65 front panel (can be wiped/washed)
- RevPi: Conformal coating on PCB (already done by manufacturer)
```

**Best practices:**
```
✅ Use cable glands for all external wiring
✅ Apply silicone sealant on panel penetrations
✅ Keep panel door gasket in good condition
✅ Mount panel away from water jets (if washdown area)
✅ Use stainless steel or powder-coated steel enclosure
```

## Complete Recommendation Summary

### For Professional, Reliable Deployment

**Core System:**
```yaml
Brain: RevPi Connect 4 ($220)
  - Industrial RPi CM4, 24V power, DIN rail
  - Survives poultry environment
  - Built-in watchdog, RTC, RS485

HMI: Weintek cMT-SVR 7" ($350)
  - IP65 front panel
  - Built-in web browser → PouCon works as-is
  - Panel mount, 24V power
  - Professional appearance

Storage: Industrial SD + USB backup ($55)
  - Boot from industrial SD card
  - Database on industrial USB drive
  - Automatic daily backups

Power: Mean Well HDR-100-24 ($40)
  - Powers all devices from single 24V bus
  - DIN rail mount
  - Universal input voltage

Network: Industrial 5-port switch ($60)
  - DIN rail mount
  - RevPi ↔ HMI Ethernet
  - Reliable connection

Total: ~$725 + your existing Waveshare/Cytron
```

**This gives you:**
```
✅ Industrial-grade reliability (24/7 for years)
✅ Professional installation (all DIN rail mounted)
✅ Easy maintenance (standard web browser)
✅ Environmental protection (proper IP ratings)
✅ Standard industrial voltages (24V throughout)
✅ No changes to PouCon application code
```

## Deployment Checklist

### Pre-Installation

- [ ] Order RevPi Connect 4 and accessories
- [ ] Order HMI panel (Weintek or equivalent)
- [ ] Order power supply and industrial switch
- [ ] Order industrial SD card and USB drive
- [ ] Verify panel space and DIN rail availability
- [ ] Plan RS485 cable routing
- [ ] Plan Ethernet cable routing

### Installation

- [ ] Mount RevPi on DIN rail
- [ ] Mount power supply on DIN rail
- [ ] Wire 24V power distribution
- [ ] Install RS485 terminators (120Ω at each end)
- [ ] Connect Waveshare IO to RS485 bus
- [ ] Connect Cytron sensor to RS485 bus
- [ ] Mount network switch
- [ ] Run Ethernet cable to HMI location
- [ ] Mount HMI panel on door
- [ ] Configure static IP addresses

### Software Setup

- [ ] Flash Raspberry Pi OS to industrial SD card
- [ ] Configure watchdog timer
- [ ] Set up auto-mount for USB drive
- [ ] Build PouCon production release
- [ ] Create systemd service
- [ ] Configure HMI web browser (kiosk mode)
- [ ] Set up automatic backups
- [ ] Test system recovery after power cycle

### Testing

- [ ] Verify all Modbus devices communicate
- [ ] Test equipment control (fans, pumps, lights)
- [ ] Test HMI touch screen functionality
- [ ] Simulate power failure (test UPS if installed)
- [ ] Run system for 24 hours under load
- [ ] Verify logging and data retention
- [ ] Test remote access (if configured)

### Documentation

- [ ] Document IP addresses and network config
- [ ] Label all cables and connections
- [ ] Create as-built electrical drawings
- [ ] Document backup/restore procedures
- [ ] Create operator training materials

## Support and Resources

**RevPi Resources:**
- Documentation: https://revolutionpi.com/tutorials/
- Forum: https://revolutionpi.com/forum/
- GitHub: https://github.com/RevolutionPi

**Modbus Resources:**
- Waveshare Wiki: https://www.waveshare.com/wiki/Modbus_RTU_IO_8CH
- Cytron Datasheet: Available on their website

**PouCon Resources:**
- Application code: This repository
- CLAUDE.md: Architecture and development guide
- LOGGING_INTEGRATION_GUIDE.md: Logging patterns

**Industrial Automation:**
- Phoenix Contact: https://www.phoenixcontact.com/ (DIN rail components)
- Mean Well: https://www.meanwell.com/ (Power supplies)
- Weintek: https://www.weintek.com/ (HMI panels)

## Maintenance Schedule

**Weekly:**
- Check system logs for errors
- Verify all equipment responding
- Check panel temperature

**Monthly:**
- Review equipment event logs
- Verify database backups
- Clean HMI touch screen
- Check cable connections

**Quarterly:**
- Update PouCon software (if new version)
- Test UPS battery (if installed)
- Verify watchdog timer operation
- Clean panel ventilation filters

**Annually:**
- Replace industrial SD card (preventive)
- Full system backup
- Review and update documentation
- Consider firmware updates for RevPi

---

**Your Phoenix/Elixir PouCon application needs ZERO code changes** - it just runs on industrial hardware instead of a desktop! The adapter pattern you built makes this seamless.

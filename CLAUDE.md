# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**PouCon** is an industrial automation and control system for poultry farms built with Elixir and Phoenix LiveView. It provides real-time hardware monitoring and control for poultry farm equipment through Modbus RTU/TCP protocol communication. The system runs on embedded hardware (Raspberry Pi) with SQLite database for persistence.

## Common Commands

### Development

```bash
# Setup project (first time)
mix setup

# Start development server with device simulation
SIMULATE_DEVICES=1 mix phx.server

# Start with interactive shell (recommended for debugging)
SIMULATE_DEVICES=1 iex -S mix phx.server

# Start with real hardware (no simulation)
mix phx.server
```

### Testing

```bash
# Run all tests
mix test

# Run specific test file
mix test test/pou_con/equipment/controllers/fan_test.exs

# Run tests with coverage
mix test --cover

# Run tests matching a pattern
mix test --only integration
```

### Database

```bash
# Run migrations
mix ecto.migrate

# Rollback migration
mix ecto.rollback

# Reset database (drop, create, migrate, seed)
mix ecto.reset

# Create new migration
mix ecto.gen.migration migration_name
```

### Code Quality

```bash
# Format code
mix format

# Compile with warnings as errors
mix compile --warnings-as-errors

# Pre-commit checks (compile, format, test)
mix precommit
```

### Data Management

```bash
# Export current database to seed JSON files
mix export_seeds
```

### Production

```bash
# Build production release
MIX_ENV=prod mix release

# Run production server
PORT=4000 MIX_ENV=prod DATABASE_PATH=./pou_con_prod.db SECRET_KEY_BASE=<key> mix phx.server
```

## Architecture Overview

### Core Architectural Principles

1. **Separation of Concerns**: Hardware communication (DeviceManager) is completely separate from business logic (Controllers) and UI (LiveView)
2. **GenServer-Based Controllers**: Each equipment instance (fan_1, pump_2, etc.) runs as an independent supervised GenServer
3. **Pluggable Hardware**: Modbus adapters support both real hardware and simulated devices via compile-time configuration
4. **Real-time Updates**: Phoenix PubSub broadcasts state changes to LiveView components for instant UI updates
5. **Crash Recovery**: DynamicSupervisor with aggressive restart policy ensures equipment controllers automatically recover from crashes

### System Layers (Bottom to Top)

```
┌─────────────────────────────────────────────────┐
│  Phoenix LiveView UI (Real-time WebSocket)      │
│  - Dashboard, Controls, Reports, Admin          │
└─────────────────────────────────────────────────┘
                    ↕ PubSub
┌─────────────────────────────────────────────────┐
│  Equipment Controllers (GenServers)             │
│  - Fan, Pump, Feeding, Egg, Light, Dung, etc.   │
│  - Auto/Manual modes, State machines            │
│  - Interlock checking, Error handling           │
└─────────────────────────────────────────────────┘
                    ↕ Commands
┌─────────────────────────────────────────────────┐
│  Automation Layer                               │
│  - EnvironmentController (temp/humidity)        │
│  - Schedulers (Light, Egg, Feeding)             │
│  - InterlockController (safety chains)          │
│  - AlarmController (condition-based alerts)     │
│  - FeedInController (filling triggers)          │
└─────────────────────────────────────────────────┘
                    ↕ Query/Command
┌─────────────────────────────────────────────────┐
│  DeviceManager (Central Polling Engine)         │
│  - Polls Modbus devices every 1 second          │
│  - Caches device states in ETS                  │
│  - Executes Modbus write commands               │
│  - Broadcasts state changes via PubSub          │
└─────────────────────────────────────────────────┘
                    ↕ Modbus I/O
┌─────────────────────────────────────────────────┐
│  Hardware Layer                                 │
│  - PortSupervisor (manages connections)         │
│  - Modbus Adapters (Real or Simulated)          │
│  - Physical devices (PLCs, sensors, relays)     │
└─────────────────────────────────────────────────┘
```

### Critical Supervision Tree

The supervision tree in `lib/pou_con/application.ex` has a specific startup order that must be maintained:

1. **DeviceManager** - Must start before controllers to provide hardware interface
2. **Registry** - Must exist before DynamicSupervisor
3. **DynamicSupervisor** - Must exist before EquipmentLoader spawns controllers
4. **EquipmentLoader** (Task) - Reads equipment from database and spawns controller GenServers
5. **Automation services** - Only start in non-test environments after controllers are ready
6. **Endpoint** - Always starts last

**CRITICAL**: The DynamicSupervisor has `max_restarts: 1_000_000` and `max_seconds: 1` to ensure crashed controllers restart immediately and indefinitely. This is intentional for industrial reliability.

### Equipment Controller Pattern

All equipment controllers follow this pattern:

```elixir
defmodule PouCon.Equipment.Controllers.XXX do
  use GenServer

  # State machine with these fields:
  # - name: unique identifier
  # - mode: :auto | :manual
  # - commanded_on/commanded_target: what user/automation requested
  # - actual_on/actual_state: what hardware reports
  # - error: nil | :timeout | :command_failed | ...

  # Key behaviors:
  # 1. Subscribe to device state changes from DeviceManager
  # 2. Check interlocks before executing commands
  # 3. Log all state changes, errors, and operations
  # 4. Sync commanded vs actual state continuously
  # 5. Detect and report hardware mismatches
end
```

Controllers are registered in the Registry under their name and can be accessed via:
- `PouCon.Equipment.EquipmentCommands.turn_on("fan_1")`
- `PouCon.Equipment.EquipmentCommands.status("fan_1")`

### Hardware Abstraction (Modbus)

The system uses a behaviour-based adapter pattern for hardware communication:

- **Production**: `PouCon.Hardware.Modbus.RtuAdapter` - actual Modbus RTU
- **Development/Test**: `PouCon.Hardware.Modbus.SimulatedAdapter` - in-memory simulation

Adapter selection is controlled by `SIMULATE_DEVICES=1` environment variable (see `config/config.exs`).

The DeviceManager polls devices every 1 second and maintains an ETS cache (`:device_cache`) that controllers query for current state.

### Protocol Flexibility and Multi-Protocol Support

**IMPORTANT**: The adapter-based architecture is designed for protocol flexibility. The system can support multiple industrial protocols simultaneously with minimal code changes (90% of codebase remains untouched).

#### Adapter Pattern Benefits

The hardware abstraction layer provides complete isolation:
- **Equipment Controllers**: Protocol-agnostic, only call `DeviceManager` APIs
- **Automation Layer**: No knowledge of protocols or physical wiring
- **Logging System**: Logs equipment events, not protocol details
- **UI Layer**: Subscribes to PubSub, unaware of hardware communication
- **DeviceManager**: Uses adapter behavior, works with any request/response protocol

#### Protocol Support Matrix

**Minimal Changes (1-2 days, adapter only):**

1. **Modbus TCP/IP** - Ethernet transport, same registers as RTU
   - Change: Add TCP adapter, update port schema to support IP addresses
   - Physical: Ethernet cables replace RS485
   - Benefits: Faster, more devices, easier wiring

2. **Modbus ASCII** - RS232/RS485, ASCII hex framing
   - Change: New adapter using ASCII framing library
   - Physical: Same RS485 wiring as current RTU
   - Benefits: Human-readable frames for debugging

3. **Direct GPIO** - Raspberry Pi pins for simple devices
   - Change: GPIO adapter using `circuits_gpio` library
   - Physical: 3.3V/5V digital pins (no external hardware needed)
   - Benefits: Zero latency, no cost, good for prototyping
   - Use case: Simple relays, lights without feedback

4. **HTTP/REST APIs** - Modern IoT devices
   - Change: HTTP adapter using `Req` or `Finch` library
   - Physical: WiFi/Ethernet
   - Benefits: Vendor integration, wireless convenience
   - Use case: Smart sensors, WiFi relays, cloud devices

**Moderate Changes (3-5 days, pattern adjustment):**

1. **OPC UA** - Industry 4.0 standard, replacing OPC Classic
   - Change: OPC UA client adapter, node-to-register mapping
   - Physical: Ethernet (TCP/IP)
   - Benefits: Secure (encryption/auth), self-describing, modern PLCs
   - Use case: Siemens S7-1500, B&R, Beckhoff PLCs

2. **CANbus** - Controller Area Network
   - Change: CAN adapter using `can` library, message ID mapping
   - Physical: Twisted pair (different wiring from RS485)
   - Benefits: Very reliable, broadcast-based, automotive-grade
   - Use case: Agriculture equipment, automotive sensors

3. **PROFIBUS DP** - Process Field Bus (Siemens)
   - Change: PROFIBUS adapter, data block mapping
   - Physical: RS485 (same wiring!)
   - Benefits: Faster than Modbus (12 Mbps vs 115 Kbps)
   - Use case: Siemens PLCs

4. **BACnet** - Building Automation and Control Networks
   - Change: BACnet adapter, object-to-register mapping
   - Physical: Ethernet (BACnet/IP) or RS485 (BACnet MS/TP)
   - Benefits: HVAC industry standard
   - Use case: Climate control, building automation

**Significant Changes (1-2 weeks, architecture adjustment):**

1. **MQTT** - Message Queue Telemetry Transport
   - Change: Adjust DeviceManager for pub/sub model (push vs poll)
   - Physical: WiFi/Ethernet
   - Challenge: Requires hybrid polling + subscription model
   - Use case: IoT sensors, cloud integration

2. **Zigbee / Z-Wave** - Wireless mesh networks
   - Change: USB coordinator + adapter, device pairing workflow
   - Physical: Wireless mesh
   - Challenge: Device discovery and pairing
   - Use case: Home automation, wireless sensors

3. **LoRaWAN** - Long Range Wide Area Network
   - Change: LoRa gateway + adapter, handle high latency
   - Physical: LoRa radio module
   - Challenge: High latency (seconds), not real-time
   - Use case: Remote outdoor sensors (10km range)

#### Physical Layer Comparison

| Wiring Type | Distance | Devices | Speed | Change Effort | Use Case |
|-------------|----------|---------|-------|---------------|----------|
| RS485 (current) | 1200m | 32-247 | 115 kbps | N/A | Current Modbus RTU |
| Ethernet | 100m | Unlimited | 1 Gbps | Minimal | Modbus TCP, OPC UA |
| GPIO | 0.1m | ~20 | Instant | Minimal | Direct Pi control |
| WiFi | 50m | 254 | 600 Mbps | Moderate | IoT devices, REST APIs |
| CANbus | 1000m | 32 | 1 Mbps | Moderate | Agriculture equipment |
| LoRa | 10km | 1000s | 50 kbps | Significant | Remote sensors |

#### Multi-Protocol Deployment Strategy

The system can run **multiple protocols simultaneously**:

```elixir
# config/config.exs - Multiple adapters configured
config :pou_con, :adapters, %{
  modbus_rtu: PouCon.Hardware.Modbus.RtuAdapter,
  modbus_tcp: PouCon.Hardware.Modbus.TcpAdapter,
  gpio: PouCon.Hardware.GPIO.Adapter,
  http: PouCon.Hardware.HTTP.Adapter,
  opcua: PouCon.Hardware.OpcUa.Adapter
}

# Database schema supports protocol selection per port
schema "ports" do
  field :protocol, :string  # "modbus_rtu", "modbus_tcp", "gpio", etc.
  field :device_path, :string  # for serial protocols
  field :ip_address, :string   # for network protocols
  field :tcp_port, :integer    # for TCP protocols
  # ... protocol-specific fields
end

# PortSupervisor routes to correct adapter
def start_connection(port) do
  adapter = get_adapter_for_protocol(port.protocol)
  opts = build_protocol_specific_opts(port)
  adapter.start_link(opts)
end
```

**Example Multi-Protocol Setup:**
- RS485 Modbus RTU for legacy PLCs (fans, pumps)
- Modbus TCP for new Ethernet-connected PLCs
- GPIO for simple relays and lights
- HTTP REST for WiFi temperature sensors
- All managed by the same DeviceManager, all equipment controllers unchanged

#### Impact of Protocol Changes

**Zero Impact (90% of codebase):**
- Equipment controllers (fan.ex, pump.ex, light.ex, etc.)
- Automation layer (environment control, schedulers, interlocks)
- Logging system (EquipmentLogger, PeriodicLogger, DailySummaryTask)
- UI layer (LiveView components, dashboard)
- Business logic (state machines, error detection)

**Changes Required (hardware layer only):**
- Port configuration and schema updates
- PortSupervisor protocol routing logic
- Protocol-specific adapter implementation
- Admin UI for protocol selection

#### Recommended Protocol Priorities

Based on poultry farm use case and implementation effort:

1. **Modbus TCP** (Highest Priority)
   - Effort: 1 day
   - Benefit: Modern PLCs, faster, easier wiring

2. **GPIO** (Simple Devices)
   - Effort: 1 day
   - Benefit: Direct Pi control, zero cost, instant response

3. **HTTP/REST** (IoT Integration)
   - Effort: 2 days
   - Benefit: WiFi sensors, vendor integration, modern devices

4. **OPC UA** (Enterprise PLCs)
   - Effort: 5 days
   - Benefit: Industry standard, secure, future-proof

### Logging System Architecture

PouCon has a comprehensive logging system designed for embedded deployment with SD card write optimization:

**Components:**
1. **EquipmentLogger** - API for logging equipment events (start, stop, error)
2. **PeriodicLogger** - Takes sensor snapshots every 30 minutes
3. **DailySummaryTask** - Generates daily summaries at midnight
4. **CleanupTask** - Deletes old data daily at 3 AM, runs VACUUM on Sundays

**Database Tables:**
- `equipment_events` - All state changes, commands, errors (30-day retention)
- `sensor_snapshots` - Periodic temperature/humidity readings (30-day retention)
- `daily_summaries` - Aggregated daily statistics (365-day retention)

**Logging Integration Pattern:**

All equipment controllers follow a 4-location integration pattern (see `LOGGING_INTEGRATION_GUIDE.md`):
1. Interlock blocks (when safety rules prevent operation)
2. State changes (commanded vs actual state sync)
3. Command failures (Modbus write errors)
4. Error transitions (timeout, invalid data, hardware mismatch)

**Key Fields:**
- `mode`: "auto" or "manual" - indicates whether automation or user triggered the event
- `triggered_by`: "user", "auto_control", "schedule", "interlock", "system"
- `metadata`: JSON field for context (temperature, humidity, schedule ID, actions)

**Performance:**
- All writes are async via `Task.Supervisor` to prevent blocking equipment operations
- Estimated 105 KB/day with 43 equipment items
- Safe for SD card deployment with automatic cleanup

**System Startup Logging:**

The system logs a "startup" event on every application start (via `EquipmentLogger.log_system_startup/0`).
This enables power failure detection by comparing timestamps:

- **Equipment name**: "SYSTEM" (pseudo-equipment for system-level events)
- **Event type**: "startup"
- **How to detect outages**: Query events and look for gaps between timestamps. If the last event before startup was 4 hours ago, the system was offline for 4 hours.

Example query to find system restarts:
```elixir
EquipmentLogger.query_events(equipment_name: "SYSTEM", event_type: "startup")
```

## Domain Directory Structure

The codebase follows domain-driven organization:

```
lib/pou_con/
├── auth/              # Authentication, authorization, user management
├── automation/        # Automated control systems
│   ├── alarm/             # Condition-based alarm system with siren control
│   ├── egg_collection/    # Schedule-based egg collection
│   ├── environment/       # Temperature/humidity auto-control
│   ├── feeding/           # Feeding schedules + FeedIn trigger
│   ├── interlock/         # Safety chain enforcement
│   └── lighting/          # Light scheduling
├── equipment/         # Equipment definitions and controllers
│   ├── controllers/       # GenServer controllers (fan, pump, etc.)
│   └── schemas/           # Equipment, Device database schemas
├── hardware/          # Hardware communication layer
│   ├── modbus/            # Modbus adapters (real/simulated)
│   └── ports/             # Serial/TCP port management
├── logging/           # Event logging and reporting system
│   └── schemas/           # Event, Snapshot, Summary schemas
└── schema/            # Shared Ecto schemas

lib/pou_con_web/
├── components/        # Reusable LiveView components
│   ├── equipment/         # Equipment-specific UI components
│   ├── layouts/           # Page layouts
│   └── summaries/         # Report summary components
└── live/              # LiveView pages
    ├── admin/             # Port/device/equipment configuration
    ├── auth/              # Login, settings
    ├── dashboard/         # Main equipment monitoring
    ├── reports/           # Event logs, snapshots, summaries
    └── [domain]/          # Domain-specific pages (feeding, lighting, etc.)

test/                  # Mirror of lib/ structure
└── pou_con/
    ├── automation/
    ├── equipment/
    ├── hardware/
    └── logging/
```

## Key Workflows

### Adding New Equipment Type

1. Create controller module in `lib/pou_con/equipment/controllers/new_type.ex`
2. Implement auto/manual mode state machine
3. Add interlock checking via `InterlockHelper`
4. Integrate logging (4 locations: interlock, state change, command failure, errors)
5. Register controller in `EquipmentLoader.load_and_start_controllers/0`
6. Create LiveView component in `lib/pou_con_web/components/equipment/`
7. Add route and page in `lib/pou_con_web/live/`
8. Write tests mirroring the production file structure in `test/`

### Integrating Logging into Controllers

Follow the pattern in `LOGGING_INTEGRATION_GUIDE.md`:

1. Add alias: `alias PouCon.Logging.EquipmentLogger`
2. Log interlock blocks with "interlock" triggered_by
3. Log state changes in `sync_coil` with mode ("auto" or "manual")
4. Log command failures with "command_failed" error type
5. Log error transitions with appropriate error types

For auto-control and schedulers, use metadata to include context:
- Auto-control: Include temperature/humidity readings
- Schedulers: Include schedule ID and time information

### Device Configuration Hierarchy

Equipment → Device Tree → Devices → Ports

1. **Port**: Serial port or TCP connection (e.g., `/dev/ttyUSB0`, `192.168.1.100:502`)
2. **Device**: Modbus slave at specific address with register mappings
3. **Device Tree**: JSON structure defining equipment's I/O components
4. **Equipment**: High-level entity (fan_1, pump_2) with type and title

Example device tree:
```json
{
  "on_off_coil": "relay_1",
  "running_input": "di_1",
  "limit_switches": ["di_front_limit", "di_back_limit"],
  "sensors": ["temp_hum_1"]
}
```

The `DeviceTreeParser` converts this into controller options.

### Testing with Simulation Mode

1. Start server with `SIMULATE_DEVICES=1 iex -S mix phx.server`
2. Navigate to `/admin/simulation` in the browser
3. Create virtual digital states to simulate sensors/limit switches
4. Test equipment behavior without physical hardware
5. The SimulatedAdapter maintains an in-memory device state table

Tests automatically use SimulatedAdapter via `test/test_helper.exs`.

## Important Patterns and Conventions

### Controller State Synchronization

Controllers use a "commanded vs actual" pattern:
- `commanded_on`: What the system thinks the equipment should be
- `actual_on`: What the hardware reports it is
- When they differ, controller attempts to sync via Modbus commands
- Repeated failures trigger error state

### Error Detection

Controllers detect these error conditions:
- `:timeout` - No data received from hardware for 3 poll cycles
- `:command_failed` - Modbus write command failed
- `:on_but_not_running` - Commanded ON but hardware reports not running
- `:off_but_running` - Commanded OFF but hardware reports still running
- `:invalid_data` - Sensor readings out of valid range

### Interlock System

The `InterlockController` enforces safety chains defined in database:
- Example: "pump_1 cannot start if fan_1 is not running"
- Controllers check `InterlockHelper.check_can_start(name)` before executing
- Blocked attempts are logged with "interlock" triggered_by

### Alarm System

The `AlarmController` triggers sirens based on configurable conditions:
- **Logic modes**: "any" (OR) or "all" (AND) for condition grouping
- **Auto-clear**: Configurable per alarm (auto-clear vs manual acknowledge)
- **Condition types**: Sensor thresholds (above/below) and equipment states (off, not_running, error)
- **Multiple sirens**: Each alarm rule can target a specific siren
- Admin UI at `/admin/alarm` for rule configuration

Database tables:
- `alarm_rules` - Groups conditions that trigger a siren
- `alarm_conditions` - Individual conditions within a rule

### Fail-Safe Siren Wiring (Power Failure Protection)

For critical safety alarms that must sound during power failure, use **Normally Closed (NC) relay wiring** with a battery-powered siren. This is a hardware-based fail-safe - when power fails, the software cannot help.

**How It Works:**
```
NORMAL OPERATION (Power OK, No Alarm):
  Relay coil ENERGIZED → NC contact OPEN → Siren OFF

ALARM ACTIVE (Software triggers alarm):
  Relay coil DE-ENERGIZED → NC contact CLOSED → Siren ON (battery power)

POWER FAILURE:
  Relay coil DE-ENERGIZED → NC contact CLOSED → Siren ON (battery power)
```

**Wiring Diagram:**
```
24V Power ──── [Relay Coil] ──── Digital Output (Waveshare)
                    │
              [NC Contact]
                    │
Battery (+) ───────●─────────── Siren (+)
                                    │
Battery (-) ──────────────────── Siren (-)
```

**Software Configuration:**
```yaml
# Power-fail siren with NC (fail-safe) wiring
name: power_fail_siren
type: siren
on_off_coil: WS-11-O-08
auto_manual: VT-SIREN-MODE
inverted: true   # Coil ON = Siren OFF, Coil OFF = Siren ON
```

With `inverted: true`:
- `turn_on()` → coil OFF → NC closes → siren sounds
- `turn_off()` → coil ON → NC opens → siren silent
- Power failure → coil OFF → NC closes → **siren sounds automatically**

**Multiple Alarm Sources:** Wire additional NC contacts in parallel to trigger the same siren:
```
Battery ──┬── [NC: Power-fail relay] ──┬── Siren
          ├── [NC: High-temp alarm]  ──┤
          └── [NC: Critical fault]  ───┘
```

**Important Considerations:**
- Use dedicated relay output for power-fail siren
- Size battery for required siren duration (30 min - 2 hours typical)
- Consider physical silence button for acknowledged outages
- Test fail-safe behavior periodically by disconnecting power

### Auto/Manual Mode

Most controllers support two modes:
- **Manual**: User controls via UI, automation disabled
- **Auto**: Schedulers and auto-control can operate equipment

Mode is stored in controller state and affects logging (logged as "auto" or "manual" mode).

**Auto-Off on Mode Switch**: When switching from MANUAL to AUTO mode, equipment is automatically turned off (`commanded_on: false`). This is a safety feature that:
1. Gives automation a "clean slate" to control equipment based on its logic
2. Prevents unexpected behavior from equipment running in an unknown state
3. Ensures automation controllers (EnvironmentController, Schedulers) start from a predictable state

This behavior is implemented in all controllable equipment: Fan, Pump, Light, Siren, Egg, FeedIn, and BinaryController-based equipment.

### PubSub Topics

The system uses these PubSub topics:
- `"device_data"` - DeviceManager broadcasts device state changes
- `"equipment_status"` - Controllers broadcast status updates
- `"environment_config"` - EnvironmentController config changes

LiveView mounts subscribe to these topics for real-time updates.

## Database Considerations

- **SQLite** is used for embedded deployment (Raspberry Pi)
- Database path controlled by `DATABASE_PATH` env var (default: `pou_con_dev.db`)
- Migrations run automatically on app start (see `Application.start/2`)
- Write optimization for SD cards: async logging, batched inserts, VACUUM on Sundays
- Connection pooling disabled (`pool_size: 1`) due to SQLite's single-writer limitation

## Testing Philosophy

- Tests mirror production directory structure under `test/`
- Use `Mox` for mocking DeviceManagerBehaviour in controller tests
- Each controller has dedicated test file (e.g., `fan_test.exs`)
- Tests verify: state machines, error handling, interlock enforcement, logging calls
- Automation modules have tests for scheduling logic and trigger conditions
- Hardware layer has tests for Modbus communication and port management

## Configuration Files

- `config/config.exs` - Base configuration, Modbus adapter selection
- `config/dev.exs` - Development settings (debug logging, live reload)
- `config/test.exs` - Test settings (sandbox mode, simulated adapter)
- `config/prod.exs` - Production settings (info logging, error tracking)
- `config/runtime.exs` - Runtime environment variables

## LiveView Structure

All LiveView modules follow Phoenix conventions:
- `mount/3` - Initialize state, subscribe to PubSub
- `handle_params/3` - Handle URL parameters
- `handle_event/3` - Handle user interactions
- `handle_info/2` - Handle PubSub broadcasts

LiveView pages use function components from `lib/pou_con_web/components/` for reusability.

## Security and Safety

- **Hardware Safety**: Interlocks enforce safety chains at software level
- **Authentication**: Required for all routes except login (enforced by plugs)
- **Role-based Access**: Admin role for configuration, User role for operation
- **Modbus Security**: No authentication (typical for industrial LANs behind firewalls)
- **Session Management**: Phoenix session-based auth with bcrypt password hashing

## Deployment Notes

- Designed for Raspberry Pi or similar embedded Linux systems
- Expects serial ports at `/dev/ttyUSB*` for Modbus RTU
- Supports Modbus TCP for network-connected devices
- Phoenix runs on port 4000 (configurable via `PORT` env var)
- Use `MIX_ENV=prod mix release` for production builds
- Database and logs persist across restarts
- **System Time Management**: Run `sudo bash setup_sudo.sh` once during deployment to enable web-based time setting (required for RTC battery failure recovery)
- I am using https://www.waveshare.com/wiki/Modbus_RTU_IO_8CH as my digital IO module, https://my.cytron.io/c-sensors-connectivities/p-industrial-grade-rs485-temperature-humidity-sensor as my sensor, the electrical panel with relays, contactors, poultry house limit switch, motors and power supply are provided by contractor. My job is to read data from field and send on/off signal to the relay using my Digital IO module.
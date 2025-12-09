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

- **Production**: `PouCon.Hardware.Modbus.RealAdapter` - actual Modbus RTU/TCP
- **Development/Test**: `PouCon.Hardware.Modbus.SimulatedAdapter` - in-memory simulation

Adapter selection is controlled by `SIMULATE_DEVICES=1` environment variable (see `config/config.exs`).

The DeviceManager polls devices every 1 second and maintains an ETS cache (`:device_cache`) that controllers query for current state.

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

## Domain Directory Structure

The codebase follows domain-driven organization:

```
lib/pou_con/
├── auth/              # Authentication, authorization, user management
├── automation/        # Automated control systems
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

### Auto/Manual Mode

Most controllers support two modes:
- **Manual**: User controls via UI, automation disabled
- **Auto**: Schedulers and auto-control can operate equipment

Mode is stored in controller state and affects logging (logged as "auto" or "manual" mode).

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

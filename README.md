# PouCon

**PouCon** is an industrial automation and control system for poultry farms, built with Elixir and Phoenix LiveView. It provides real-time hardware monitoring and control for poultry farm equipment through Modbus RTU/TCP and Siemens S7 protocol communication.

## Overview

PouCon manages the complete lifecycle of poultry farm operations, from environmental climate control to automated feeding, egg collection, and waste management. The system communicates with industrial controllers via Modbus RTU/TCP and Siemens S7 protocols, and provides operators with a real-time web-based interface for monitoring and control.

## Key Features

### Hardware Communication & Control
- **Multi-Protocol Support**: Modbus RTU/TCP and Siemens S7 (S7-300/400, S7-1200/1500, ET200SP)
- **Multi-Port Management**: Support for multiple serial/TCP ports connecting different hardware controllers
- **Real-time Polling**: 1-second polling with efficient ETS caching for device state synchronization
- **Simulation Mode**: Complete hardware simulation for development and testing without physical devices
- **Raw Data Viewer**: Direct inspection and writing of Modbus/S7 register values for debugging

### Equipment Management
PouCon controls and monitors various types of poultry farm equipment:

- **Climate Control**
  - Automatic fan control with sequencing and NC fan support
  - Water pump management for cooling systems
  - Temperature and humidity monitoring with configurable thresholds
  - CO2 and NH3 gas sensor monitoring
  - Calculated average sensors from multiple sensor groups
  - Hysteresis and stagger delay to prevent rapid cycling and power surges

- **Poultry Operations**
  - Automated feeding systems with position control and limit switches
  - Egg collection automation with scheduling
  - Multi-position feed input control
  - Flock management with production tracking (eggs, mortality, feed usage)
  - Operations task management with recurring schedules

- **Waste Management**
  - Horizontal dung removal systems
  - Vertical dung exit control
  - Automated cleaning sequences

- **Lighting**
  - Automated light scheduling
  - Manual override capabilities

- **Alarm & Safety Systems**
  - Configurable alarm rules with sensor thresholds and equipment state conditions
  - AND/OR logic for condition grouping
  - Multiple siren support with auto-clear or manual acknowledge options
  - Fail-safe NC relay wiring for power failure protection
  - Interlock system for equipment safety chains
  - Critical alert banners with screen keep-awake

- **Metering & Monitoring**
  - Water flow meters with consumption tracking
  - Power meters (voltage, current, power factor, energy)
  - Power supply status indicators

### Environmental Control
- Automatic temperature and humidity-based climate control
- Up to 10 configurable temperature steps with equipment assignments
- Intelligent fan and pump sequencing with stagger delay
- Real-time sensor monitoring and equipment response
- Failsafe validator for manual fan configuration

### User Interface
- **Real-time Dashboard**: Live equipment status and environmental monitoring
- **Environment Control Panel**: Configure climate parameters and thresholds
- **Device Management**: Admin interface for configuring ports, data points, and equipment
- **Scheduling**: Light, feeding, and egg collection schedule management
- **Flock Management**: Production tracking with daily yield recording
- **Operations Tasks**: Recurring maintenance task tracking
- **Reports**: Equipment event logs, sensor data history, and error tracking
- **Backup & Restore**: Full database backup with selective restore
- **On-Screen Keyboard**: Built-in touch keyboard for kiosk deployments
- **Screen Saver**: Configurable screen timeout with automatic backlight control
- **System Management**: Time, reboot, and system diagnostics from the web interface
- **Simulation Interface**: Test equipment behavior without hardware
- **Role-based Access**: Admin and User roles with authentication

## Technology Stack

- **Language**: Elixir 1.19+ / Erlang OTP 28+
- **Web Framework**: Phoenix 1.8
- **Real-time UI**: Phoenix LiveView 1.1
- **Database**: SQLite with Ecto ORM
- **Hardware Protocols**: Modbus RTU/TCP (modbux), Siemens S7 (snapex7)
- **Serial Communication**: circuits_uart
- **HTTP Server**: Bandit
- **Styling**: Tailwind CSS
- **Authentication**: bcrypt_elixir
- **Testing**: ExUnit with Mox for mocking

## Architecture

### Core Components

- **DataPointManager** (GenServer): Central polling engine that handles Modbus/S7 I/O, device state caching via ETS, and hardware communication
- **Equipment Controllers**: Individual GenServers for each equipment instance (fan_1, pump_2, etc.) with auto/manual mode state machines
- **PortSupervisor**: Manages Modbus RTU/TCP and S7 connection lifecycle
- **EnvironmentController**: Monitors environmental sensors and orchestrates climate control equipment
- **Automation Services**: Light, feeding, and egg collection schedulers; alarm controller; interlock enforcement
- **Phoenix LiveView**: Real-time UI with WebSocket communication and PubSub updates
- **Hardware Adapters**: Pluggable architecture supporting real hardware and simulated devices for both Modbus and S7

### Data Flow
1. DataPointManager polls hardware devices at 1-second intervals
2. Device state cached in ETS (`:device_cache`) for fast access
3. Equipment controllers subscribe to state changes via PubSub
4. Controllers execute business logic (auto/manual modes, sequencing, error detection)
5. LiveView components receive real-time updates via PubSub
6. User actions trigger commands through controllers to DataPointManager
7. DataPointManager writes to hardware devices and updates cache

## Getting Started

### Prerequisites

- Elixir 1.19 or later
- Erlang/OTP 28 or later
- Node.js (for asset compilation)

### Installation

1. Clone the repository
   ```bash
   git clone <repository-url>
   cd pou_con
   ```

2. Install dependencies and setup database
   ```bash
   mix setup
   ```

3. Start the Phoenix server with device simulation
   ```bash
   SIMULATE_DEVICES=1 mix phx.server
   ```

   Or start inside IEx for interactive development:
   ```bash
   SIMULATE_DEVICES=1 iex -S mix phx.server
   ```

4. Visit [`http://localhost:4000`](http://localhost:4000) in your browser

### First-Time Setup

On first run, you'll be guided through a setup wizard to:
1. Create an admin account
2. Configure your first house/facility

## Usage

### Admin Tasks

- **Port Configuration**: Add serial ports (Modbus RTU) or TCP connections (Modbus TCP, Siemens S7)
- **Data Point Configuration**: Define data point mappings with read/write functions for hardware I/O
- **Equipment Setup**: Create equipment definitions with data point trees (inputs, outputs, sensors)
- **Interlock Rules**: Configure safety chains between equipment
- **Alarm Rules**: Define conditions that trigger sirens
- **Schedules**: Configure lighting, feeding, and egg collection schedules
- **Flock Management**: Track flocks, record daily production data
- **Task Templates**: Define recurring operations tasks

### Operator Tasks

- **Dashboard Monitoring**: View real-time status of all equipment
- **Equipment Pages**: Detailed view of fans, pumps, sensors, lighting, feeding, etc.
- **Environment Control**: Configure temperature/humidity thresholds and enable/disable auto mode
- **Operations Tasks**: Complete recurring maintenance tasks
- **Flock Logs**: Record daily eggs, mortality, and feed usage
- **Reports**: View equipment events, sensor data, and error history

### Monitoring Pages (Public Access)

These pages are accessible without login:
- Dashboard (`/`), Temperature (`/temp`), Humidity (`/hum`), CO2 (`/co2`), NH3 (`/nh3`)
- Average Sensors (`/averages`), Fans (`/fans`), Pumps (`/pumps`), Lighting (`/lighting`)
- Sirens (`/sirens`), Egg Collection (`/egg_collection`), Feeding (`/feed`), Dung (`/dung`)
- Power Indicators (`/power_indicators`), Water Meters (`/water_meters`), Power Meters (`/power_meters`)
- Reports (`/reports`), Help/User Guide (`/help`)

## Development

### Running Tests

```bash
mix test
```

### Running with Coverage

```bash
mix test --cover
```

### Code Quality

```bash
# Format code
mix format

# Compile with warnings as errors
mix compile --warnings-as-errors

# Pre-commit checks
mix precommit
```

### Using Simulation Mode

The system includes a complete simulation mode for development and testing:

1. Start with `SIMULATE_DEVICES=1 mix phx.server`
2. Navigate to `/admin/simulation` in the web interface
3. Configure virtual digital states to simulate sensors and limit switches
4. Test equipment controllers without physical hardware

### Adding New Equipment Types

1. Create a new controller module in `lib/pou_con/equipment/controllers/`
2. Implement the GenServer with auto/manual mode state machine
3. Add interlock checking via `InterlockHelper`
4. Integrate logging at 4 critical points (interlock, state change, command failure, errors)
5. Register controller in `EquipmentLoader.load_and_start_controllers/0`
6. Create LiveView component in `lib/pou_con_web/components/equipment/`
7. Add route and page in `lib/pou_con_web/live/`
8. Write tests mirroring the production file structure in `test/`

## Production Deployment

### Building a Release

```bash
MIX_ENV=prod mix release
```

### Cross-Compilation for Raspberry Pi

PouCon uses Docker buildx with QEMU emulation to cross-compile for ARM64:

```bash
# One-time Docker setup
./scripts/setup_docker_arm.sh

# Build ARM release
./scripts/build_arm.sh

# Create deployment package (includes offline dependencies)
./scripts/create_deployment_package.sh
```

### Deploying to Raspberry Pi

```bash
# Copy package to USB drive
cp pou_con_deployment_*.tar.gz /media/usb-drive/

# At Raspberry Pi (no internet required)
tar -xzf pou_con_deployment_*.tar.gz
cd deployment_package_*/
sudo ./deploy.sh
```

The `deploy.sh` script handles everything: dependencies, SSL certificates, database setup, and service configuration.

### Updating an Existing Installation

```bash
# At Raspberry Pi with USB drive
cd deployment_package_*/
sudo ./update.sh
```

The update script backs up the database, updates application files, runs migrations, and restarts the service.

### Environment Variables

- `PORT`: HTTP server port (default: 4000)
- `DATABASE_PATH`: Path to SQLite database file
- `SECRET_KEY_BASE`: Phoenix secret key (generate with `mix phx.gen.secret`)
- `PHX_HOST`: Production hostname/domain
- `SIMULATE_DEVICES`: Set to `1` for simulation mode

### Hardware Setup

1. Connect Modbus RTU devices to serial ports (e.g., `/dev/ttyUSB0`, `/dev/ttyUSB1`)
2. Or configure Modbus TCP / Siemens S7 connections with IP addresses
3. Configure port settings in the admin interface
4. Add data points with register/memory mappings
5. Map equipment to data points via data point trees

### Supported Hardware

- **Digital I/O**: Waveshare Modbus RTU IO 8CH (RS485)
- **Sensors**: Cytron Industrial Grade RS485 Temperature/Humidity Sensor
- **PLCs**: Siemens S7-300/400, S7-1200/1500, ET200SP
- **Displays**: reTerminal DM, Official 7" Pi Display, DSI displays
- **Controllers**: Raspberry Pi 3B+/4/5/CM4, RevPi Connect 5

For detailed deployment instructions, see:
- `docs/DEPLOYMENT_MANUAL.md` - Complete deployment guide
- `docs/REVPI_DEPLOYMENT_GUIDE.md` - RevPi Connect 5 specific guide
- `docs/USER_MANUAL.md` - Operator user manual (also accessible at `/help` in the web interface)

For more information on Phoenix deployment, see the [official deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## License

[Add your license here]

## Contributing

[Add contribution guidelines here]

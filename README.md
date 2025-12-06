# PouCon

**PouCon** is an industrial automation and control system for poultry farms, built with Elixir and Phoenix LiveView. It provides real-time hardware monitoring and control for poultry farm equipment through Modbus protocol communication.

## Overview

PouCon manages the complete lifecycle of poultry farm operations, from environmental climate control to automated feeding, egg collection, and waste management. The system communicates with industrial controllers via Modbus RTU/TCP and provides operators with a real-time web-based interface for monitoring and control.

## Key Features

### Hardware Communication & Control
- **Modbus Protocol Support**: Full Modbus RTU/TCP implementation for industrial device communication
- **Multi-Port Management**: Support for multiple serial/device ports to connect different hardware controllers
- **Real-time Polling**: Efficient caching and polling mechanism for device state synchronization
- **Simulation Mode**: Complete hardware simulation for testing without physical devices

### Equipment Management
PouCon controls and monitors various types of poultry farm equipment:

- **Climate Control**
  - Automatic fan control with sequencing and NC fan support
  - Water pump management for cooling systems
  - Temperature and humidity monitoring with configurable thresholds
  - Hysteresis support to prevent rapid on/off cycling

- **Poultry Operations**
  - Automated feeding systems with position control and limit switches
  - Egg collection automation
  - Multi-position feed input control
  - Poultry exit device management

- **Waste Management**
  - Horizontal dung removal systems
  - Vertical dung exit control
  - Automated cleaning sequences

- **Lighting**
  - Automated light scheduling
  - Manual override capabilities

### Environmental Control
- Automatic temperature and humidity-based climate control
- Configurable min/max thresholds for temperature and humidity
- Intelligent fan and pump sequencing to manage power consumption
- Real-time sensor monitoring and equipment response

### User Interface
- **Real-time Dashboard**: Live equipment status and environmental monitoring
- **Environment Control Panel**: Configure climate parameters and thresholds
- **Device Management**: Admin interface for configuring ports and devices
- **Equipment Management**: Define and manage equipment configurations
- **Simulation Interface**: Test equipment behavior without hardware
- **Role-based Access**: Admin and User roles with authentication

## Technology Stack

- **Language**: Elixir 1.15+
- **Web Framework**: Phoenix 1.8.1
- **Real-time UI**: Phoenix LiveView 1.1.0
- **Database**: SQLite with Ecto ORM
- **Hardware Protocol**: Modbus RTU/TCP (via modbux library)
- **Serial Communication**: circuits_uart
- **Styling**: Tailwind CSS
- **Authentication**: bcrypt_elixir
- **Task Scheduling**: Quantum
- **Testing**: ExUnit with Mox for mocking

## Architecture

### Core Components

- **DeviceManager** (GenServer): Central polling engine that handles Modbus I/O, device state caching, and communication with hardware
- **Device Controllers**: Individual GenServers for each equipment type (FanController, PumpController, FeedingController, etc.)
- **PortSupervisor**: Manages Modbus connection lifecycle
- **EnvironmentController**: Monitors environmental sensors and orchestrates climate control equipment
- **Phoenix LiveView**: Real-time UI with WebSocket communication
- **Modbus Adapters**: Pluggable architecture supporting both real hardware and simulated devices

### Data Flow
1. DeviceManager polls Modbus devices at configured intervals
2. Device state cached in-memory for performance
3. Device Controllers subscribe to state changes
4. Controllers execute business logic (auto/manual modes, sequencing, etc.)
5. LiveView components receive real-time updates via PubSub
6. User actions trigger commands through controllers to DeviceManager
7. DeviceManager writes to Modbus devices and updates cache

## Getting Started

### Prerequisites

- Elixir 1.15 or later
- Erlang/OTP 26 or later
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

3. Start the Phoenix server
   ```bash
   mix phx.server
   ```

   Or start inside IEx for interactive development:
   ```bash
   iex -S mix phx.server
   ```

4. Visit [`http://localhost:4000`](http://localhost:4000) in your browser

### First-Time Setup

On first run, you'll be guided through a setup wizard to:
1. Create an admin account
2. Configure your first house/facility

## Usage

### Admin Tasks

- **Port Configuration**: Add serial ports or TCP connections for Modbus communication
- **Device Configuration**: Define Modbus devices with their addresses and register mappings
- **Equipment Setup**: Create equipment definitions with device trees (inputs, outputs, sensors)

### Operator Tasks

- **Dashboard Monitoring**: View real-time status of all equipment
- **Environment Control**: Configure temperature/humidity thresholds and enable/disable auto mode
- **Manual Control**: Override automatic control for any equipment
- **Simulation**: Test equipment behavior using the simulation interface

## Development

### Running Tests

```bash
mix test
```

### Running with Coverage

```bash
mix test --cover
```

### Code Formatting

```bash
mix format
```

### Using Simulation Mode

The system includes a complete simulation mode for development and testing:

1. Navigate to the Simulation page in the web interface
2. Configure virtual digital states to simulate sensors and limit switches
3. Test equipment controllers without physical hardware

### Adding New Equipment Types

1. Create a new controller module in `lib/pou_con/device_controllers/`
2. Implement the controller behavior (auto/manual modes, state machine logic)
3. Add LiveView component in `lib/pou_con_web/components/`
4. Update the equipment loader and dashboard

## Production Deployment

### Building a Release

```bash
MIX_ENV=prod mix release
```

### Running in Production

```bash
PORT=4000 \
MIX_ENV=prod \
DATABASE_PATH=./pou_con_prod.db \
SECRET_KEY_BASE=<your-secret-key> \
PHX_HOST=<your-domain> \
mix phx.server
```

### Environment Variables

- `PORT`: HTTP server port (default: 4000)
- `DATABASE_PATH`: Path to SQLite database file
- `SECRET_KEY_BASE`: Phoenix secret key (generate with `mix phx.gen.secret`)
- `PHX_HOST`: Production hostname/domain

### Hardware Setup

1. Connect Modbus RTU devices to serial ports (e.g., `/dev/ttyUSB0`, `/dev/ttyUSB1`)
2. Or configure Modbus TCP connections with IP addresses and ports
3. Configure port settings in the admin interface (baud rate, data bits, stop bits, parity)
4. Add devices with their Modbus slave addresses
5. Map equipment to device registers

For more information on Phoenix deployment, see the [official deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## License

[Add your license here]

## Contributing

[Add contribution guidelines here]

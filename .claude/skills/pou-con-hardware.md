# PouCon Hardware Integration Skill

## DataPointManager Architecture

`DataPointManager` is the central I/O hub — a GenServer that:
1. Manages an ETS cache (`:data_point_cache`) for fast reads
2. Routes commands to the correct protocol adapter (Modbus RTU/TCP, S7, Virtual)
3. Applies analog conversions (`scale_factor`/`offset`) and digital NC inversion
4. Is protocol-agnostic — controllers never know what protocol is used

```
Controller → DataPointManager → PortSupervisor → Protocol Adapter → Hardware
                │                                        │
                └── ETS Cache (read_direct)              └── Modbus RTU/TCP, S7, Virtual
```

## DataPointManagerBehaviour Callbacks

```elixir
@callback read_direct(data_point_name :: String.t()) ::
  {:ok, %{state: integer()}} |          # Digital: state is 0 or 1
  {:ok, %{value: float()}} |            # Analog: converted value
  {:error, :timeout | :not_found | term()}

@callback command(data_point_name :: String.t(), action :: atom(), params :: map()) ::
  {:ok, :success} |
  {:error, term()}
```

### Usage in Controllers

```elixir
# Read a data point (returns logical value — inversion already applied)
{:ok, %{state: coil_state}} = @data_point_manager.read_direct("WS-11-O-01")
actual_on = coil_state == 1  # Always logical: 1=ON, 0=OFF

# Write a command (logical value — DPM handles NC inversion)
@data_point_manager.command("WS-11-O-01", :set_state, %{state: 1})  # Turn ON
@data_point_manager.command("WS-11-O-01", :set_state, %{state: 0})  # Turn OFF
```

## Data Point Types

| Type | io_function | Protocol Command | Description |
|------|-------------|-----------------|-------------|
| DO (Digital Output) | `:fc` | Force Coil | Relay control (on/off) |
| DI (Digital Input) | `:rc` | Read Coil | Sensor, feedback, switch |
| AI (Analog Input) | `:rhr` | Read Holding Register | Temperature, humidity, etc. |
| AO (Analog Output) | `:phr` | Preset Holding Register | Setpoint writing |
| VDI (Virtual Digital Input) | N/A | In-memory | Software-controlled switch |

## Data Point Schema Fields

```elixir
%DataPoint{
  name: "WS-11-O-01",          # Unique identifier
  type: "DO",                    # DO, DI, AI, AO
  description: "Fan 1 relay",   # Human-readable
  port_id: 1,                   # FK to Port (hardware connection)
  device_address: 11,           # Modbus slave ID or S7 byte address
  data_address: 1,              # Register/coil number
  io_function: "fc",            # Modbus function code atom
  scale_factor: 1.0,            # Analog: (raw * scale_factor) + offset
  offset: 0.0,                  # Analog: added after scaling
  inverted: false,              # Digital: NC wiring (true = flip 0↔1)
  log_interval: nil,            # Seconds between logged samples (nil = don't log)
  color_zones: nil              # JSON: threshold-based UI coloring
}
```

## Protocol Routing

DataPointManager determines protocol from the Port record:

| Port Type | Adapter | Transport |
|-----------|---------|-----------|
| `"modbus_rtu"` | `Modbus.RtuAdapter` | RS485 serial via `circuits_uart` |
| `"modbus_tcp"` | `Modbus.TcpAdapter` | TCP/IP socket |
| `"s7"` | `S7.Adapter` | TCP/IP to Siemens PLC |
| `"virtual"` | In-memory GenServer | No hardware |

## Analog Conversion Formula

```
displayed_value = (raw_register_value * scale_factor) + offset
```

Example: Temperature sensor returns raw `245`, with `scale_factor: 0.1`, `offset: 0.0`:
```
displayed_value = 245 * 0.1 + 0.0 = 24.5°C
```

## NC Inversion Transparency

For normally-closed (NC) relay wiring where coil OFF = equipment ON:

```
Controller sends:  command("relay", :set_state, %{state: 1})  ← "turn ON"
DPM sees inverted: true → writes physical 0 to coil
Result: NC contact closes → equipment powered ON ✓

Controller reads:  read_direct("relay")
Hardware returns:  physical coil = 0
DPM sees inverted: true → returns %{state: 1}
Controller sees:   actual_on = true ✓
```

**Controllers never know about inversion.** They always work in logical terms.

## Modbux API Reference

### RTU Master (single call)
```elixir
# Read coil (DI): {:rc, slave_id, address, count}
Modbux.Rtu.Master.request(pid, {:rc, 11, 1, 1})  # → {:ok, [0]} or {:ok, [1]}

# Read holding register (AI): {:rhr, slave_id, address, count}
Modbux.Rtu.Master.request(pid, {:rhr, 11, 1, 2})  # → {:ok, [high, low]}

# Force coil (DO): {:fc, slave_id, address, value}
Modbux.Rtu.Master.request(pid, {:fc, 11, 1, 1})  # → :ok

# Preset holding register (AO): {:phr, slave_id, address, value}
Modbux.Rtu.Master.request(pid, {:phr, 11, 1, 100})  # → :ok
```

### TCP Client (2-step)
```elixir
# Step 1: Send request
:ok = Modbux.Tcp.Client.request(pid, {:rc, 11, 1, 1})
# Step 2: Get confirmation
{:ok, [1]} = Modbux.Tcp.Client.confirmation(pid)
```

The `TcpAdapter` wraps this into a single `request/2` call with auto-reconnect.

### IEEE754 Float Helpers
```elixir
Modbux.IEEE754.from_2_regs(high, low, :be)  # Big-endian (default)
Modbux.IEEE754.to_2_regs(float_val, :be)    # Returns {high, low}
```

## Snapex7 API Reference (S7 Protocol)

```elixir
# Connect
Snapex7.Client.connect_to(pid, ip: "192.168.1.10", rack: 0, slot: 1)

# Read process inputs (%IB area)
{:ok, <<byte1, byte2>>} = Snapex7.Client.eb_read(pid, start: 0, amount: 2)

# Read process outputs (%QB area)
{:ok, <<byte1>>} = Snapex7.Client.ab_read(pid, start: 0, amount: 1)

# Write process outputs
:ok = Snapex7.Client.ab_write(pid, start: 0, data: <<0x01>>)

# Read/write data blocks
{:ok, data} = Snapex7.Client.db_read(pid, db_number: 1, start: 0, amount: 4)
:ok = Snapex7.Client.db_write(pid, db_number: 1, start: 0, data: <<value>>)

# Read/write markers (M area)
{:ok, data} = Snapex7.Client.mb_read(pid, start: 0, amount: 1)
:ok = Snapex7.Client.mb_write(pid, start: 0, data: <<0x01>>)
```

**S7 Adapter** wraps Snapex7 in a GenServer with:
- Auto-reconnect with exponential backoff (5s → 60s max)
- `safe_call/2` that catches `:port_timed_out` exits
- Connection state tracking (`:disconnected` | `:connecting` | `:connected`)

## DataPointTreeParser Format

Equipment `data_point_tree` is a JSON map parsed into controller opts:

```json
{
  "on_off_coil": "WS-11-O-01",
  "running_feedback": "WS-11-I-01",
  "auto_manual": "VT-200-15",
  "trip": "WS-11-I-02"
}
```

Parsed to keyword list: `[on_off_coil: "WS-11-O-01", running_feedback: "WS-11-I-01", ...]`

### Sensor Types
```json
{"value": "CYTRON-11-AI-01"}
```

### Feeding Equipment
```json
{
  "on_off_coil": "WS-13-O-01",
  "running_feedback": "WS-13-I-01",
  "front_limit": "WS-13-I-02",
  "back_limit": "WS-13-I-03",
  "auto_manual": "VT-300-01"
}
```

## Simulation Environment

### Starting Simulation Mode
```bash
SIMULATE_DEVICES=1 mix phx.server
# or with IEx:
SIMULATE_DEVICES=1 iex -S mix phx.server
```

### How It Works

`SIMULATE_DEVICES=1` swaps real adapters for in-memory simulations at compile time:

```elixir
# config/config.exs
if System.get_env("SIMULATE_DEVICES") == "1" do
  config :pou_con, :modbus_adapter, PouCon.Hardware.Modbus.SimulatedAdapter
  config :pou_con, :s7_adapter, PouCon.Hardware.S7.SimulatedAdapter
else
  config :pou_con, :modbus_adapter, PouCon.Hardware.Modbus.RtuAdapter
  config :pou_con, :s7_adapter, PouCon.Hardware.S7.Adapter
end
```

### Simulated Modbus Adapter
`SimulatedAdapter` is a GenServer that maintains in-memory state for:
- Coils (digital outputs), inputs (digital inputs), holding registers (analog)
- Realistic sensor simulation: CO2 (SenseCAP), NH3, temperature/humidity (Cytron)
- Water meter with cumulative flow + jitter
- Power meter (DELAB PQM-1000s) with 3-phase calculations
- Device offline simulation via `set_offline/2`

API:
```elixir
SimulatedAdapter.set_input(pid, {slave_id, channel}, value)   # Simulate DI
SimulatedAdapter.set_coil(pid, {slave_id, channel}, value)     # Simulate DO
SimulatedAdapter.set_register(pid, {slave_id, channel}, value) # Simulate AI
SimulatedAdapter.set_offline(pid, slave_id)                     # Simulate timeout
```

### Simulated S7 Adapter
`S7.SimulatedAdapter` is a GenServer with binary storage for:
- Process Inputs (EB, 512 bytes), Outputs (AB, 512 bytes)
- Data Blocks (DB, up to 1024 bytes per block), Markers (M, 512 bytes)

API:
```elixir
S7.SimulatedAdapter.set_input_bit(pid, byte, bit, value)    # %I0.0 etc.
S7.SimulatedAdapter.set_output_bit(pid, byte, bit, value)   # %Q0.0 etc.
S7.SimulatedAdapter.set_analog_input(pid, byte, int16_val)  # %IW0 etc.
S7.SimulatedAdapter.set_offline(pid, true)                   # Simulate disconnect
```

### Virtual Device Driver
For persistent virtual switches (e.g., auto/manual mode toggles):
- Backed by `virtual_digital_states` DB table (not in-memory)
- `VirtualDigitalState` schema: `{slave_id, channel, state}` (state: 0 or 1)
- Used by DataPointManager for "virtual" protocol ports

### Simulation Web UI
Navigate to `/admin/simulation` (only visible when `SIMULATE_DEVICES=1`):
- Lists all data points with equipment and key mapping
- Toggle digital I/O ON/OFF with buttons
- Set raw register values for analog sensors
- Simulate device offline state
- Connect/disconnect ports dynamically
- Search and filter by equipment, key, name, or value

### Test Environment
Tests use a separate mock (not SimulatedAdapter):
```elixir
# config/test.exs
config :pou_con, :data_point_manager, PouCon.DataPointManagerMock

# test/test_helper.exs
Mox.defmock(PouCon.DataPointManagerMock, for: PouCon.Hardware.DataPointManagerBehaviour)
```
This lets tests use `Mox.stub/3` and `Mox.expect/3` for precise control.

## Key Files

- `lib/pou_con/hardware/data_point_manager.ex` — Central I/O hub GenServer
- `lib/pou_con/hardware/data_point_manager_behaviour.ex` — Behaviour for mocking
- `lib/pou_con/hardware/port_supervisor.ex` — Manages protocol connections
- `lib/pou_con/equipment/schemas/data_point.ex` — DataPoint schema
- `lib/pou_con/hardware/data_point_tree_parser.ex` — JSON→keyword parser
- `lib/pou_con/hardware/modbus/rtu_adapter.ex` — Modbus RTU adapter
- `lib/pou_con/hardware/modbus/tcp_adapter.ex` — Modbus TCP adapter
- `lib/pou_con/hardware/s7/adapter.ex` — Siemens S7 adapter
- `lib/pou_con/hardware/modbus/simulated_adapter.ex` — Modbus simulation (dev)
- `lib/pou_con/hardware/s7/simulated_adapter.ex` — S7 simulation (dev)
- `lib/pou_con/hardware/devices/virtual.ex` — Virtual device driver (DB-backed)
- `lib/pou_con_web/live/simulation_live.ex` — Simulation web UI

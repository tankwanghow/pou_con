# PouCon Hardware Integration Skill

## DataPointManager Architecture

`DataPointManager` is the central I/O hub — a GenServer that:
1. Manages an ETS cache (`:data_point_cache`) for fast reads
2. Acts as a fast router: dispatches each non-virtual read/write to the per-port `PortWorker`
3. Applies analog conversions (`scale_factor`/`offset`) and digital NC inversion
4. Handles virtual (DB-backed) data points inline (bypassing PortWorker)
5. Is protocol-agnostic — controllers never know what protocol is used

```
Controller → DataPointManager → PortWorker (one per non-virtual port) → Protocol Adapter → Hardware
                │                     │
                │                     └── owns skipped_slaves + failure_counts per port,
                │                         serializes all I/O for that port
                └── ETS Cache (read_direct), virtual data points handled inline
```

**PortWorker isolation** (see `port_worker.ex`): every non-virtual port has a dedicated
`PortWorker` GenServer (supervised by `PortWorkerSupervisor`). DataPointManager stays a
thin router and no longer holds `skipped_slaves`/`failure_counts` — those live per-port in
the worker. `PortWorker.reset(port_path)` is called on `reload_port` and auto-reconnect.

API:
```elixir
PortWorker.read(port_path, data_point, conn_pid, protocol)
PortWorker.write(port_path, data_point, conn_pid, protocol_str, action, params)
PortWorker.reset(port_path)
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

The data point is **self-describing**: instead of a single `io_function`, it carries
`read_fn` / `write_fn` strings that name functions in the unified device modules
(`DigitalIO`, `AnalogIO`). These work across all protocols (RTU, TCP, RTU-over-TCP, S7).

| Type | read_fn | write_fn | Description |
|------|---------|----------|-------------|
| DO (Digital Output) | `read_digital_output` | `write_digital_output` | Relay control (on/off) |
| DI (Digital Input) | `read_digital_input` | (none) | Sensor, feedback, switch |
| AI (Analog Input) | `read_analog_input` | (none) | Temperature, humidity, etc. |
| AO (Analog Output) | `read_analog_output` | `write_analog_output` | Setpoint read/write |
| VDI/VDO (Virtual) | DB-backed | DB-backed | Software-controlled switch |

## Data Point Schema Fields

> Real fields — there is **no** `io_function`, `device_address`, `data_address`, `port_id`,
> or `log_interval` field. The port FK is `port_path` (string) → `ports.device_path`.

```elixir
%DataPoint{
  name: "relay_1",              # Unique identifier
  type: "DO",                    # DO, DI, AI, AO (VDI/VDO for virtual)
  description: "Fan 1 relay",   # Human-readable
  slave_id: 11,                 # Modbus slave ID (or S7 byte address)
  register: 1,                  # Register/coil number
  channel: 1,                   # Bit/channel within register (digital), or nil
  read_fn: "read_digital_output",  # Function name in DigitalIO/AnalogIO
  write_fn: "write_digital_output", # nil for read-only points
  scale_factor: 1.0,            # Analog: (raw * scale_factor) + offset
  offset: 0.0,                  # Analog: added after scaling
  unit: "°C",                   # Display unit
  value_type: "int16",          # Analog decode: int16/uint16/int32/uint32/float32
  byte_order: "high_low",       # 32-bit word order ("high_low" | "low_high")
  min_valid: -40.0,             # Validation range (optional)
  max_valid: 80.0,
  inverted: false,              # Digital: NC wiring (true = flip 0↔1)
  color_zones: nil,             # JSON: threshold-based UI coloring
  port_path: "/dev/ttyUSB0"     # FK → ports.device_path (string, not integer id)
}
```

> Logging is **global**, not per data point (no `log_interval` field). Controlled by
> `app_config` keys `data_point_logging_enabled` and `data_point_log_interval_seconds`.

## Protocol Routing

DataPointManager determines protocol from the Port record:

| Port Type | Adapter | Transport |
|-----------|---------|-----------|
| `"modbus_rtu"` | `Modbus.RtuAdapter` | RS485 serial via `circuits_uart` |
| `"modbus_tcp"` | `Modbus.TcpAdapter` | Modbus TCP (MBAP header) over TCP/IP — gateways/native devices |
| `"rtu_over_tcp"` | `Modbus.RtuOverTcpAdapter` | RTU frames (CRC16) over raw TCP socket — serial servers |
| `"s7"` | `S7.Adapter` | TCP/IP to Siemens PLC |
| `"virtual"` | DB-backed (`Devices.Virtual`) | No hardware (handled inline in DataPointManager) |

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
  config :pou_con, :modbus_tcp_adapter, PouCon.Hardware.Modbus.SimulatedAdapter
  config :pou_con, :rtu_over_tcp_adapter, PouCon.Hardware.Modbus.SimulatedAdapter
  config :pou_con, :s7_adapter, PouCon.Hardware.S7.SimulatedAdapter
else
  config :pou_con, :modbus_adapter, PouCon.Hardware.Modbus.RtuAdapter
  config :pou_con, :s7_adapter, PouCon.Hardware.S7.Adapter
  # modbus_tcp_adapter / rtu_over_tcp_adapter default to their real adapters
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

- `lib/pou_con/hardware/data_point_manager.ex` — Central I/O router + ETS cache + inline virtual handling
- `lib/pou_con/hardware/data_point_manager_behaviour.ex` — Behaviour for mocking
- `lib/pou_con/hardware/port_worker.ex` — Per-port GenServer; serializes I/O, owns skipped_slaves/failure_counts
- `lib/pou_con/hardware/port_supervisor.ex` — DynamicSupervisor for hardware connection processes
- `lib/pou_con/equipment/schemas/data_point.ex` — DataPoint schema
- `lib/pou_con/hardware/data_point_tree_parser.ex` — JSON→keyword parser
- `lib/pou_con/hardware/devices/digital_io.ex` — read_digital_input/output, write_digital_output (all protocols)
- `lib/pou_con/hardware/devices/analog_io.ex` — read_analog_input/output, write_analog_output (all protocols)
- `lib/pou_con/hardware/modbus/rtu_adapter.ex` — Modbus RTU adapter
- `lib/pou_con/hardware/modbus/tcp_adapter.ex` — Modbus TCP adapter (MBAP)
- `lib/pou_con/hardware/modbus/rtu_over_tcp_adapter.ex` — RTU-over-TCP adapter (raw serial servers)
- `lib/pou_con/hardware/s7/adapter.ex` — Siemens S7 adapter
- `lib/pou_con/hardware/modbus/simulated_adapter.ex` — Modbus simulation (dev)
- `lib/pou_con/hardware/s7/simulated_adapter.ex` — S7 simulation (dev)
- `lib/pou_con/hardware/devices/virtual.ex` — Virtual device driver (DB-backed)
- `lib/pou_con_web/live/simulation_live.ex` — Simulation web UI

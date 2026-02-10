# PouCon Library Quick Reference

## Modbux (Modbus RTU + TCP)

### RTU Master — Single-Call API

```elixir
# Start
{:ok, pid} = Modbux.Rtu.Master.start_link(
  device: "/dev/ttyUSB0",
  speed: 9600,
  parity: :none,
  timeout: 2000
)

# Read coil (digital input/output state)
{:ok, [value]} = Modbux.Rtu.Master.request(pid, {:rc, slave_id, address, count})
# value: 0 or 1

# Read holding register (analog value)
{:ok, [high, low]} = Modbux.Rtu.Master.request(pid, {:rhr, slave_id, address, count})

# Force single coil (digital output)
:ok = Modbux.Rtu.Master.request(pid, {:fc, slave_id, address, value})
# value: 0 or 1

# Preset single holding register (analog output)
:ok = Modbux.Rtu.Master.request(pid, {:phr, slave_id, address, value})

# Stop
Modbux.Rtu.Master.stop(pid)
```

### Request Tuple Format
| Tuple | Modbus Function | Description |
|-------|----------------|-------------|
| `{:rc, slave, addr, count}` | FC01 Read Coils | Read digital states |
| `{:ri, slave, addr, count}` | FC02 Read Discrete Inputs | Read-only digital |
| `{:rhr, slave, addr, count}` | FC03 Read Holding Registers | Read analog values |
| `{:rir, slave, addr, count}` | FC04 Read Input Registers | Read-only analog |
| `{:fc, slave, addr, value}` | FC05 Force Single Coil | Write digital output |
| `{:phr, slave, addr, value}` | FC06 Preset Single Register | Write analog output |

### TCP Client — 2-Step API

```elixir
# Start + connect
{:ok, pid} = Modbux.Tcp.Client.start_link(
  ip: {192, 168, 1, 10},
  tcp_port: 502,
  timeout: 2000,
  active: false
)
:ok = Modbux.Tcp.Client.connect(pid)

# Request (2 steps)
:ok = Modbux.Tcp.Client.request(pid, {:rc, slave_id, address, count})
{:ok, [value]} = Modbux.Tcp.Client.confirmation(pid)

# Close
Modbux.Tcp.Client.close(pid)
Modbux.Tcp.Client.stop(pid)
```

**Note**: PouCon's `TcpAdapter` wraps the 2-step pattern into a single `request/2` with auto-reconnect on `:closed`.

### IEEE754 Float Helpers

```elixir
# 2 registers → float (for 32-bit sensors)
float = Modbux.IEEE754.from_2_regs(high_reg, low_reg, :be)  # Big-endian
float = Modbux.IEEE754.from_2_regs(high_reg, low_reg, :le)  # Little-endian

# float → 2 registers
{high, low} = Modbux.IEEE754.to_2_regs(float_val, :be)
```

### Endianness Notes
- Most Modbus devices use big-endian (`:be`) — this is the default
- Some devices (especially Asian manufacturers) use little-endian (`:le`)
- Waveshare IO modules use simple 16-bit integers, no float conversion needed

## Snapex7 (Siemens S7 Protocol)

### Connection
```elixir
{:ok, pid} = Snapex7.Client.start_link()
:ok = Snapex7.Client.connect_to(pid, ip: "192.168.1.10", rack: 0, slot: 1)
```

### Connection Parameters
| Device | Rack | Slot |
|--------|------|------|
| S7-300/400 | 0 | 2 |
| S7-1200/1500 | 0 | 1 |
| ET200SP | 0 | 1 |

### Read/Write API

```elixir
# Process Inputs (%IB): Digital inputs from field
{:ok, binary} = Snapex7.Client.eb_read(pid, start: byte_addr, amount: num_bytes)

# Process Outputs (%QB): Digital outputs to field
{:ok, binary} = Snapex7.Client.ab_read(pid, start: byte_addr, amount: num_bytes)
:ok = Snapex7.Client.ab_write(pid, start: byte_addr, data: <<byte_data>>)

# Data Blocks (DB): Structured data
{:ok, binary} = Snapex7.Client.db_read(pid, db_number: n, start: offset, amount: size)
:ok = Snapex7.Client.db_write(pid, db_number: n, start: offset, data: binary)

# Memory Markers (M): Internal flags
{:ok, binary} = Snapex7.Client.mb_read(pid, start: byte_addr, amount: num_bytes)
:ok = Snapex7.Client.mb_write(pid, start: byte_addr, data: <<byte_data>>)

# Disconnect
Snapex7.Client.disconnect(pid)
```

### Bit Extraction from Bytes
S7 returns raw bytes. Extract individual bits for digital I/O:
```elixir
{:ok, <<byte>>} = Snapex7.Client.eb_read(pid, start: 0, amount: 1)
bit_0 = Bitwise.band(byte, 1)          # %I0.0
bit_1 = Bitwise.band(byte >>> 1, 1)    # %I0.1
bit_7 = Bitwise.band(byte >>> 7, 1)    # %I0.7
```

### Error Handling
```elixir
# Snapex7 can return error tuples OR crash with :port_timed_out
case Snapex7.Client.eb_read(pid, start: 0, amount: 1) do
  {:ok, data} -> process(data)
  {:error, "Remote Server Error"} -> handle_disconnect()
end

# MUST wrap in try/catch for port timeouts
try do
  Snapex7.Client.eb_read(pid, start: 0, amount: 1)
catch
  :exit, :port_timed_out -> {:error, :timeout}
  :exit, reason -> {:error, {:exit, reason}}
end
```

**Sync-only**: All Snapex7 calls are synchronous (blocking). The S7.Adapter GenServer serializes access.

## Circuits.UART (Serial Communication)

```elixir
# Open port
{:ok, pid} = Circuits.UART.start_link()
:ok = Circuits.UART.open(pid, "/dev/ttyUSB0",
  speed: 9600,
  data_bits: 8,
  stop_bits: 1,
  parity: :none,
  active: false  # Use polling mode for Modbus
)

# Active mode (for receiving unsolicited data)
:ok = Circuits.UART.open(pid, "/dev/ttyUSB0",
  speed: 9600,
  active: true  # Sends {:circuits_uart, port, data} messages
)

# RS485 options (for half-duplex transceivers)
:ok = Circuits.UART.open(pid, "/dev/ttyUSB0",
  speed: 9600,
  rs485: %{
    enabled: true,
    rts_on_send: true,
    rts_after_send: false,
    delay_rts_before_send: 0,
    delay_rts_after_send: 0
  }
)

# Close
Circuits.UART.close(pid)
```

**Note**: PouCon doesn't use Circuits.UART directly — Modbux handles serial communication internally. But it's available if you need raw serial access.

## Ecto.SQLite3

### Key Limitations
| Limitation | Impact | Workaround |
|-----------|--------|-----------|
| Single writer | No concurrent writes | `pool_size: 1` in config |
| No `RENAME COLUMN` | Can't rename in migration | Create new, copy data, drop old |
| No `ALTER TYPE` | Can't change column types | Same as above |
| WAL mode | Better read concurrency | Enabled by default |
| VACUUM | Reclaims space | Runs weekly on Sundays (CleanupTask) |

### Configuration
```elixir
# config/config.exs
config :pou_con, PouCon.Repo,
  database: Path.expand("../pou_con_dev.db", Path.dirname(__ENV__.file)),
  pool_size: 1,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true
```

### Boolean Handling
SQLite stores booleans as integers (0/1). Ecto handles this transparently for schemas,
but raw queries and JSON exports need manual conversion:
```elixir
# In export_seeds.ex
defp convert_boolean(1), do: true
defp convert_boolean(0), do: false
defp convert_boolean(val), do: val
```

### Transaction Timeouts
For large operations (backup restore), increase timeout:
```elixir
Repo.transaction(fn -> ... end, timeout: 300_000)  # 5 minutes
```

## Key Files

- `lib/pou_con/hardware/modbus/real_adapter.ex` — Modbux RTU wrapper
- `lib/pou_con/hardware/modbus/tcp_adapter.ex` — Modbux TCP wrapper with auto-reconnect
- `lib/pou_con/hardware/s7/adapter.ex` — Snapex7 wrapper with backoff retry
- `lib/pou_con/hardware/s7/adapter_behaviour.ex` — S7 adapter behaviour
- `lib/pou_con/hardware/modbus/adapter.ex` — Modbus adapter behaviour

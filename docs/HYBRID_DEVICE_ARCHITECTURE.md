# Hybrid Device Architecture

This document describes the hybrid device architecture in PouCon that supports both custom device modules and generic device type templates.

## Overview

PouCon uses a **hybrid approach** to handle the wide variety of industrial Modbus devices:

1. **Custom Device Modules** - For complex devices requiring specialized parsing logic (power meters, VFDs, water meters with valve control)
2. **Generic Device Type Templates** - For simpler devices with standard register layouts (temperature sensors, pressure transmitters, simple meters)

```
┌─────────────────────────────────────────────────────────────────┐
│                        Device Types                              │
├─────────────────────────────────────────────────────────────────┤
│  COMPLEX (Custom Modules)         │  SIMPLE (Generic Templates) │
│  ─────────────────────────        │  ───────────────────────────│
│  • DELAB PQM-1000s                │  • Generic Temp Sensor       │
│  • VFD Controllers                │  • Pressure Transmitter      │
│  • PLCs with custom logic         │  • Level Sensor              │
│  • Water Meter (valve+flow)       │  • Simple Energy Meter       │
│                                   │  • 4-20mA Analog Input       │
│  → Elixir module per type         │  → JSON template in DB       │
│  → Full parsing flexibility       │  → Generic interpreter       │
└─────────────────────────────────────────────────────────────────┘
```

## When to Use Each Approach

### Use Custom Device Modules When:

- Device has complex multi-step write operations (e.g., valve control sequences)
- Data interpretation requires conditional logic (e.g., bit flags with states)
- Device has 50+ registers with different read strategies
- Protocol has non-standard features (waveforms, harmonics, events)
- Device requires initialization sequences or state machines

**Examples**: Power quality analyzers, water meters with valve control, VFDs, complex PLCs

### Use Generic Device Types When:

- Device has simple register layout (read temperature, read pressure)
- Standard data types (int16, uint16, float32)
- No complex business logic for interpretation
- User wants to add new device support without code changes

**Examples**: Temperature sensors, humidity sensors, pressure transmitters, level sensors, simple energy meters

## Database Schema

### DeviceType Table

```sql
CREATE TABLE device_types (
  id INTEGER PRIMARY KEY,
  name VARCHAR(255) NOT NULL UNIQUE,
  manufacturer VARCHAR(255),
  model VARCHAR(255),
  category VARCHAR(50) NOT NULL,  -- sensor, meter, actuator, io, analyzer
  description TEXT,
  register_map JSON NOT NULL,     -- Full register definition
  read_strategy VARCHAR(20) DEFAULT 'batch',
  is_builtin BOOLEAN DEFAULT false,
  inserted_at DATETIME,
  updated_at DATETIME
);
```

### Device Table (Updated)

```sql
-- New column added
ALTER TABLE devices ADD COLUMN device_type_id INTEGER REFERENCES device_types(id);
```

When `device_type_id` is set, the device uses `GenericDeviceInterpreter` instead of `read_fn`/`write_fn` dispatch.

## Register Map Structure

The `register_map` JSON field defines how to read and interpret device registers:

```json
{
  "registers": [
    {
      "name": "temperature",
      "address": 0,
      "count": 1,
      "type": "int16",
      "multiplier": 0.1,
      "unit": "°C",
      "access": "r"
    },
    {
      "name": "humidity",
      "address": 1,
      "count": 1,
      "type": "uint16",
      "multiplier": 0.1,
      "unit": "%",
      "access": "r"
    },
    {
      "name": "setpoint",
      "address": 10,
      "count": 1,
      "type": "int16",
      "multiplier": 0.1,
      "unit": "°C",
      "access": "rw"
    }
  ],
  "batch_start": 0,
  "batch_count": 2,
  "function_code": "holding"
}
```

### Supported Data Types

| Type | Registers | Description |
|------|-----------|-------------|
| `uint16` | 1 | Unsigned 16-bit integer |
| `int16` | 1 | Signed 16-bit integer |
| `uint32` | 2 | Unsigned 32-bit (big-endian) |
| `int32` | 2 | Signed 32-bit (big-endian) |
| `uint32_le` | 2 | Unsigned 32-bit (little-endian) |
| `int32_le` | 2 | Signed 32-bit (little-endian) |
| `float32` | 2 | IEEE 754 float (big-endian) |
| `float32_le` | 2 | IEEE 754 float (little-endian) |
| `uint64` | 4 | Unsigned 64-bit (big-endian) |
| `bool` | 1 | Boolean (0/1) |
| `enum` | 1 | Maps values to strings (requires `values` field) |
| `bitmask` | 1 | Decodes bit flags (requires `bits` field) |

### Enum Example

```json
{
  "name": "pipe_status",
  "address": 6,
  "count": 1,
  "type": "enum",
  "access": "r",
  "values": {
    "85": "empty",
    "170": "full"
  }
}
```

### Bitmask Example

```json
{
  "name": "alarm_flags",
  "address": 20,
  "count": 1,
  "type": "bitmask",
  "access": "r",
  "bits": {
    "0": "low_pressure",
    "1": "high_pressure",
    "2": "sensor_fault",
    "3": "power_fail"
  }
}
```

## Adding a New Generic Device Type

### Via Admin UI (Future)

1. Navigate to Admin → Device Types
2. Click "Add Device Type"
3. Fill in manufacturer, model, category
4. Define register map using JSON editor
5. Save template
6. Create Device records that reference this type

### Via Database/Seeds

```elixir
# priv/repo/seeds.exs

Repo.insert!(%PouCon.Hardware.DeviceType{
  name: "generic_temp_sensor",
  manufacturer: "Various",
  model: "RS485 Temperature Sensor",
  category: "sensor",
  description: "Generic Modbus RTU temperature sensor with 0.1°C resolution",
  register_map: %{
    "registers" => [
      %{
        "name" => "temperature",
        "address" => 0,
        "count" => 1,
        "type" => "int16",
        "multiplier" => 0.1,
        "unit" => "°C",
        "access" => "r"
      }
    ],
    "batch_start" => 0,
    "batch_count" => 1,
    "function_code" => "holding"
  },
  is_builtin: true
})
```

### Creating Device Instance

```elixir
# Create device that uses the template
Repo.insert!(%PouCon.Equipment.Schemas.Device{
  name: "temp_sensor_house_1",
  type: "generic_temp_sensor",
  slave_id: 5,
  port_device_path: "/dev/ttyUSB0",
  device_type_id: 1  # References the DeviceType record
})
```

## Adding a New Custom Device Module

For complex devices, create an Elixir module:

### 1. Create Device Module

```elixir
# lib/pou_con/hardware/devices/my_complex_device.ex

defmodule PouCon.Hardware.Devices.MyComplexDevice do
  @moduledoc """
  Device driver for MyComplexDevice.

  Register map:
  - 0x0000 (2 regs): Measurement 1 - Float32 LE
  - 0x0002 (2 regs): Measurement 2 - Float32 LE
  - 0x0010 (1 reg): Control register - Bitmask
  """

  def read_my_device(modbus, slave_id, _register, _channel) do
    case PouCon.Utils.Modbus.request(modbus, {:rhr, slave_id, 0x0000, 20}) do
      {:ok, registers} ->
        {:ok, parse_registers(registers)}
      {:error, reason} ->
        {:error, reason}
    end
  end

  def write_my_device_control(modbus, slave_id, _register, {action, _params}, _channel) do
    value = case action do
      :start -> 0x0001
      :stop -> 0x0000
    end

    case PouCon.Utils.Modbus.request(modbus, {:phr, slave_id, 0x0010, value}) do
      :ok -> {:ok, :success}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_registers(registers) do
    %{
      measurement_1: decode_float_le(Enum.at(registers, 0), Enum.at(registers, 1)),
      measurement_2: decode_float_le(Enum.at(registers, 2), Enum.at(registers, 3))
    }
  end

  defp decode_float_le(reg1, reg2) do
    <<value::float-little-32>> = <<reg1::big-16, reg2::big-16>>
    Float.round(value, 3)
  end
end
```

### 2. Register in DeviceManager

```elixir
# lib/pou_con/hardware/device_manager.ex

# Add to alias list
alias PouCon.Hardware.Devices.MyComplexDevice

# Add to get_device_module/1
defp get_device_module(fn_name) do
  case fn_name do
    # ... existing entries ...
    :read_my_device -> MyComplexDevice
    :write_my_device_control -> MyComplexDevice
  end
end
```

### 3. Create Device in Database

```elixir
Repo.insert!(%Device{
  name: "my_device_1",
  type: "my_complex_device",
  slave_id: 1,
  read_fn: "read_my_device",
  write_fn: "write_my_device_control",
  port_device_path: "/dev/ttyUSB0"
})
```

## Data Flow

### Custom Module Device

```
Device (read_fn="read_water_meter")
  → DeviceManager.poll_custom_devices
  → get_device_module(:read_water_meter) → XintaiWaterMeter
  → XintaiWaterMeter.read_water_meter(modbus, slave_id, ...)
  → Parse complex registers
  → Cache in ETS
```

### Generic Template Device

```
Device (device_type_id=1)
  → DeviceManager.poll_generic_devices
  → GenericDeviceInterpreter.read(modbus, slave_id, device_type)
  → Read registers per register_map
  → Decode values based on type/multiplier
  → Cache in ETS
```

## Migration

Run the migration to add DeviceType support:

```bash
mix ecto.migrate
```

This creates:
- `device_types` table
- Adds `device_type_id` column to `devices` table

## Categories

Device types are organized into categories:

| Category | Description | Example Devices |
|----------|-------------|-----------------|
| `sensor` | Temperature, humidity, pressure sensors | Generic temp sensor |
| `meter` | Energy meters, flow meters, counters | Simple kWh meter |
| `actuator` | Relays, valves, motor controls | Relay module |
| `io` | Digital/analog I/O modules | 8-channel DI/DO |
| `analyzer` | Power quality, gas analyzers (complex) | PQM-1000s |
| `other` | Miscellaneous devices | - |

## Best Practices

1. **Start with Generic Templates** - Try generic templates first; only create custom modules when needed

2. **Document Register Maps** - Always include manufacturer documentation reference in device module comments

3. **Validate Early** - DeviceType.changeset validates register_map structure

4. **Use Batch Reads** - Set `batch_start` and `batch_count` to minimize Modbus transactions

5. **Handle Errors Gracefully** - Both approaches cache errors properly for UI feedback

6. **Test with Simulation** - Use `SIMULATE_DEVICES=1` to test new device types without hardware

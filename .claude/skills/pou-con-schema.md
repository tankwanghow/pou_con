# PouCon Schema & Database Skill

## Table Catalog

### Hardware Layer
| Table | Purpose | Retention |
|-------|---------|-----------|
| `ports` | Serial/TCP/S7 connection configs | Permanent |
| `data_points` | I/O point definitions (DO, DI, AI, VDI) | Permanent |
| `virtual_digital_states` | In-memory virtual switch values | Permanent |

### Equipment Layer
| Table | Purpose | Retention |
|-------|---------|-----------|
| `equipment` | Equipment definitions + data_point_tree | Permanent |

### Automation Layer
| Table | Purpose | Retention |
|-------|---------|-----------|
| `interlock_rules` | Safety chain rules (upstream→downstream) | Permanent |
| `environment_control_configs` | Temperature step ladder config | Permanent |
| `light_schedules` | Light on/off time schedules | Permanent |
| `egg_collection_schedules` | Egg collection time schedules | Permanent |
| `feeding_schedules` | Feeding motor schedules | Permanent |
| `alarm_rules` | Alarm trigger definitions | Permanent |
| `alarm_conditions` | Individual conditions per alarm rule | Permanent |

### Logging Layer
| Table | Purpose | Retention |
|-------|---------|-----------|
| `equipment_events` | State changes, commands, errors | 30 days |
| `data_point_logs` | Periodic sensor/output value samples (hybrid: interval + on-change for discrete) | 30 days |
| `equipment_state_logs` | Periodic equipment on/off + running state samples | 30 days |

> **Logging was overhauled** (migrations `logging_refactor`, `global_logging_toggle`,
> `drop_daily_summaries_table`). The old `daily_summaries` table and `DailySummaryTask`/
> `PeriodicLogger` are **gone**. Logging is now globally toggled via `app_config` keys
> `data_point_logging_enabled` and `data_point_log_interval_seconds` (default 300s).

### Auth & Operations
| Table | Purpose | Retention |
|-------|---------|-----------|
| `users` | Authentication accounts | Permanent |
| `flocks` | Poultry flock lifecycle tracking | Permanent |
| `task_categories` | Operations task categories | Permanent |
| `task_templates` | Reusable task templates | Permanent |
| `tasks` | Daily operations tasks | Permanent |

## Equipment Schema

```elixir
# lib/pou_con/equipment/schemas/equipment.ex
schema "equipment" do
  field :name, :string          # Unique: "fan_1", "pump_2"
  field :title, :string         # Display: "Fan 1", "Pump 2"
  field :type, :string          # Controller type (see valid types below)
  field :data_point_tree, :string  # JSON: maps logical names to data point names
  field :active, :boolean, default: true
  field :poll_interval_ms, :integer  # Override default poll interval
  timestamps()
end
```

### Valid Equipment Types

Default poll interval is set by `Equipment.changeset` — `@sensor_meter_types`
(temp/humidity/co2/nh3/water_meter/power_meter/average_sensor/**power_indicator**) default
to **5000 ms**; every other type defaults to **500 ms**. (Override per-equipment via
`poll_interval_ms`, validated to 100–60000 ms.)

| Type | Controller | Default Poll (ms) | Required data_point_tree Keys |
|------|-----------|-------------------|-------------------------------|
| `"fan"` | Fan | 500 | `on_off_coil`, `running_feedback`, `auto_manual` |
| `"pump"` | Pump | 500 | `on_off_coil`, `running_feedback`, `auto_manual` |
| `"light"` | Light | 500 | `on_off_coil`, `auto_manual` |
| `"siren"` | Siren | 500 | `on_off_coil`, `auto_manual` |
| `"egg"` | Egg | 500 | `on_off_coil`, `running_feedback`, `auto_manual` |
| `"feed_in"` | FeedIn | 500 | `on_off_coil`, `auto_manual` |
| `"dung"` | Dung | 500 | `on_off_coil`, `running_feedback` |
| `"dung_horz"` | DungHor | 500 | `on_off_coil`, `running_feedback` |
| `"dung_exit"` | DungExit | 500 | `on_off_coil`, `running_feedback` |
| `"feeding"` | Feeding | 500 | `on_off_coil`, `running_feedback`, `front_limit`, `back_limit`, `auto_manual` |
| `"power_indicator"` | PowerIndicator | 5000 | `on_off_coil` |
| `"temp_sensor"` | Sensor | 5000 | `value` |
| `"humidity_sensor"` | Sensor | 5000 | `value` |
| `"co2_sensor"` | Sensor | 5000 | `value` |
| `"nh3_sensor"` | Sensor | 5000 | `value` |
| `"water_meter"` | Sensor | 5000 | `value` |
| `"power_meter"` | Sensor | 5000 | `value` |
| `"average_sensor"` | AverageSensor | 5000 | `sensors` (list) |

Optional keys for controllable equipment: `trip` (motor protection DI). The full valid-type
list lives in `Equipment.changeset`'s `validate_inclusion`.

## DataPoint Schema

```elixir
# lib/pou_con/equipment/schemas/data_point.ex
schema "data_points" do
  field :name, :string            # Unique: "relay_1"
  field :type, :string            # "DO", "DI", "AI", "AO" (VDI/VDO virtual)
  field :slave_id, :integer       # Modbus slave ID (or S7 byte address)
  field :register, :integer       # Register/coil number
  field :channel, :integer        # Bit/channel within register (digital), or nil
  field :read_fn, :string         # Function in DigitalIO/AnalogIO, e.g. "read_digital_output"
  field :write_fn, :string        # nil for read-only points
  field :description, :string     # Human-readable
  field :scale_factor, :float, default: 1.0   # Analog: multiply raw value
  field :offset, :float, default: 0.0         # Analog: add after scaling
  field :unit, :string            # Display unit, e.g. "°C"
  field :value_type, :string      # Decode: int16/uint16/int32/uint32/float32
  field :byte_order, :string, default: "high_low"  # 32-bit word order
  field :min_valid, :float        # Validation range (optional)
  field :max_valid, :float
  field :color_zones, :string     # JSON: threshold-based UI coloring
  field :inverted, :boolean, default: false    # Digital: NC wiring flip
  # FK is by STRING device_path, not integer port_id
  belongs_to :port, PouCon.Hardware.Ports.Port,
    foreign_key: :port_path, references: :device_path, type: :string
  timestamps()
end
```

> No `io_function`, `device_address`, `data_address`, `port_id`, or `log_interval` fields.

### read_fn / write_fn Values
Self-describing function names dispatched to the unified device modules (work across all
protocols — RTU, TCP, RTU-over-TCP, S7):

| read_fn / write_fn | Module | Direction |
|--------------------|--------|-----------|
| `read_digital_input` | `DigitalIO` | Read digital (DI) |
| `read_digital_output` / `write_digital_output` | `DigitalIO` | Read/write digital (DO) |
| `read_analog_input` | `AnalogIO` | Read analog (AI) |
| `read_analog_output` / `write_analog_output` | `AnalogIO` | Read/write analog (AO) |

## Port Schema

```elixir
# lib/pou_con/hardware/ports/port.ex
schema "ports" do
  field :name, :string            # Unique: "modbus-usb0", "plc-rack1"
  # @protocols = ~w(modbus_rtu modbus_tcp rtu_over_tcp s7 virtual)
  field :protocol, :string, default: "modbus_rtu"
  field :active, :boolean, default: true
  # Serial (modbus_rtu)
  field :device_path, :string     # "/dev/ttyUSB0" — also the FK target for data_points.port_path
  field :speed, :integer, default: 9600
  field :parity, :string, default: "none"
  field :data_bits, :integer, default: 8
  field :stop_bits, :integer, default: 1
  # Network (modbus_tcp, rtu_over_tcp, s7)
  field :ip_address, :string      # "192.168.1.10"
  field :tcp_port, :integer, default: 502   # rtu_over_tcp/serial servers often use 2001, etc.
  # S7-specific
  field :s7_rack, :integer, default: 0
  field :s7_slot, :integer, default: 1
  timestamps()
end
```

### Protocol Helpers
```elixir
Port.modbus_rtu?(%Port{protocol: "modbus_rtu"})  # true
Port.modbus_tcp?(%Port{protocol: "modbus_tcp"})  # true
Port.s7?(%Port{protocol: "s7"})                  # true
Port.virtual?(%Port{protocol: "virtual"})        # true (also true when device_path == "virtual")
# NOTE: there is no rtu_over_tcp?/1 helper — match protocol == "rtu_over_tcp" directly
```

## Migration Conventions

### SQLite-Specific
- No `RENAME COLUMN` — must create new column, copy data, drop old
- `pool_size: 1` — single-writer limitation
- Use `integer` for booleans (SQLite stores as 0/1)
- Avoid concurrent migrations

### Standard Pattern
```elixir
defmodule PouCon.Repo.Migrations.AddValveEquipmentType do
  use Ecto.Migration

  def change do
    # SQLite-safe operations
    alter table(:equipment) do
      add :new_field, :string
    end

    create index(:equipment, [:new_field])
  end
end
```

Generate with: `mix ecto.gen.migration add_valve_equipment_type`

## export_seeds.ex / backup.ex Sync Requirement

**CRITICAL**: Both `export_seeds.ex` and `backup.ex` have hardcoded table lists and select maps that must stay in sync:

When adding new tables or fields:
1. Update `lib/mix/tasks/export_seeds.ex` — add table to export list with correct field mapping
2. Update `lib/pou_con/backup.ex` — add table to restore list with matching field handling
3. Ensure boolean conversion is handled (SQLite 0/1 → Elixir boolean)
4. Ensure time field formatting (Time → ISO8601 strings for JSON)

### Tables in export_seeds.ex
```
ports, data_points, equipment, virtual_digital_states,
interlock_rules, environment_control_config (singular table name),
light_schedules, egg_collection_schedules, feeding_schedules,
alarm_rules, alarm_conditions, task_categories, task_templates
```

### Backup restore order (respects foreign keys)
Config tables first (ports, data_points, equipment, etc.), then log tables.

## Seed Data Patterns

Seed files are JSON in `priv/repo/seeds/`:
```
seeds/ports.json
seeds/data_points.json
seeds/equipment.json
seeds/virtual_digital_states.json
seeds/interlock_rules.json
...
```

Loaded by `mix run priv/repo/seeds.exs`

## Key Files

- `lib/pou_con/equipment/schemas/equipment.ex` — Equipment schema + type validation
- `lib/pou_con/equipment/schemas/data_point.ex` — DataPoint schema
- `lib/pou_con/hardware/ports/port.ex` — Port schema + protocol helpers
- `lib/mix/tasks/export_seeds.ex` — Database → JSON export
- `lib/pou_con/backup.ex` — Backup/restore with version handling
- `lib/pou_con/equipment/data_points.ex` — DataPoints context (CRUD + helpers)

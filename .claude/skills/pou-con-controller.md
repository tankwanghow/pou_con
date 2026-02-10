# PouCon Equipment Controller Skill

## Controller Taxonomy

### Tier 1: Macro-Based (`use BinaryController`)
Minimal code — just `use` statement + options. The macro generates the full GenServer.

| Controller | Type String | Auto/Manual | Running FB | Trip | Always Manual |
|-----------|-------------|-------------|------------|------|--------------|
| Light | `"light"` | yes | no | no | no |
| Siren | `"siren"` | yes | no | no | no |
| Pump | `"pump"` | yes | yes | yes | no |
| Egg | `"egg"` | yes | yes | yes | no |
| FeedIn | `"feed_in"` | yes | no | no | no |
| Dung | `"dung"` | no | yes | yes | yes |
| DungHor | `"dung_horz"` | no | yes | yes | yes |
| DungExit | `"dung_exit"` | no | yes | yes | yes |
| PowerIndicator | `"power_indicator"` | no | no | no | yes |

### Tier 2: Custom Binary (Fan)
Full hand-written GenServer. Fan is custom because it has a **physical 3-way switch** pattern:
- DI=1 (24V): AUTO position — software controls
- DI=0: ON or OFF position — physical bypass, software is read-only
- Uses `is_auto_manual_virtual_di` flag to distinguish virtual vs physical switches

### Tier 3: Non-Binary (Sensor, AverageSensor, Feeding)
Different state machines — not on/off equipment:
- **Sensor**: Reads analog values, no commands
- **AverageSensor**: Aggregates multiple sensor readings
- **Feeding**: Directional motor with limit switches (front/back)

## BinaryController Macro Options

```elixir
use PouCon.Equipment.Controllers.BinaryController,
  equipment_type: "pump",           # Required: matches equipment.type in DB
  default_poll_interval: 500,       # Self-poll interval (ms), override per-equipment via DB
  has_running_feedback: true,       # true = reads running_feedback DI for motor status
  has_auto_manual: true,            # true = reads auto_manual DI/VDI for mode
  has_trip_signal: true,            # true = reads trip DI for motor protection
  always_manual: false              # true = no auto mode at all (dung conveyors)
```

### Decision Matrix

| Question | Yes → | No → |
|----------|-------|------|
| Does it have a motor with contactor feedback? | `has_running_feedback: true` | `has_running_feedback: false` |
| Can automation control it? | `has_auto_manual: true` | `has_auto_manual: false` |
| Does it have a motor protection relay? | `has_trip_signal: true` | `has_trip_signal: false` |
| Is it always manually operated? | `always_manual: true` | `always_manual: false` |

## New Equipment Type Registration Checklist

When adding a new macro-based equipment type (e.g., "valve"):

### 1. Create controller module
```elixir
# lib/pou_con/equipment/controllers/valve.ex
defmodule PouCon.Equipment.Controllers.Valve do
  @moduledoc """
  Controller for water valve equipment.
  [Document device tree, operation mode, state machine, error detection]
  """

  use PouCon.Equipment.Controllers.BinaryController,
    equipment_type: "valve",
    default_poll_interval: 500,
    has_running_feedback: false,
    has_auto_manual: true,
    has_trip_signal: false
end
```

### 2. Register in EquipmentLoader
```elixir
# lib/pou_con/equipment/equipment_loader.ex
# Add to the case statement in load_and_start_controllers/0:
"valve" -> PouCon.Equipment.Controllers.Valve
```

### 3. Add to Equipment schema validation
```elixir
# lib/pou_con/equipment/schemas/equipment.ex
# Add "valve" to the valid types list and required keys
```

### 4. Create LiveView component
```elixir
# lib/pou_con_web/components/equipment/valve_component.ex
# Follow fan_component.ex or light_component.ex pattern
```

### 5. Create LiveView page
```elixir
# lib/pou_con_web/live/valves/index.ex
# Follow fans/index.ex pattern
```

### 6. Add route
```elixir
# lib/pou_con_web/router.ex
live "/valves", ValvesLive.Index, :index
```

### 7. Write tests
```elixir
# test/pou_con/equipment/controllers/valve_test.exs
# Follow light_test.exs or pump_test.exs pattern
```

## State Machine Fields

Every binary controller has this core state:

```elixir
%State{
  name: "pump_1",                    # Unique equipment identifier
  title: "Pump 1",                   # Display title
  on_off_coil: "WS-12-O-01",        # DO data point for relay control
  running_feedback: "WS-12-I-01",   # DI data point for motor status (or nil)
  auto_manual: "VT-200-15",         # DI/VDI for mode switch (or nil)
  trip: "WS-12-I-02",               # DI for motor protection (or nil)
  commanded_on: false,               # What we want (user/automation request)
  actual_on: false,                  # What hardware reports (coil state)
  is_running: false,                 # Motor feedback (or mirrors actual_on)
  is_tripped: false,                 # Motor protection status
  mode: :auto,                       # :auto | :manual
  error: nil,                        # nil | :timeout | :command_failed | ...
  interlocked: false,                # true when interlock blocks startup
  is_auto_manual_virtual_di: false, # true if mode is software-controlled
  inverted: false,                   # true for NC relay wiring
  poll_interval_ms: 500,             # Self-polling interval
  error_count: 0                     # Debounce counter for mismatch errors
}
```

## Synchronization Flow

```
poll_and_update(state)
  │
  ├── Read all data points (on_off_coil, running_feedback, auto_manual, trip)
  │     └── Any error? → timeout state
  │
  ├── Parse values (all logical: 1=ON, 0=OFF)
  │     ├── actual_on = coil_state == 1
  │     ├── is_running = fb_state == 1
  │     ├── mode = if mode_state == 1, :auto, :manual
  │     └── is_tripped = trip_state == 1
  │
  ├── Mode switch detection (manual→auto?)
  │     └── Yes → commanded_on = false, send OFF command
  │
  ├── Error detection (only when software controls)
  │     ├── :tripped (immediate)
  │     ├── :on_but_not_running (debounced, 3 polls)
  │     ├── :off_but_running (debounced, 3 polls)
  │     └── :timeout, :invalid_data (immediate)
  │
  ├── Error transition logging (old_error → new_error)
  │
  └── Interlock status check (for UI display)
```

## Safety Patterns

### Auto-Off on Mode Switch
When switching from MANUAL to AUTO, equipment is turned OFF automatically:
```elixir
commanded_on = if mode_switched_to_auto, do: false, else: state.commanded_on
if mode_switched_to_auto and actual_on do
  @data_point_manager.command(state.on_off_coil, :set_state, %{state: 0})
end
```
This gives automation a clean slate.

### Physical Panel Switch (Fan Only)
When physical 3-way switch is NOT in AUTO (DI=0), the controller becomes read-only:
```elixir
# In sync_coil:
defp sync_coil(%State{mode: :manual, is_auto_manual_virtual_di: false} = state) do
  poll_and_update(state)  # Read only, no commands
end

# In handle_cast(:turn_on, ...):
def handle_cast(:turn_on, %{mode: :manual, is_auto_manual_virtual_di: false} = state) do
  {:noreply, state}  # Ignore — panel controls the contactor directly
end
```

### Error Debouncing
Mismatch errors require 3 consecutive detections (configurable via `@error_debounce_threshold`):
```elixir
err when err in [:on_but_not_running, :off_but_running] ->
  new_count = state.error_count + 1
  if new_count >= @error_debounce_threshold, do: {err, new_count}, else: {state.error, new_count}
```
At 500ms polling, this gives 1.5s grace period for physical equipment response.

## Common Pitfalls

1. **Compile-time DataPointManager**: Never call DPM directly — always use `@data_point_manager Application.compile_env(:pou_con, :data_point_manager)` so tests can mock it
2. **Logical I/O only**: Controllers always use `%{state: 0}` (OFF) and `%{state: 1}` (ON). DataPointManager handles physical NC inversion
3. **DB queries in init**: `DataPoints.is_virtual?/1` and `DataPoints.is_inverted?/1` do DB lookups — fine in controllers but need fixture setup in tests
4. **Missing interlock check**: Always check `Helpers.check_interlock(name)` before `turn_on`. Interlocks are fail-open (returns `true` on error)
5. **Sync export_seeds + backup**: If you add equipment types, check that both `export_seeds.ex` and `backup.ex` handle them

## Key Files

- `lib/pou_con/equipment/controllers/binary_controller.ex` — The macro
- `lib/pou_con/equipment/controllers/helpers/binary_equipment_helpers.ex` — Shared helpers
- `lib/pou_con/equipment/controllers/fan.ex` — Custom controller (physical switch)
- `lib/pou_con/equipment/controllers/light.ex` — Simplest macro user
- `lib/pou_con/equipment/controllers/pump.ex` — Macro with running feedback + trip
- `lib/pou_con/equipment/controllers/dung.ex` — Always-manual macro user
- `lib/pou_con/equipment/equipment_loader.ex` — Type→module mapping
- `lib/pou_con/equipment/schemas/equipment.ex` — Equipment schema + validation

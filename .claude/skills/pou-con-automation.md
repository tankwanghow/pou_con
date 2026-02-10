# PouCon Automation Layer Skill

## Overview

The automation layer sits between controllers and the UI, making decisions based on sensor data, schedules, and safety rules. All automation services are GenServers that poll periodically.

**Startup order** (in `application.ex`): InterlockController → EquipmentLoader → Automation Services

## EnvironmentController

**Purpose**: Auto-controls fans and pumps based on temperature and humidity.

**Architecture**:
- GenServer with configurable poll interval (default 10s)
- Loads config from `environment_control_configs` table
- Splits fans into **failsafe** (always manual, 24/7) and **auto** groups
- Uses 5-step temperature escalation

**Temperature Step Ladder**:
```
Step 1: temp > step_1_temp → turn on step_1_fans
Step 2: temp > step_2_temp → turn on step_1 + step_2_fans
Step 3: temp > step_3_temp → turn on step_1 + step_2 + step_3_fans
Step 4: temp > step_4_temp → turn on all fans
Step 5: temp > step_5_temp → turn on all fans + pumps (emergency cooling)
```

**Key behaviors**:
- **Step delay**: Waits `delay_between_step_seconds` before transitioning to prevent hunting
- **Stagger delay**: Prevents rapid on/off switching within a cycle
- **Delta boost**: If front-to-back temperature difference exceeds threshold, jumps to highest step
- **Humidity override**: Can activate pumps based on humidity threshold regardless of temperature
- **Reality scanning**: Each poll reads actual hardware state (handles manual mode switches)

**Critical rule**: Only controls equipment in `:auto` mode. Skips equipment in `:manual`.

**PubSub**: Publishes to `"environment_config"` on config changes.

**Key file**: `lib/pou_con/automation/environment/environment_controller.ex`

## InterlockController

**Purpose**: Enforces safety chains — prevents equipment from starting if prerequisites aren't met.

**Architecture**:
- GenServer with ETS table for lock-free reads
- 500ms polling interval for fast response
- Rules loaded from `interlock_rules` database table

**Rule format**: `upstream → downstream` (downstream cannot run without upstream)
```
Example: fan_1 → pump_1 (pump cannot start if fan is not running)
```

**Key API**:
```elixir
# Check if equipment can start (called by controllers before turn_on)
InterlockController.can_start?("pump_1")
# => {:ok, :allowed} or {:error, "Blocked by: fan_1 (not running)"}
```

**Cascade stopping**: When upstream equipment stops, automatically sends `turn_off` to all downstream equipment.

**Fail-open design**: If InterlockController crashes or is unavailable, controllers default to allowing start (returns `true` on error). This prevents a software fault from shutting down all equipment.

**Key file**: `lib/pou_con/automation/interlock/interlock_controller.ex`

## Scheduler Pattern

All schedulers follow this pattern:

```elixir
defmodule PouCon.Automation.XXX.XXXScheduler do
  use GenServer

  @check_interval 1_000  # Check every 1 second

  def init(_) do
    schedule_check()
    {:ok, load_schedules()}
  end

  def handle_info(:check, state) do
    current_time = PouCon.current_user_time()  # Timezone-aware!

    for schedule <- state.schedules do
      equipment_status = EquipmentCommands.status(schedule.equipment_name)

      # Only control equipment in AUTO mode
      if equipment_status.mode == :auto do
        if should_be_on?(schedule, current_time) do
          EquipmentCommands.turn_on(schedule.equipment_name)
        else
          EquipmentCommands.turn_off(schedule.equipment_name)
        end
      end
    end

    schedule_check()
    {:noreply, state}
  end

  defp schedule_check, do: Process.send_after(self(), :check, @check_interval)
end
```

### LightScheduler
- Checks `light_schedules` table for time-based on/off
- Simple: if current time is between `on_time` and `off_time`, turn on
- Handles overnight schedules (on_time > off_time, e.g., 18:00→06:00)

### EggCollectionScheduler
- Checks `egg_collection_schedules` for collection times
- Sends turn_on at scheduled time, turns off after duration
- Multiple collection times per day

### FeedingScheduler
- Most complex scheduler — handles directional motor with limit switches
- Validates: move_to_back only if front_limit=ON AND back_limit=OFF
- Validates: move_to_front only if front_limit=OFF AND back_limit=ON
- Checks FeedIn bucket status before allowing move_to_back

## AlarmController

**Purpose**: Triggers sirens based on configurable conditions.

**Architecture**:
- GenServer with 2-second polling
- Rules from `alarm_rules` + `alarm_conditions` tables
- Each rule targets a specific siren

**Logic modes**:
- `"any"` (OR): Any condition triggers the alarm
- `"all"` (AND): All conditions must be true to trigger

**Condition types**:
| Type | Field | Operators |
|------|-------|-----------|
| Sensor threshold | `sensor_name` | `above`, `below`, `equals` |
| Equipment state | `equipment_name` | `off`, `not_running`, `error` |

**Alarm states**:
- **Auto-clear**: Clears automatically when conditions return to normal
- **Manual-clear**: Requires user acknowledgment via API call
- **Mute**: Silences siren for configurable duration while tracking state

**Multi-siren support**: Each alarm rule specifies which siren to activate.

**Key file**: `lib/pou_con/automation/alarm/alarm_controller.ex`

## FeedInController

**Purpose**: Monitors feed-in bucket sensor and triggers filling.

**Architecture**:
- Polls feed_in equipment status
- When bucket is empty (sensor triggers), commands feed_in to fill
- Stops when bucket is full

**Key file**: `lib/pou_con/automation/feeding/feed_in_controller.ex`

## PubSub Topics Reference

| Topic | Publisher | Subscribers |
|-------|-----------|------------|
| `"data_point_data"` | DataPointManager | LiveView pages, automation |
| `"equipment_status"` | StatusBroadcaster | LiveView pages |
| `"environment_config"` | EnvironmentController | Environment config UI |
| `"interlock_rules"` | Admin UI | InterlockController |

## Common Pitfalls

1. **Timezone**: Always use `PouCon.current_user_time()` for schedule comparisons, never `Time.utc_now()`
2. **Mode check**: Always verify `equipment.mode == :auto` before sending automation commands
3. **Fail-open interlocks**: InterlockController returns `true` (allowed) on any error — this is intentional for safety
4. **Step delay**: EnvironmentController delays between steps to prevent hunting — don't reduce below 30s
5. **Cascade stops**: InterlockController automatically stops downstream equipment — don't duplicate this logic in controllers

## Key Files

- `lib/pou_con/automation/environment/environment_controller.ex` — Temperature/humidity auto-control
- `lib/pou_con/automation/environment/failsafe_validator.ex` — Validates failsafe fan configuration
- `lib/pou_con/automation/interlock/interlock_controller.ex` — Safety chain enforcement
- `lib/pou_con/automation/lighting/light_scheduler.ex` — Light on/off scheduling
- `lib/pou_con/automation/egg_collection/egg_collection_scheduler.ex` — Egg collection scheduling
- `lib/pou_con/automation/feeding/feeding_scheduler.ex` — Feeding motor scheduling
- `lib/pou_con/automation/feeding/feed_in_controller.ex` — Feed-in bucket monitoring
- `lib/pou_con/automation/alarm/alarm_controller.ex` — Alarm/siren management

# PouCon Automation Layer Skill

## Overview

The automation layer sits between controllers and the UI, making decisions based on sensor data, schedules, and safety rules. All automation services are GenServers that poll periodically.

**Startup order** (in `application.ex`): InterlockController → EquipmentLoader → Automation Services

## EnvironmentController

**Purpose**: Auto-controls fans and pumps based on temperature and humidity.

**Architecture**:
- GenServer that polls periodically (`poll_interval_ms` from config)
- Loads config from the `environment_control_config` table (singular)
- **Count-based fan model** (not named fan lists): fans split into a **failsafe** count
  (`failsafe_fans_count`, user-controlled MANUAL fans running 24/7 for minimum ventilation)
  and **auto** fans the controller drives via per-step `step_N_extra_fans` counts
- Total fans at step N = `failsafe_fans_count + step_N_extra_fans`

**Temperature Step Ladder** (count-based):
```
Each step has a temperature threshold + step_N_extra_fans (extra AUTO fans above failsafe).
temp crosses step_N_temp → target = failsafe_fans_count + step_N_extra_fans
Each poll SCANS actual fan states from hardware (handles users flipping the 3-way switch)
then turns AUTO fans on/off to reach the target count — no stale tracking.
Pumps: humidity >= hum_max → all pumps stop; <= hum_min → all pumps run; else per step.
```

**Startup Phase (post-restart blind period)**:
- On restart the controller collects sensor/equipment data but issues **no commands**,
  so it doesn't act on stale observations while controllers are still adopting hardware state.
- Exits on the first poll with valid `avg_temp`, OR after 10 consecutive invalid-temp polls
  (safety fallback). On exit it applies its decision immediately (bypasses
  `delay_between_step_seconds`, still respects `stagger_delay_seconds`).

**Sensor Loss Safety (permanent)**:
- One counter tracks consecutive polls with no valid temperature.
- At 10 (during startup or normal operation) it forces step 4 / highest configured step to
  protect against overheating when sensors are unreliable.

**Other key behaviors**:
- **Step delay**: Waits `delay_between_step_seconds` before transitioning to prevent hunting
- **Stagger delay**: `stagger_delay_seconds` between individual relay operations
- **Delta boost**: front-to-back temperature difference over threshold jumps to highest step
- **Reality scanning**: each poll reads actual hardware state (handles manual switches)

**Critical rule**: Only controls equipment in `:auto` mode. Skips equipment in `:manual`.

**FailsafeValidator**: a separate child that reports actual failsafe-fan status; the
controller reconciles `configured_failsafe` vs `actual_failsafe` each cycle.

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

## FeedIn (now an equipment controller, not an automation service)

The old `FeedInController` automation module was **removed**. Feed-in is now the `FeedIn`
equipment controller (`lib/pou_con/equipment/controllers/feed_in.ex`, type `"feed_in"`):
- Watches the configured **trigger** bucket's front-limit edge to start a fill.
- `turn_on(name, max_fill_minutes \\ 30)` — `max_fill_minutes` (1..120) is a safety upper
  bound. Temporary logic infers "full" via timer/hardwired switch until a full-switch DI is
  wired (`has_full_switch`, `fill_completed` are temporary fields).
- The `FeedingScheduler` checks FeedIn status before allowing `move_to_back`.

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
- `lib/pou_con/equipment/controllers/feed_in.ex` — Feed-in controller (replaced FeedInController)
- `lib/pou_con/automation/alarm/alarm_controller.ex` — Alarm/siren management

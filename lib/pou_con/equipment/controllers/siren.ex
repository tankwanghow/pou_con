defmodule PouCon.Equipment.Controllers.Siren do
  @moduledoc """
  Controller for alarm siren equipment (combined light and sound).

  Manages on/off state for siren with schedule-based automation
  through the LightScheduler (shared with lights) and alarm triggering
  through the AlarmController.

  ## Device Tree Configuration

  ```yaml
  on_off_coil: SIREN-BACK       # Digital output for siren (light + sound)
  auto_manual: SIREN-AUTO       # Virtual device for mode selection
  running_feedback: WS-12-I-01  # Digital input for siren running status
  ```

  ## Fail-Safe Wiring (Power Failure Protection)

  For critical alarms that must sound during power failure, use NC (Normally Closed)
  relay wiring with a battery-powered siren and set `inverted: true`:

  - **Normal operation**: Relay coil energized → NC contact open → Siren OFF
  - **Alarm active**: Relay coil de-energized → NC contact closed → Siren ON
  - **Power failure**: Relay coil de-energized → NC contact closed → Siren ON

  With `inverted: true`, the software logic is automatically adjusted:
  - `turn_on()` sends coil value 0 (de-energize) → siren sounds
  - `turn_off()` sends coil value 1 (energize) → siren silent

  See CLAUDE.md "Fail-Safe Siren Wiring" section for detailed wiring diagrams.

  ## State Machine

  - `commanded_on` - Current siren state (commanded directly)
  - `actual_on` - Mirrors commanded state (no feedback)
  - `mode` - `:auto` (alarm controller allowed) or `:manual` (user control only)

  ## Error Detection

  - `:timeout` - No response from Modbus device
  - `:command_failed` - Modbus write command failed

  Note: Sirens don't have running feedback, so `is_running` mirrors `actual_on`.

  ## Alarm Integration

  The AlarmController triggers sirens based on configured alarm rules.
  Each alarm rule can specify which siren to activate when conditions are met.
  """

  use PouCon.Equipment.Controllers.BinaryController,
    equipment_type: "siren",
    default_poll_interval: 1000,
    has_running_feedback: true,
    has_auto_manual: true,
    has_trip_signal: false
end

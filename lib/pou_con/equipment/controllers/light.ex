defmodule PouCon.Equipment.Controllers.Light do
  @moduledoc """
  Controller for poultry house lighting equipment.

  Manages on/off state for lighting zones with schedule-based automation
  through the LightScheduler.

  ## Device Tree Configuration

  ```yaml
  on_off_coil: WS-13-O-01      # Digital output to control light relay
  auto_manual: VT-200-20        # Virtual device for mode selection
  ```

  ## State Machine

  - `commanded_on` - What the system wants (user command or scheduler)
  - `actual_on` - What the hardware reports (coil state)
  - `mode` - `:auto` (scheduler allowed) or `:manual` (user control only)

  ## Error Detection

  - `:timeout` - No response from Modbus device
  - `:command_failed` - Modbus write command failed

  Note: Lights don't have running feedback, so `is_running` mirrors `actual_on`.

  ## Schedule Integration

  The LightScheduler automatically turns lights on/off based on configured
  schedules (on_time, off_time). Only affects equipment in `:auto` mode.
  Schedules are configured per-equipment in the light_schedules table.
  """

  use PouCon.Equipment.Controllers.BinaryController,
    equipment_type: "light",
    default_poll_interval: 1000,
    has_running_feedback: false,
    has_auto_manual: true,
    has_trip_signal: false
end

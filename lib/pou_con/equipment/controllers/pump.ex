defmodule PouCon.Equipment.Controllers.Pump do
  @moduledoc """
  Controller for water/cooling pump equipment.

  Manages on/off state, monitors running feedback, and handles auto/manual mode
  switching for cooling system pumps in the poultry house.

  ## Device Tree Configuration

  ```yaml
  on_off_coil: WS-12-O-01      # Digital output to control pump relay
  running_feedback: WS-12-I-01  # Digital input for motor running status
  auto_manual: VT-200-15        # Virtual device for mode selection
  trip: WS-12-I-02              # Optional: motor trip signal
  ```

  ## State Machine

  - `commanded_on` - What the system wants (user command or automation)
  - `actual_on` - What the hardware reports (coil state)
  - `is_running` - Motor running feedback from contactor auxiliary contact
  - `mode` - `:auto` (automation allowed) or `:manual` (user control only)

  ## Error Detection

  - `:timeout` - No response from Modbus device
  - `:on_but_not_running` - Commanded ON but motor not running (check contactor/motor)
  - `:off_but_running` - Commanded OFF but motor still running (stuck contactor)
  - `:command_failed` - Modbus write command failed
  - `:tripped` - Motor protection tripped

  ## Interlock Integration

  Pumps typically have interlocks requiring upstream fans to be running before
  the pump can start. This prevents cooling water spray without ventilation.
  Checks `InterlockHelper.check_can_start/1` before turning on.

  ## Auto-Control Integration

  The EnvironmentController manages pumps based on temperature/humidity readings,
  activating cooling when thresholds are exceeded.
  """

  use PouCon.Equipment.Controllers.BinaryController,
    equipment_type: "pump",
    default_poll_interval: 500,
    has_running_feedback: true,
    has_auto_manual: true,
    has_trip_signal: true
end

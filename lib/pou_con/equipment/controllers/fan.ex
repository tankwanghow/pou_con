defmodule PouCon.Equipment.Controllers.Fan do
  @moduledoc """
  Controller for ventilation fan equipment.

  Manages on/off state, monitors running feedback, and handles auto/manual mode
  for poultry house ventilation fans.

  Implementation is provided by the shared `BinaryController` macro.

  ## Device Tree Configuration

  ```yaml
  on_off_coil: WS-11-O-01      # Digital output to control fan relay
  running_feedback: WS-11-I-01  # Digital input for motor running status
  auto_manual: WS-11-I-02       # Physical DI from 3-way switch (AUTO position)
  trip: WS-11-I-03              # Optional motor protection trip signal
  ```

  ## Inverted (NC) Wiring Support

  For normally closed (NC) relay wiring where coil OFF = fan runs,
  set `inverted: true` on the DO data point in the admin UI.
  The DataPointManager handles physical inversion transparently.

  ## Physical 3-Way Switch Control

  Each fan has a physical 3-position selector switch at the electrical panel:
  - **AUTO**: DI = 1 (24V) → Software controls fan via relay
  - **ON**: DI = 0 → Fan runs directly (physical bypass), software observes only
  - **OFF**: DI = 0 → Fan stopped (no power), software observes only

  When DI = 0 (switch not in AUTO), the controller becomes read-only:
  - Does NOT send commands to the relay
  - Only monitors running feedback for display
  - Prevents false "off_but_running" errors from physical override

  ## State Machine

  - `commanded_on` - What the system wants (user command or automation)
  - `actual_on` - What the hardware reports (coil state)
  - `is_running` - Motor running feedback from contactor auxiliary contact
  - `mode` - `:auto` (software control) or `:manual` (physical panel control)

  ## Error Detection

  - `:timeout` - No response from Modbus device
  - `:on_but_not_running` - Commanded ON but motor not running (check contactor/motor)
  - `:off_but_running` - Commanded OFF but motor still running (stuck contactor)
  - `:command_failed` - Modbus write command failed
  - `:tripped` - Motor protection tripped

  Note: Error detection only applies in AUTO mode. In MANUAL mode, physical
  switch controls the contactor directly, so coil/running mismatches are expected.

  ## Interlock Integration

  Before turning on, checks `InterlockHelper.check_can_start/1` to enforce
  safety chains (e.g., pump cannot start if upstream fan is off).
  Interlocks only apply in AUTO mode.
  """

  use PouCon.Equipment.Controllers.BinaryController,
    equipment_type: "fan",
    default_poll_interval: 500,
    has_running_feedback: true,
    has_auto_manual: true,
    has_trip_signal: true
end

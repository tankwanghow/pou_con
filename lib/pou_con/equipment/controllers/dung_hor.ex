defmodule PouCon.Equipment.Controllers.DungHor do
  @moduledoc """
  Controller for horizontal dung collection conveyor.

  Manages the horizontal conveyor belt that runs along the length of the
  poultry house, collecting manure from all vertical (Dung) conveyors
  and transporting it to the exit conveyor.

  ## Device Tree Configuration

  ```yaml
  on_off_coil: WS-14-O-04      # Digital output to control conveyor motor
  running_feedback: WS-14-I-04  # Digital input for motor running status
  trip: WS-14-I-05              # Optional: motor trip signal
  ```

  ## Manual-Only Operation

  The horizontal conveyor is manually controlled and typically runs
  continuously while vertical conveyors are operating.

  ## Operational Sequence

  Proper dung removal sequence:
  1. Start DungHor (horizontal) first
  2. Start individual Dung (vertical) conveyors
  3. Run until all belts are clear
  4. Stop vertical conveyors
  5. Continue horizontal until clear
  6. Start DungExit to external storage
  7. Stop all when complete

  ## State Machine

  - `commanded_on` - What the operator requested
  - `actual_on` - What the hardware reports (coil state)
  - `is_running` - Motor running feedback from contactor

  ## Error Detection

  - `:timeout` - No response from Modbus device
  - `:on_but_not_running` - Motor commanded ON but not running
  - `:off_but_running` - Motor commanded OFF but still running
  - `:command_failed` - Modbus write command failed
  - `:tripped` - Motor protection tripped
  """

  use PouCon.Equipment.Controllers.BinaryController,
    equipment_type: "dung horizontal",
    default_poll_interval: 500,
    has_running_feedback: true,
    has_auto_manual: false,
    has_trip_signal: true,
    always_manual: true
end

defmodule PouCon.Equipment.Controllers.Dung do
  @moduledoc """
  Controller for vertical/inclined dung conveyor belts.

  Manages the main dung removal conveyors that transport manure from under
  the cage tiers to the horizontal collection conveyor. These are typically
  operated manually by workers during daily cleaning.

  ## Device Tree Configuration

  ```yaml
  on_off_coil: WS-14-O-01      # Digital output to control conveyor motor
  running_feedback: WS-14-I-01  # Digital input for motor running status
  trip: WS-14-I-02              # Optional: motor trip signal
  ```

  ## Manual-Only Operation

  Unlike fans and pumps, dung conveyors do not have an auto/manual mode.
  They are always manually controlled by operators. This is intentional:
  - Dung removal requires visual inspection
  - Operators need to verify belt is clear before starting
  - Runtime depends on manure accumulation (varies daily)

  ## State Machine

  - `commanded_on` - What the operator requested
  - `actual_on` - What the hardware reports (coil state)
  - `is_running` - Motor running feedback from contactor

  ## Error Detection

  - `:timeout` - No response from Modbus device
  - `:on_but_not_running` - Motor commanded ON but not running (jam/overload)
  - `:off_but_running` - Motor commanded OFF but still running
  - `:command_failed` - Modbus write command failed
  - `:tripped` - Motor protection tripped

  ## Related Controllers

  - `DungHor` - Horizontal collection conveyor (receives from all Dung conveyors)
  - `DungExit` - Exit conveyor to external storage
  """

  use PouCon.Equipment.Controllers.BinaryController,
    equipment_type: "dung",
    default_poll_interval: 500,
    has_running_feedback: true,
    has_auto_manual: false,
    has_trip_signal: true,
    always_manual: true
end

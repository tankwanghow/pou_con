defmodule PouCon.Equipment.Controllers.DungExit do
  @moduledoc """
  Controller for dung exit conveyor.

  Manages the final conveyor that transports collected manure from the
  horizontal conveyor to external storage (truck, pit, or composting area).

  ## Device Tree Configuration

  ```yaml
  on_off_coil: WS-14-O-05      # Digital output to control conveyor motor
  running_feedback: WS-14-I-05  # Digital input for motor running status
  trip: WS-14-I-06              # Optional: motor trip signal
  ```

  ## Manual-Only Operation

  Like other dung conveyors, the exit conveyor is manually controlled.
  Operators run it when external storage is ready to receive manure.

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

  ## Related Controllers

  - `Dung` - Vertical conveyors feeding into collection system
  - `DungHor` - Horizontal conveyor that feeds this exit conveyor
  """

  use PouCon.Equipment.Controllers.BinaryController,
    equipment_type: "dung exit",
    default_poll_interval: 500,
    has_running_feedback: true,
    has_auto_manual: false,
    has_trip_signal: true,
    always_manual: true
end

defmodule PouCon.Hardware.Devices.DigitalIOAddressTest do
  use ExUnit.Case, async: true

  alias PouCon.Hardware.Devices.DigitalIO

  test "channel is 1-indexed within an 8-bit register group" do
    assert DigitalIO.modbus_address(0, 1) == 0
    assert DigitalIO.modbus_address(0, 8) == 7
    assert DigitalIO.modbus_address(1, 1) == 8
    assert DigitalIO.modbus_address(2, 3) == 18
  end

  test "no channel uses register as the address" do
    assert DigitalIO.modbus_address(5, nil) == 5
  end
end

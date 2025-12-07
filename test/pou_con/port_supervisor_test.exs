defmodule PouCon.PortSupervisorTest do
  use ExUnit.Case, async: true

  alias PouCon.Hardware.PortSupervisor

  test "starts successfully" do
    # The supervisor is started by the application
    assert Process.whereis(PortSupervisor) != nil
    assert Process.alive?(Process.whereis(PortSupervisor))
  end

  test "is a DynamicSupervisor" do
    info = DynamicSupervisor.which_children(PortSupervisor)
    assert is_list(info)
  end

  test "can count children" do
    count = DynamicSupervisor.count_children(PortSupervisor)
    assert is_map(count)
    assert Map.has_key?(count, :active)
    assert Map.has_key?(count, :specs)
    assert Map.has_key?(count, :supervisors)
    assert Map.has_key?(count, :workers)
  end

  describe "start_modbus_master/1" do
    test "requires valid port struct" do
      # We can't actually test Modbus without hardware
      # Just verify the function exists
      assert function_exported?(PortSupervisor, :start_modbus_master, 1)
    end
  end

  describe "stop_modbus_master/1" do
    test "function exists" do
      assert function_exported?(PortSupervisor, :stop_modbus_master, 1)
    end
  end
end

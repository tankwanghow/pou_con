defmodule PouCon.DeviceManagerBehaviourTest do
  use ExUnit.Case, async: false

  alias PouCon.Hardware.DeviceManagerBehaviour

  test "defines required callbacks" do
    callbacks = DeviceManagerBehaviour.behaviour_info(:callbacks)

    assert {:command, 3} in callbacks
    assert {:get_cached_data, 1} in callbacks
    assert {:list_devices, 0} in callbacks
    assert {:list_ports, 0} in callbacks
    assert {:query, 1} in callbacks
    assert {:get_all_cached_data, 0} in callbacks
  end

  test "is a behaviour module" do
    # Check that it's defined as a module with @callback definitions
    assert Code.ensure_loaded?(DeviceManagerBehaviour)
    info = DeviceManagerBehaviour.module_info()
    assert is_list(info)
  end
end

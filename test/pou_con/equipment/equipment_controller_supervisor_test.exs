defmodule PouCon.EquipmentControllerSupervisorTest do
  use ExUnit.Case, async: false

  alias PouCon.Equipment.EquipmentControllerSupervisor

  test "starts successfully" do
    # The supervisor is started by the application
    # We just verify it exists and is running
    assert Process.whereis(EquipmentControllerSupervisor) != nil
    assert Process.alive?(Process.whereis(EquipmentControllerSupervisor))
  end

  test "is a DynamicSupervisor" do
    info = DynamicSupervisor.which_children(EquipmentControllerSupervisor)
    assert is_list(info)
  end

  test "can count children" do
    count = DynamicSupervisor.count_children(EquipmentControllerSupervisor)
    assert is_map(count)
    assert Map.has_key?(count, :active)
    assert Map.has_key?(count, :specs)
    assert Map.has_key?(count, :supervisors)
    assert Map.has_key?(count, :workers)
  end
end

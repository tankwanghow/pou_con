defmodule PouCon.DeviceControllers.DungHorTest do
  use PouCon.DataCase
  import Mox

  alias PouCon.DeviceControllers.DungHor
  alias PouCon.DeviceManagerMock

  setup :verify_on_exit!

  setup do
    Mox.set_mox_global(PouCon.DeviceManagerMock)

    id = System.unique_integer([:positive])

    device_names = %{
      on_off_coil: "test_dunghor_coil_#{id}",
      running_feedback: "test_dunghor_fb_#{id}"
    }

    stub(DeviceManagerMock, :get_cached_data, fn _name -> {:ok, %{state: 0}} end)
    stub(DeviceManagerMock, :command, fn _name, _cmd, _params -> {:ok, :success} end)

    %{devices: device_names}
  end

  describe "start/1 and initialization" do
    test "starts successfully with valid options", %{devices: devices} do
      opts = [
        name: "test_dunghor_1_#{System.unique_integer([:positive])}",
        title: "Test DungHor 1",
        on_off_coil: devices.on_off_coil,
        running_feedback: devices.running_feedback
      ]

      assert {:ok, pid} = DungHor.start(opts)
      assert Process.alive?(pid)
    end
  end

  describe "status/1" do
    setup %{devices: devices} do
      name = "test_dunghor_status_#{System.unique_integer([:positive])}"

      opts = [
        name: name,
        title: "Test Status DungHor",
        on_off_coil: devices.on_off_coil,
        running_feedback: devices.running_feedback
      ]

      {:ok, _pid} = DungHor.start(opts)
      %{name: name}
    end

    test "returns status map with all required fields", %{name: name} do
      status = DungHor.status(name)
      assert is_map(status)
      assert status.name == name
      assert status.commanded_on == false
      assert status.actual_on == false
      assert status.is_running == false
      assert status.error == nil
    end

    test "reflects state from DeviceManager", %{devices: devices} do
      name = "test_dunghor_state_#{System.unique_integer([:positive])}"

      stub(DeviceManagerMock, :get_cached_data, fn
        n when n == devices.on_off_coil -> {:ok, %{state: 1}}
        n when n == devices.running_feedback -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      opts = [
        name: name,
        on_off_coil: devices.on_off_coil,
        running_feedback: devices.running_feedback
      ]

      {:ok, _pid} = DungHor.start(opts)
      Process.sleep(50)

      status = DungHor.status(name)
      assert status.actual_on == true
      assert status.is_running == true
    end
  end

  describe "commands" do
    setup %{devices: devices} do
      name = "test_dunghor_cmd_#{System.unique_integer([:positive])}"

      opts = [
        name: name,
        on_off_coil: devices.on_off_coil,
        running_feedback: devices.running_feedback
      ]

      {:ok, pid} = DungHor.start(opts)
      %{name: name, pid: pid}
    end

    test "turn_on sends command to DeviceManager", %{name: name, devices: devices} do
      expect(DeviceManagerMock, :command, fn n, :set_state, %{state: 1} ->
        assert n == devices.on_off_coil
        {:ok, :success}
      end)

      DungHor.turn_on(name)
      Process.sleep(50)

      status = DungHor.status(name)
      assert status.commanded_on == true
    end

    test "turn_off sends command to DeviceManager", %{name: name, pid: pid, devices: devices} do
      stub(DeviceManagerMock, :get_cached_data, fn
        n when n == devices.on_off_coil -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      send(pid, :data_refreshed)
      Process.sleep(50)

      expect(DeviceManagerMock, :command, fn n, :set_state, %{state: 0} ->
        assert n == devices.on_off_coil
        {:ok, :success}
      end)

      DungHor.turn_off(name)
      Process.sleep(50)

      status = DungHor.status(name)
      assert status.commanded_on == false
    end
  end
end

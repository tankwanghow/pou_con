defmodule PouCon.DeviceControllers.PumpControllerTest do
  use PouCon.DataCase
  import Mox

  alias PouCon.DeviceControllers.PumpController
  alias PouCon.DeviceManagerMock

  setup :verify_on_exit!

  setup do
    # Allow any process to use the mock
    Mox.set_mox_global(PouCon.DeviceManagerMock)

    # Create test device names with unique suffix
    id = System.unique_integer([:positive])
    device_names = %{
      on_off_coil: "test_pump_coil_#{id}",
      running_feedback: "test_pump_fb_#{id}",
      auto_manual: "test_pump_am_#{id}"
    }

    # Default stub: return 0 (OFF/AUTO) for everything
    stub(DeviceManagerMock, :get_cached_data, fn _name ->
      {:ok, %{state: 0}}
    end)

    stub(DeviceManagerMock, :command, fn _name, _cmd, _params ->
      {:ok, :success}
    end)

    %{devices: device_names}
  end

  describe "start/1 and initialization" do
    test "starts successfully with valid options", %{devices: devices} do
      opts = [
        name: "test_pump_1_#{System.unique_integer([:positive])}",
        title: "Test Pump 1",
        on_off_coil: devices.on_off_coil,
        running_feedback: devices.running_feedback,
        auto_manual: devices.auto_manual
      ]

      assert {:ok, pid} = PumpController.start(opts)
      assert Process.alive?(pid)
    end
  end

  describe "status/1" do
    setup %{devices: devices} do
      name = "test_pump_status_#{System.unique_integer([:positive])}"
      opts = [
        name: name,
        title: "Test Status Pump",
        on_off_coil: devices.on_off_coil,
        running_feedback: devices.running_feedback,
        auto_manual: devices.auto_manual
      ]

      {:ok, _pid} = PumpController.start(opts)
      %{name: name}
    end

    test "returns status map with all required fields", %{name: name} do
      status = PumpController.status(name)

      assert is_map(status)
      assert status.name == name
      assert status.commanded_on == false
      assert status.actual_on == false
      assert status.is_running == false
      assert status.mode == :auto
      assert status.error == nil
    end

    test "reflects state from DeviceManager", %{devices: devices} do
      name = "test_pump_state_#{System.unique_integer([:positive])}"

      # Stub specific values for this test
      stub(DeviceManagerMock, :get_cached_data, fn
        n when n == devices.on_off_coil -> {:ok, %{state: 1}}
        n when n == devices.running_feedback -> {:ok, %{state: 1}}
        n when n == devices.auto_manual -> {:ok, %{state: 1}} # Manual
        _ -> {:ok, %{state: 0}}
      end)

      opts = [
        name: name,
        on_off_coil: devices.on_off_coil,
        running_feedback: devices.running_feedback,
        auto_manual: devices.auto_manual
      ]

      {:ok, _pid} = PumpController.start(opts)
      Process.sleep(50)

      status = PumpController.status(name)
      assert status.actual_on == true
      assert status.is_running == true
      assert status.mode == :manual
    end

    test "returns error message when DeviceManager returns error", %{devices: devices} do
      name = "test_pump_error_#{System.unique_integer([:positive])}"

      stub(DeviceManagerMock, :get_cached_data, fn _ -> {:error, :timeout} end)

      opts = [
        name: name,
        on_off_coil: devices.on_off_coil,
        running_feedback: devices.running_feedback,
        auto_manual: devices.auto_manual
      ]

      {:ok, _pid} = PumpController.start(opts)
      Process.sleep(50)

      status = PumpController.status(name)
      assert status.error == :timeout
      assert status.error_message == "SENSOR TIMEOUT"
    end
  end

  describe "commands" do
    setup %{devices: devices} do
      name = "test_pump_cmd_#{System.unique_integer([:positive])}"
      opts = [
        name: name,
        on_off_coil: devices.on_off_coil,
        running_feedback: devices.running_feedback,
        auto_manual: devices.auto_manual
      ]

      {:ok, pid} = PumpController.start(opts)
      %{name: name, pid: pid}
    end

    test "turn_on sends command to DeviceManager", %{name: name, devices: devices} do
      expect(DeviceManagerMock, :command, fn n, :set_state, %{state: 1} ->
        assert n == devices.on_off_coil
        {:ok, :success}
      end)

      PumpController.turn_on(name)
      Process.sleep(50)

      status = PumpController.status(name)
      assert status.commanded_on == true
    end

    test "turn_off sends command to DeviceManager", %{name: name, pid: pid, devices: devices} do
      # Stub coil to be ON so actual_on becomes true
      stub(DeviceManagerMock, :get_cached_data, fn
        n when n == devices.on_off_coil -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      # Force update
      send(pid, :data_refreshed)
      Process.sleep(50)

      expect(DeviceManagerMock, :command, fn n, :set_state, %{state: 0} ->
        assert n == devices.on_off_coil
        {:ok, :success}
      end)

      PumpController.turn_off(name)
      Process.sleep(50)

      status = PumpController.status(name)
      assert status.commanded_on == false
    end

    test "set_manual sends command to DeviceManager", %{name: name, devices: devices} do
      expect(DeviceManagerMock, :command, fn n, :set_state, %{state: 1} ->
        assert n == devices.auto_manual
        {:ok, :success}
      end)

      PumpController.set_manual(name)
      Process.sleep(50)
    end

    test "set_auto sends command to DeviceManager", %{name: name, devices: devices} do
      expect(DeviceManagerMock, :command, fn n, :set_state, %{state: 0} ->
        assert n == devices.auto_manual
        {:ok, :success}
      end)

      PumpController.set_auto(name)
      Process.sleep(50)
    end
  end
end

defmodule PouCon.DeviceControllers.FanControllerTest do
  use PouCon.DataCase
  import Mox

  alias PouCon.DeviceControllers.FanController
  alias PouCon.DeviceManagerMock

  setup :verify_on_exit!

  setup do
    # Allow any process to use the mock
    Mox.set_mox_global(PouCon.DeviceManagerMock)

    # Create test device names with unique suffix
    id = System.unique_integer([:positive])

    device_names = %{
      on_off_coil: "test_fan_coil_#{id}",
      running_feedback: "test_fan_fb_#{id}",
      auto_manual: "test_fan_am_#{id}"
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
        name: "test_fan_1_#{System.unique_integer([:positive])}",
        title: "Test Fan 1",
        on_off_coil: devices.on_off_coil,
        running_feedback: devices.running_feedback,
        auto_manual: devices.auto_manual
      ]

      assert {:ok, pid} = FanController.start(opts)
      assert Process.alive?(pid)
    end

    test "starts but crashes in init when required :on_off_coil is missing", %{devices: devices} do
      opts = [
        name: "test_fan_missing_coil_#{System.unique_integer([:positive])}",
        running_feedback: devices.running_feedback,
        auto_manual: devices.auto_manual
      ]

      # We don't need to mock here because it crashes before calling DeviceManager
      # But if it did call, the global stub handles it.

      # Since it crashes in init, start returns {:error, ...} or crashes the caller if linked.
      # DynamicSupervisor.start_child handles the crash gracefully usually returning {:error, ...}
      # or {:ok, pid} then pid dies.

      result = FanController.start(opts)

      case result do
        {:ok, pid} ->
          Process.sleep(50)
          refute Process.alive?(pid)

        {:error, _} ->
          assert true
      end
    end
  end

  describe "status/1" do
    setup %{devices: devices} do
      name = "test_fan_status_#{System.unique_integer([:positive])}"

      opts = [
        name: name,
        title: "Test Status Fan",
        on_off_coil: devices.on_off_coil,
        running_feedback: devices.running_feedback,
        auto_manual: devices.auto_manual
      ]

      {:ok, _pid} = FanController.start(opts)
      %{name: name}
    end

    test "returns status map with all required fields", %{name: name} do
      status = FanController.status(name)

      assert is_map(status)
      assert status.name == name
      assert status.commanded_on == false
      assert status.actual_on == false
      assert status.is_running == false
      assert status.mode == :auto
      assert status.error == nil
    end

    test "reflects state from DeviceManager", %{devices: devices} do
      name = "test_fan_state_#{System.unique_integer([:positive])}"

      # Stub specific values for this test
      stub(DeviceManagerMock, :get_cached_data, fn
        n when n == devices.on_off_coil -> {:ok, %{state: 1}}
        n when n == devices.running_feedback -> {:ok, %{state: 1}}
        # Manual
        n when n == devices.auto_manual -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      opts = [
        name: name,
        on_off_coil: devices.on_off_coil,
        running_feedback: devices.running_feedback,
        auto_manual: devices.auto_manual
      ]

      {:ok, _pid} = FanController.start(opts)

      # Wait for init poll
      Process.sleep(50)

      status = FanController.status(name)
      assert status.actual_on == true
      assert status.is_running == true
      assert status.mode == :manual
    end

    test "returns error message when DeviceManager returns error", %{devices: devices} do
      name = "test_fan_error_#{System.unique_integer([:positive])}"

      # Stub error return
      stub(DeviceManagerMock, :get_cached_data, fn _ -> {:error, :timeout} end)

      opts = [
        name: name,
        on_off_coil: devices.on_off_coil,
        running_feedback: devices.running_feedback,
        auto_manual: devices.auto_manual
      ]

      {:ok, _pid} = FanController.start(opts)
      Process.sleep(50)

      status = FanController.status(name)
      assert status.error == :timeout
      assert status.error_message == "SENSOR TIMEOUT"
    end
  end

  describe "commands" do
    setup %{devices: devices} do
      name = "test_fan_cmd_#{System.unique_integer([:positive])}"

      opts = [
        name: name,
        on_off_coil: devices.on_off_coil,
        running_feedback: devices.running_feedback,
        auto_manual: devices.auto_manual
      ]

      {:ok, pid} = FanController.start(opts)
      %{name: name, pid: pid}
    end

    test "turn_on sends command to DeviceManager", %{name: name, devices: devices} do
      # Expect command call
      expect(DeviceManagerMock, :command, fn n, :set_state, %{state: 1} ->
        assert n == devices.on_off_coil
        {:ok, :success}
      end)

      FanController.turn_on(name)
      Process.sleep(50)

      status = FanController.status(name)
      assert status.commanded_on == true
    end

    test "turn_off sends command to DeviceManager", %{name: name, pid: pid, devices: devices} do
      # Stub coil to be ON so actual_on becomes true
      stub(DeviceManagerMock, :get_cached_data, fn
        n when n == devices.on_off_coil -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      # Force update to pick up the stubbed value
      send(pid, :data_refreshed)
      Process.sleep(50)

      # Now actual_on should be true. commanded_on is false (default).
      # Calling turn_off (commanded_on=false) will trigger command because 0 != 1.

      # Expect command call for OFF
      expect(DeviceManagerMock, :command, fn n, :set_state, %{state: 0} ->
        assert n == devices.on_off_coil
        {:ok, :success}
      end)

      FanController.turn_off(name)
      Process.sleep(50)

      status = FanController.status(name)
      assert status.commanded_on == false
    end

    test "set_manual sends command to DeviceManager", %{name: name, devices: devices} do
      expect(DeviceManagerMock, :command, fn n, :set_state, %{state: 1} ->
        assert n == devices.auto_manual
        {:ok, :success}
      end)

      FanController.set_manual(name)
      Process.sleep(50)
    end

    test "set_auto sends command to DeviceManager", %{name: name, devices: devices} do
      expect(DeviceManagerMock, :command, fn n, :set_state, %{state: 0} ->
        assert n == devices.auto_manual
        {:ok, :success}
      end)

      FanController.set_auto(name)
      Process.sleep(50)
    end
  end

  describe "error detection logic" do
    test "detects on_but_not_running", %{devices: devices} do
      name = "test_fan_logic_1_#{System.unique_integer([:positive])}"

      # Stub: Coil ON (1), Feedback OFF (0)
      stub(DeviceManagerMock, :get_cached_data, fn
        n when n == devices.on_off_coil -> {:ok, %{state: 1}}
        n when n == devices.running_feedback -> {:ok, %{state: 0}}
        _ -> {:ok, %{state: 0}}
      end)

      opts = [
        name: name,
        on_off_coil: devices.on_off_coil,
        running_feedback: devices.running_feedback,
        auto_manual: devices.auto_manual
      ]

      {:ok, _pid} = FanController.start(opts)
      Process.sleep(50)

      status = FanController.status(name)
      assert status.error == :on_but_not_running
      assert status.error_message == "ON BUT NOT RUNNING"
    end

    test "detects off_but_running", %{devices: devices} do
      name = "test_fan_logic_2_#{System.unique_integer([:positive])}"

      # Stub: Coil OFF (0), Feedback ON (1)
      stub(DeviceManagerMock, :get_cached_data, fn
        n when n == devices.on_off_coil -> {:ok, %{state: 0}}
        n when n == devices.running_feedback -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      opts = [
        name: name,
        on_off_coil: devices.on_off_coil,
        running_feedback: devices.running_feedback,
        auto_manual: devices.auto_manual
      ]

      {:ok, _pid} = FanController.start(opts)
      Process.sleep(50)

      status = FanController.status(name)
      assert status.error == :off_but_running
      assert status.error_message == "OFF BUT RUNNING"
    end
  end
end

defmodule PouCon.Equipment.Controllers.FanTest do
  use PouCon.DataCase
  import Mox

  alias PouCon.Equipment.Controllers.Fan
  alias PouCon.DataPointManagerMock

  setup :verify_on_exit!

  setup do
    # Allow any process to use the mock
    Mox.set_mox_global(PouCon.DataPointManagerMock)

    # Create test device names with unique suffix
    id = System.unique_integer([:positive])

    device_names = %{
      on_off_coil: "test_fan_coil_#{id}",
      running_feedback: "test_fan_fb_#{id}",
      auto_manual: "test_fan_am_#{id}"
    }

    # Default stub: return values for AUTO mode (DI = 1 for auto_manual)
    stub(DataPointManagerMock, :get_cached_data, fn
      n when n == device_names.auto_manual -> {:ok, %{state: 1}}
      _ -> {:ok, %{state: 0}}
    end)

    stub(DataPointManagerMock, :command, fn _name, _cmd, _params ->
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

      assert {:ok, pid} = Fan.start(opts)
      assert Process.alive?(pid)
    end

    test "starts but crashes in init when required :on_off_coil is missing", %{devices: devices} do
      opts = [
        name: "test_fan_missing_coil_#{System.unique_integer([:positive])}",
        running_feedback: devices.running_feedback,
        auto_manual: devices.auto_manual
      ]

      result = Fan.start(opts)

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

      {:ok, _pid} = Fan.start(opts)
      %{name: name}
    end

    test "returns status map with all required fields", %{name: name} do
      status = Fan.status(name)

      assert is_map(status)
      assert status.name == name
      assert status.commanded_on == false
      assert status.actual_on == false
      assert status.is_running == false
      # DI = 1 in default stub means AUTO mode
      assert status.mode == :auto
      assert status.error == nil
    end

    test "reflects state from DataPointManager - AUTO mode", %{devices: devices} do
      name = "test_fan_state_#{System.unique_integer([:positive])}"

      # Stub: Coil ON, Running ON, AUTO mode (DI = 1)
      stub(DataPointManagerMock, :get_cached_data, fn
        n when n == devices.on_off_coil -> {:ok, %{state: 1}}
        n when n == devices.running_feedback -> {:ok, %{state: 1}}
        n when n == devices.auto_manual -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      opts = [
        name: name,
        on_off_coil: devices.on_off_coil,
        running_feedback: devices.running_feedback,
        auto_manual: devices.auto_manual
      ]

      {:ok, _pid} = Fan.start(opts)
      Process.sleep(50)

      status = Fan.status(name)
      assert status.actual_on == true
      assert status.is_running == true
      assert status.mode == :auto
    end

    test "reflects state from DataPointManager - PANEL mode", %{devices: devices} do
      name = "test_fan_panel_#{System.unique_integer([:positive])}"

      # Stub: Panel mode (DI = 0 means physical switch not in AUTO)
      stub(DataPointManagerMock, :get_cached_data, fn
        n when n == devices.on_off_coil -> {:ok, %{state: 0}}
        n when n == devices.running_feedback -> {:ok, %{state: 1}}
        n when n == devices.auto_manual -> {:ok, %{state: 0}}
        _ -> {:ok, %{state: 0}}
      end)

      opts = [
        name: name,
        on_off_coil: devices.on_off_coil,
        running_feedback: devices.running_feedback,
        auto_manual: devices.auto_manual
      ]

      {:ok, _pid} = Fan.start(opts)
      Process.sleep(50)

      status = Fan.status(name)
      # DI = 0 means switch is in ON or OFF position (panel control)
      assert status.mode == :manual
      # Fan is running via physical switch bypass
      assert status.is_running == true
      # Coil is off (software not controlling)
      assert status.actual_on == false
      # No error in panel mode (mismatches are expected)
      assert status.error == nil
    end

    test "returns error message when DataPointManager returns error", %{devices: devices} do
      name = "test_fan_error_#{System.unique_integer([:positive])}"

      # Stub error return
      stub(DataPointManagerMock, :get_cached_data, fn _ -> {:error, :timeout} end)

      opts = [
        name: name,
        on_off_coil: devices.on_off_coil,
        running_feedback: devices.running_feedback,
        auto_manual: devices.auto_manual
      ]

      {:ok, _pid} = Fan.start(opts)
      Process.sleep(50)

      status = Fan.status(name)
      assert status.error == :timeout
      assert status.error_message == "SENSOR TIMEOUT"
    end
  end

  describe "commands in AUTO mode" do
    setup %{devices: devices} do
      name = "test_fan_cmd_#{System.unique_integer([:positive])}"

      # Ensure AUTO mode (DI = 1)
      stub(DataPointManagerMock, :get_cached_data, fn
        n when n == devices.auto_manual -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      opts = [
        name: name,
        on_off_coil: devices.on_off_coil,
        running_feedback: devices.running_feedback,
        auto_manual: devices.auto_manual
      ]

      {:ok, pid} = Fan.start(opts)
      Process.sleep(50)
      %{name: name, pid: pid}
    end

    test "turn_on sends command to DataPointManager in AUTO mode", %{name: name, devices: devices} do
      # Expect command call for ON
      expect(DataPointManagerMock, :command, fn n, :set_state, %{state: 1} ->
        assert n == devices.on_off_coil
        {:ok, :success}
      end)

      Fan.turn_on(name)
      Process.sleep(50)

      status = Fan.status(name)
      assert status.commanded_on == true
    end

    test "turn_off sends command to DataPointManager in AUTO mode", %{
      name: name,
      pid: pid,
      devices: devices
    } do
      # Stub coil to be ON so actual_on becomes true
      stub(DataPointManagerMock, :get_cached_data, fn
        n when n == devices.on_off_coil -> {:ok, %{state: 1}}
        n when n == devices.auto_manual -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      # Force update to pick up the stubbed value
      send(pid, :data_refreshed)
      Process.sleep(50)

      # Expect command call for OFF
      expect(DataPointManagerMock, :command, fn n, :set_state, %{state: 0} ->
        assert n == devices.on_off_coil
        {:ok, :success}
      end)

      Fan.turn_off(name)
      Process.sleep(50)

      status = Fan.status(name)
      assert status.commanded_on == false
    end
  end

  describe "commands ignored in PANEL mode" do
    setup %{devices: devices} do
      name = "test_fan_panel_cmd_#{System.unique_integer([:positive])}"

      # Panel mode (DI = 0)
      stub(DataPointManagerMock, :get_cached_data, fn
        n when n == devices.auto_manual -> {:ok, %{state: 0}}
        _ -> {:ok, %{state: 0}}
      end)

      opts = [
        name: name,
        on_off_coil: devices.on_off_coil,
        running_feedback: devices.running_feedback,
        auto_manual: devices.auto_manual
      ]

      {:ok, pid} = Fan.start(opts)
      Process.sleep(50)
      %{name: name, pid: pid}
    end

    test "turn_on is ignored in PANEL mode", %{name: name} do
      # No command should be sent
      Fan.turn_on(name)
      Process.sleep(50)

      status = Fan.status(name)
      # commanded_on should still be false (command was ignored)
      assert status.commanded_on == false
      assert status.mode == :manual
    end

    test "turn_off is ignored in PANEL mode", %{name: name} do
      # No command should be sent
      Fan.turn_off(name)
      Process.sleep(50)

      status = Fan.status(name)
      assert status.commanded_on == false
      assert status.mode == :manual
    end
  end

  describe "error detection logic in AUTO mode" do
    test "detects on_but_not_running" do
      id = System.unique_integer([:positive])
      name = "test_fan_logic_1_#{id}"
      coil = "test_coil_#{id}"
      fb = "test_fb_#{id}"
      am = "test_am_#{id}"

      # Stub: Coil ON (1), Feedback OFF (0), AUTO mode (DI = 1)
      stub(DataPointManagerMock, :get_cached_data, fn
        n when n == coil -> {:ok, %{state: 1}}
        n when n == fb -> {:ok, %{state: 0}}
        n when n == am -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      opts = [
        name: name,
        on_off_coil: coil,
        running_feedback: fb,
        auto_manual: am
      ]

      {:ok, _pid} = Fan.start(opts)
      Process.sleep(50)

      status = Fan.status(name)
      assert status.error == :on_but_not_running
      assert status.error_message == "ON BUT NOT RUNNING"
    end

    test "detects off_but_running" do
      id = System.unique_integer([:positive])
      name = "test_fan_logic_2_#{id}"
      coil = "test_coil_#{id}"
      fb = "test_fb_#{id}"
      am = "test_am_#{id}"

      # Stub: Coil OFF (0), Feedback ON (1), AUTO mode (DI = 1)
      stub(DataPointManagerMock, :get_cached_data, fn
        n when n == coil -> {:ok, %{state: 0}}
        n when n == fb -> {:ok, %{state: 1}}
        n when n == am -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      opts = [
        name: name,
        on_off_coil: coil,
        running_feedback: fb,
        auto_manual: am
      ]

      {:ok, _pid} = Fan.start(opts)
      Process.sleep(50)

      status = Fan.status(name)
      assert status.error == :off_but_running
      assert status.error_message == "OFF BUT RUNNING"
    end
  end

  describe "error detection skipped in PANEL mode" do
    test "no error when coil off but running in PANEL mode" do
      id = System.unique_integer([:positive])
      name = "test_fan_panel_error_#{id}"
      coil = "test_coil_#{id}"
      fb = "test_fb_#{id}"
      am = "test_am_#{id}"

      # Stub: Coil OFF (0), Feedback ON (1), PANEL mode (DI = 0)
      # This would be an error in AUTO mode, but is normal in PANEL mode
      # (physical switch bypasses the relay)
      stub(DataPointManagerMock, :get_cached_data, fn
        n when n == coil -> {:ok, %{state: 0}}
        n when n == fb -> {:ok, %{state: 1}}
        n when n == am -> {:ok, %{state: 0}}
        _ -> {:ok, %{state: 0}}
      end)

      opts = [
        name: name,
        on_off_coil: coil,
        running_feedback: fb,
        auto_manual: am
      ]

      {:ok, _pid} = Fan.start(opts)
      Process.sleep(50)

      status = Fan.status(name)
      # No error - this is expected in PANEL mode (physical switch ON)
      assert status.error == nil
      assert status.mode == :manual
      assert status.is_running == true
    end
  end
end

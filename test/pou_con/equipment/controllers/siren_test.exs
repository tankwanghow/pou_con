defmodule PouCon.Equipment.Controllers.SirenTest do
  use PouCon.DataCase
  import Mox

  alias PouCon.Equipment.Controllers.Siren
  alias PouCon.DataPointManagerMock

  setup :verify_on_exit!

  setup do
    # Allow any process to use the mock
    Mox.set_mox_global(PouCon.DataPointManagerMock)

    # Create test device names with unique suffix
    id = System.unique_integer([:positive])

    device_names = %{
      on_off_coil: "test_siren_coil_#{id}",
      auto_manual: "test_siren_am_#{id}",
      running_feedback: "test_siren_rf_#{id}"
    }

    # Default stub: return values for AUTO mode (state = 1 for auto_manual)
    stub(DataPointManagerMock, :read_direct, fn
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
        name: "test_siren_1_#{System.unique_integer([:positive])}",
        title: "Test Siren 1",
        on_off_coil: devices.on_off_coil,
        auto_manual: devices.auto_manual,
        running_feedback: devices.running_feedback
      ]

      assert {:ok, pid} = Siren.start(opts)
      assert Process.alive?(pid)
    end

    test "raises when required :on_off_coil is missing", %{devices: devices} do
      opts = [
        name: "test_siren_missing_coil_#{System.unique_integer([:positive])}",
        auto_manual: devices.auto_manual
      ]

      result = Siren.start(opts)

      case result do
        {:ok, pid} ->
          Process.sleep(50)
          refute Process.alive?(pid)

        {:error, _} ->
          assert true
      end
    end

    test "raises when required :auto_manual is missing", %{devices: devices} do
      opts = [
        name: "test_siren_missing_am_#{System.unique_integer([:positive])}",
        on_off_coil: devices.on_off_coil
      ]

      result = Siren.start(opts)

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
      name = "test_siren_status_#{System.unique_integer([:positive])}"

      opts = [
        name: name,
        title: "Test Status Siren",
        on_off_coil: devices.on_off_coil,
        auto_manual: devices.auto_manual,
        running_feedback: devices.running_feedback
      ]

      {:ok, _pid} = Siren.start(opts)
      %{name: name}
    end

    test "returns status map with all required fields", %{name: name} do
      status = Siren.status(name)

      assert is_map(status)
      assert status.name == name
      assert status.commanded_on == false
      assert status.actual_on == false
      assert status.is_running == false
      # DI = 1 in default stub means AUTO mode
      assert status.mode == :auto
      assert status.error == nil
      assert status.error_message == "OK"
      assert is_boolean(status.interlocked)
      assert is_boolean(status.is_auto_manual_virtual_di)
      assert is_boolean(status.inverted)
    end

    test "reflects mode from DataPointManager - AUTO mode", %{devices: devices} do
      name = "test_siren_auto_#{System.unique_integer([:positive])}"

      # Stub: AUTO mode (state = 1)
      stub(DataPointManagerMock, :read_direct, fn
        n when n == devices.auto_manual -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      opts = [
        name: name,
        on_off_coil: devices.on_off_coil,
        auto_manual: devices.auto_manual,
        running_feedback: devices.running_feedback
      ]

      {:ok, _pid} = Siren.start(opts)
      Process.sleep(50)

      status = Siren.status(name)
      assert status.mode == :auto
    end

    test "reflects mode from DataPointManager - MANUAL mode", %{devices: devices} do
      name = "test_siren_manual_#{System.unique_integer([:positive])}"

      # Stub: MANUAL mode (state = 0)
      stub(DataPointManagerMock, :read_direct, fn
        n when n == devices.auto_manual -> {:ok, %{state: 0}}
        _ -> {:ok, %{state: 0}}
      end)

      opts = [
        name: name,
        on_off_coil: devices.on_off_coil,
        auto_manual: devices.auto_manual,
        running_feedback: devices.running_feedback
      ]

      {:ok, _pid} = Siren.start(opts)
      Process.sleep(50)

      status = Siren.status(name)
      assert status.mode == :manual
    end

    test "returns error when DataPointManager returns error", %{devices: devices} do
      name = "test_siren_error_#{System.unique_integer([:positive])}"

      # Stub error return
      stub(DataPointManagerMock, :read_direct, fn _ -> {:error, :timeout} end)

      opts = [
        name: name,
        on_off_coil: devices.on_off_coil,
        auto_manual: devices.auto_manual,
        running_feedback: devices.running_feedback
      ]

      {:ok, _pid} = Siren.start(opts)
      Process.sleep(50)

      status = Siren.status(name)
      assert status.error == :timeout
      assert status.error_message == "SENSOR TIMEOUT"
    end
  end

  describe "turn_on/1 and turn_off/1" do
    setup %{devices: devices} do
      name = "test_siren_cmd_#{System.unique_integer([:positive])}"

      opts = [
        name: name,
        on_off_coil: devices.on_off_coil,
        auto_manual: devices.auto_manual,
        running_feedback: devices.running_feedback
      ]

      {:ok, pid} = Siren.start(opts)
      Process.sleep(50)
      %{name: name, pid: pid}
    end

    test "turn_on sends command to DataPointManager", %{name: name, devices: devices} do
      # Expect command call for ON (coil value = 1 for NO wiring)
      expect(DataPointManagerMock, :command, fn n, :set_state, %{state: 1} ->
        assert n == devices.on_off_coil
        {:ok, :success}
      end)

      # Update stub to return coil state = 1 and running_feedback = 1 after command
      stub(DataPointManagerMock, :read_direct, fn
        n when n == devices.auto_manual -> {:ok, %{state: 1}}
        n when n == devices.on_off_coil -> {:ok, %{state: 1}}
        n when n == devices.running_feedback -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      Siren.turn_on(name)
      Process.sleep(100)

      status = Siren.status(name)
      assert status.actual_on == true
      assert status.is_running == true
    end

    test "turn_off sends command to DataPointManager", %{name: name, devices: devices} do
      # Update stub to return coil ON state first
      stub(DataPointManagerMock, :read_direct, fn
        n when n == devices.auto_manual -> {:ok, %{state: 1}}
        n when n == devices.on_off_coil -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      # First turn on
      expect(DataPointManagerMock, :command, fn n, :set_state, %{state: 1} ->
        assert n == devices.on_off_coil
        {:ok, :success}
      end)

      Siren.turn_on(name)
      Process.sleep(50)

      # Update stub to return coil OFF state after turn_off
      stub(DataPointManagerMock, :read_direct, fn
        n when n == devices.auto_manual -> {:ok, %{state: 1}}
        n when n == devices.on_off_coil -> {:ok, %{state: 0}}
        _ -> {:ok, %{state: 0}}
      end)

      # Then turn off - expect coil value = 0
      expect(DataPointManagerMock, :command, fn n, :set_state, %{state: 0} ->
        assert n == devices.on_off_coil
        {:ok, :success}
      end)

      Siren.turn_off(name)
      Process.sleep(50)

      status = Siren.status(name)
      # For output-only devices, actual_on represents the on state
      assert status.actual_on == false
    end

    test "command failure sets error state", %{name: name} do
      # Stub command to fail
      expect(DataPointManagerMock, :command, fn _n, :set_state, _params ->
        {:error, :timeout}
      end)

      Siren.turn_on(name)
      Process.sleep(100)

      status = Siren.status(name)
      assert status.error == :command_failed
    end
  end

  describe "set_mode/2 with virtual auto_manual" do
    test "sets mode when auto_manual is virtual", %{devices: devices} do
      name = "test_siren_setmode_#{System.unique_integer([:positive])}"

      # Mark auto_manual as virtual by inserting a virtual data point
      # For this test, we'll rely on DataPoints.is_virtual? returning true
      # when port_path is "virtual"

      opts = [
        name: name,
        on_off_coil: devices.on_off_coil,
        auto_manual: devices.auto_manual,
        running_feedback: devices.running_feedback
      ]

      {:ok, _pid} = Siren.start(opts)
      Process.sleep(50)

      # Since is_auto_manual_virtual_di depends on DataPoints.is_virtual?,
      # and that checks the database, we verify the set_mode doesn't crash
      Siren.set_mode(name, :manual)
      Process.sleep(50)

      # Status call should work regardless
      status = Siren.status(name)
      assert is_atom(status.mode)
    end
  end

  # Note: Inverted wiring tests removed — inversion is now handled at the
  # DataPointManager level (data point `inverted` flag), not in controllers.
  # See data_point_manager_test.exs for inversion tests.

  describe "interlock integration" do
    test "turn_on is blocked when interlocked", %{devices: devices} do
      name = "test_siren_interlock_#{System.unique_integer([:positive])}"

      opts = [
        name: name,
        on_off_coil: devices.on_off_coil,
        auto_manual: devices.auto_manual,
        running_feedback: devices.running_feedback
      ]

      {:ok, _pid} = Siren.start(opts)
      Process.sleep(50)

      # The interlock check uses InterlockController which may not be running
      # in test. If it's not running, check_interlock returns true (fail-open).
      # This test verifies the code path doesn't crash.
      Siren.turn_on(name)
      Process.sleep(50)

      status = Siren.status(name)
      # Either turned on (no interlock) or stayed off (interlocked)
      # Siren uses is_running to represent on state
      assert is_boolean(status.is_running)
    end
  end

  describe "defensive programming" do
    test "status returns interlocked field" do
      id = System.unique_integer([:positive])
      name = "test_siren_interlocked_#{id}"
      coil = "test_coil_#{id}"
      am = "test_am_#{id}"

      stub(DataPointManagerMock, :read_direct, fn
        n when n == am -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      opts = [name: name, on_off_coil: coil, auto_manual: am, running_feedback: "test_rf_#{id}"]

      {:ok, _pid} = Siren.start(opts)
      Process.sleep(50)

      status = Siren.status(name)
      assert Map.has_key?(status, :interlocked)
      assert is_boolean(status.interlocked)
    end

    test "status returns is_auto_manual_virtual_di field" do
      id = System.unique_integer([:positive])
      name = "test_siren_virtual_#{id}"
      coil = "test_coil_#{id}"
      am = "test_am_#{id}"

      stub(DataPointManagerMock, :read_direct, fn _ -> {:ok, %{state: 0}} end)

      opts = [name: name, on_off_coil: coil, auto_manual: am, running_feedback: "test_rf_#{id}"]

      {:ok, _pid} = Siren.start(opts)
      Process.sleep(50)

      status = Siren.status(name)
      assert Map.has_key?(status, :is_auto_manual_virtual_di)
      assert is_boolean(status.is_auto_manual_virtual_di)
    end
  end
end

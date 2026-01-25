defmodule PouCon.Equipment.Controllers.PowerIndicatorTest do
  use PouCon.DataCase
  import Mox

  alias PouCon.Equipment.Controllers.PowerIndicator
  alias PouCon.DataPointManagerMock

  setup :verify_on_exit!

  setup do
    Mox.set_mox_global(PouCon.DataPointManagerMock)

    id = System.unique_integer([:positive])

    device_names = %{
      indicator: "test_power_indicator_#{id}"
    }

    # Default stub: return power OFF
    stub(DataPointManagerMock, :read_direct, fn _ -> {:ok, %{state: 0}} end)

    %{devices: device_names}
  end

  describe "start/1 and initialization" do
    test "starts successfully with valid options", %{devices: devices} do
      opts = [
        name: "test_indicator_1_#{System.unique_integer([:positive])}",
        title: "Test MCCB Status",
        indicator: devices.indicator
      ]

      assert {:ok, pid} = PowerIndicator.start(opts)
      assert Process.alive?(pid)
    end

    test "fails gracefully when :indicator is missing" do
      opts = [
        name: "test_indicator_missing_#{System.unique_integer([:positive])}",
        title: "Test Missing Indicator"
      ]

      result = PowerIndicator.start(opts)

      case result do
        {:ok, pid} ->
          Process.sleep(50)
          refute Process.alive?(pid)

        {:error, {:missing_config, :indicator}} ->
          assert true
      end
    end
  end

  describe "status/1" do
    setup %{devices: devices} do
      name = "test_indicator_status_#{System.unique_integer([:positive])}"

      opts = [
        name: name,
        title: "Test Status Indicator",
        indicator: devices.indicator
      ]

      {:ok, _pid} = PowerIndicator.start(opts)
      Process.sleep(50)
      %{name: name}
    end

    test "returns status map with all required fields", %{name: name} do
      status = PowerIndicator.status(name)

      assert is_map(status)
      assert status.name == name
      assert Map.has_key?(status, :is_on)
      assert Map.has_key?(status, :is_running)
      assert Map.has_key?(status, :error)
      assert Map.has_key?(status, :error_message)
    end

    test "reports power OFF when indicator state is 0", %{name: name} do
      status = PowerIndicator.status(name)

      assert status.is_on == false
      assert status.is_running == false
      assert status.error == nil
    end

    test "reports power ON when indicator state is 1", %{devices: devices} do
      name = "test_indicator_on_#{System.unique_integer([:positive])}"

      stub(DataPointManagerMock, :read_direct, fn _ -> {:ok, %{state: 1}} end)

      opts = [
        name: name,
        indicator: devices.indicator
      ]

      {:ok, _pid} = PowerIndicator.start(opts)
      Process.sleep(50)

      status = PowerIndicator.status(name)
      assert status.is_on == true
      assert status.is_running == true
    end
  end

  describe "error handling" do
    test "detects timeout when indicator read fails", %{devices: devices} do
      name = "test_indicator_timeout_#{System.unique_integer([:positive])}"

      stub(DataPointManagerMock, :read_direct, fn _ -> {:error, :timeout} end)

      opts = [
        name: name,
        indicator: devices.indicator
      ]

      {:ok, _pid} = PowerIndicator.start(opts)
      Process.sleep(50)

      status = PowerIndicator.status(name)
      assert status.error == :timeout
      assert status.error_message == "OFFLINE"
    end

    test "detects invalid data format", %{devices: devices} do
      name = "test_indicator_invalid_#{System.unique_integer([:positive])}"

      # Return unexpected data format
      stub(DataPointManagerMock, :read_direct, fn _ -> {:ok, "invalid"} end)

      opts = [
        name: name,
        indicator: devices.indicator
      ]

      {:ok, _pid} = PowerIndicator.start(opts)
      Process.sleep(50)

      status = PowerIndicator.status(name)
      assert status.error == :invalid_data
      assert status.error_message == "INVALID DATA"
    end
  end

  describe "polling behavior" do
    test "updates status on subsequent polls", %{devices: devices} do
      name = "test_indicator_poll_#{System.unique_integer([:positive])}"

      # Start with power OFF
      stub(DataPointManagerMock, :read_direct, fn _ -> {:ok, %{state: 0}} end)

      opts = [
        name: name,
        indicator: devices.indicator,
        poll_interval_ms: 100
      ]

      {:ok, pid} = PowerIndicator.start(opts)
      Process.sleep(50)

      status1 = PowerIndicator.status(name)
      assert status1.is_on == false

      # Update to power ON
      stub(DataPointManagerMock, :read_direct, fn _ -> {:ok, %{state: 1}} end)

      # Trigger poll
      send(pid, :poll)
      Process.sleep(50)

      status2 = PowerIndicator.status(name)
      assert status2.is_on == true
    end

    test "transitions from timeout to normal when connection restored", %{devices: devices} do
      name = "test_indicator_recovery_#{System.unique_integer([:positive])}"

      # Start with timeout
      stub(DataPointManagerMock, :read_direct, fn _ -> {:error, :timeout} end)

      opts = [
        name: name,
        indicator: devices.indicator,
        poll_interval_ms: 100
      ]

      {:ok, pid} = PowerIndicator.start(opts)
      Process.sleep(50)

      status1 = PowerIndicator.status(name)
      assert status1.error == :timeout

      # Restore connection
      stub(DataPointManagerMock, :read_direct, fn _ -> {:ok, %{state: 1}} end)

      send(pid, :poll)
      Process.sleep(50)

      status2 = PowerIndicator.status(name)
      assert status2.error == nil
      assert status2.is_on == true
    end
  end

  describe "read-only behavior" do
    test "has no turn_on function" do
      refute function_exported?(PowerIndicator, :turn_on, 1)
    end

    test "has no turn_off function" do
      refute function_exported?(PowerIndicator, :turn_off, 1)
    end

    test "has no set_mode function" do
      refute function_exported?(PowerIndicator, :set_mode, 2)
    end
  end
end

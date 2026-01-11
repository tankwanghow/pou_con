defmodule PouCon.Equipment.Controllers.WaterMeterTest do
  use PouCon.DataCase
  import Mox

  alias PouCon.Equipment.Controllers.WaterMeter
  alias PouCon.DeviceManagerMock

  setup :verify_on_exit!

  @valid_meter_data %{
    positive_flow: 1234.56,
    negative_flow: 12.34,
    flow_rate: 2.5,
    remaining_flow: 500.0,
    pipe_status: "full",
    valve_status: %{open: true, closed: false, abnormal: false, low_battery: false},
    pressure: 0.35,
    temperature: 22.5,
    battery_voltage: 3.6
  }

  setup do
    Mox.set_mox_global(PouCon.DeviceManagerMock)

    id = System.unique_integer([:positive])

    device_names = %{
      meter: "water_meter_#{id}"
    }

    stub(DeviceManagerMock, :get_cached_data, fn _name ->
      {:ok, @valid_meter_data}
    end)

    %{devices: device_names}
  end

  describe "start/1" do
    test "starts successfully", %{devices: devices} do
      opts = [
        name: "test_wm_#{System.unique_integer([:positive])}",
        title: "Test Water Meter",
        meter: devices.meter
      ]

      assert {:ok, pid} = WaterMeter.start(opts)
      assert Process.alive?(pid)
    end

    test "fails to start when :meter is missing" do
      # Trap exits so we don't crash the test process
      Process.flag(:trap_exit, true)

      opts = [
        name: "test_wm_no_meter_#{System.unique_integer([:positive])}",
        title: "Test Water Meter"
      ]

      # GenServer.start_link returns {:error, reason} when init/1 raises
      # With trap_exit, we get the result instead of crashing
      result = WaterMeter.start_link(opts)

      # The process should fail to start with an error
      assert {:error, reason} = result
      # The reason contains the RuntimeError
      assert match?({%RuntimeError{}, _stacktrace}, reason) or
               match?({{%RuntimeError{}, _stacktrace}, _}, reason)
    end

    test "returns existing pid if already started", %{devices: devices} do
      name = "test_wm_existing_#{System.unique_integer([:positive])}"

      opts = [
        name: name,
        title: "Test Water Meter",
        meter: devices.meter
      ]

      {:ok, pid1} = WaterMeter.start(opts)
      {:ok, pid2} = WaterMeter.start(opts)

      assert pid1 == pid2
    end
  end

  describe "status/1" do
    setup %{devices: devices} do
      name = "test_wm_status_#{System.unique_integer([:positive])}"

      opts = [
        name: name,
        title: "Test Status WM",
        meter: devices.meter
      ]

      {:ok, _pid} = WaterMeter.start(opts)
      %{name: name}
    end

    test "returns status map with all fields", %{name: name} do
      status = WaterMeter.status(name)

      assert is_map(status)
      assert status.name == name
      assert status.title == "Test Status WM"

      # Flow data
      assert status.positive_flow == 1234.56
      assert status.negative_flow == 12.34
      assert status.flow_rate == 2.5
      assert status.remaining_flow == 500.0

      # Status data
      assert status.pipe_status == :full

      assert status.valve_status == %{
               open: true,
               closed: false,
               abnormal: false,
               low_battery: false
             }

      # Optional sensors
      assert status.pressure == 0.35
      assert status.temperature == 22.5
      assert status.battery_voltage == 3.6

      # Error state
      assert status.error == nil
      assert status.error_message == "OK"
    end
  end

  describe "pipe_status normalization" do
    test "normalizes 'empty' string to :empty atom", %{devices: devices} do
      name = "test_wm_empty_#{System.unique_integer([:positive])}"

      stub(DeviceManagerMock, :get_cached_data, fn _ ->
        {:ok, %{@valid_meter_data | pipe_status: "empty"}}
      end)

      opts = [name: name, meter: devices.meter]
      {:ok, _pid} = WaterMeter.start(opts)

      status = WaterMeter.status(name)
      assert status.pipe_status == :empty
    end

    test "normalizes 'full' string to :full atom", %{devices: devices} do
      name = "test_wm_full_#{System.unique_integer([:positive])}"

      stub(DeviceManagerMock, :get_cached_data, fn _ ->
        {:ok, %{@valid_meter_data | pipe_status: "full"}}
      end)

      opts = [name: name, meter: devices.meter]
      {:ok, _pid} = WaterMeter.start(opts)

      status = WaterMeter.status(name)
      assert status.pipe_status == :full
    end

    test "normalizes unknown value to :unknown atom", %{devices: devices} do
      name = "test_wm_unknown_#{System.unique_integer([:positive])}"

      stub(DeviceManagerMock, :get_cached_data, fn _ ->
        {:ok, %{@valid_meter_data | pipe_status: 42}}
      end)

      opts = [name: name, meter: devices.meter]
      {:ok, _pid} = WaterMeter.start(opts)

      status = WaterMeter.status(name)
      assert status.pipe_status == :unknown
    end

    test "handles nil pipe_status", %{devices: devices} do
      name = "test_wm_nil_pipe_#{System.unique_integer([:positive])}"

      stub(DeviceManagerMock, :get_cached_data, fn _ ->
        {:ok, %{@valid_meter_data | pipe_status: nil}}
      end)

      opts = [name: name, meter: devices.meter]
      {:ok, _pid} = WaterMeter.start(opts)

      status = WaterMeter.status(name)
      assert status.pipe_status == :unknown
    end
  end

  describe "error handling" do
    test "handles timeout error", %{devices: devices} do
      name = "test_wm_timeout_#{System.unique_integer([:positive])}"

      stub(DeviceManagerMock, :get_cached_data, fn _ -> {:error, :timeout} end)

      opts = [name: name, meter: devices.meter]
      {:ok, _pid} = WaterMeter.start(opts)
      Process.sleep(50)

      status = WaterMeter.status(name)
      assert status.error == :timeout
      assert status.error_message == "METER TIMEOUT"

      # All readings should be cleared
      assert status.positive_flow == nil
      assert status.flow_rate == nil
      assert status.pipe_status == nil
    end

    test "handles invalid data - missing flow_rate", %{devices: devices} do
      name = "test_wm_invalid_#{System.unique_integer([:positive])}"

      stub(DeviceManagerMock, :get_cached_data, fn _ ->
        {:ok, %{positive_flow: 100.0, pipe_status: "full"}}
      end)

      opts = [name: name, meter: devices.meter]
      {:ok, _pid} = WaterMeter.start(opts)
      Process.sleep(50)

      status = WaterMeter.status(name)
      assert status.error == :invalid_data
      assert status.error_message == "INVALID METER DATA"
    end

    test "handles unexpected result format", %{devices: devices} do
      name = "test_wm_unexpected_#{System.unique_integer([:positive])}"

      stub(DeviceManagerMock, :get_cached_data, fn _ -> "not a valid response" end)

      opts = [name: name, meter: devices.meter]
      {:ok, _pid} = WaterMeter.start(opts)
      Process.sleep(50)

      status = WaterMeter.status(name)
      assert status.error == :invalid_data
    end

    test "clears error when data becomes valid again", %{devices: devices} do
      name = "test_wm_recovery_#{System.unique_integer([:positive])}"

      # Start with error
      stub(DeviceManagerMock, :get_cached_data, fn _ -> {:error, :timeout} end)

      opts = [name: name, meter: devices.meter]
      {:ok, pid} = WaterMeter.start(opts)
      Process.sleep(50)

      status = WaterMeter.status(name)
      assert status.error == :timeout

      # Recover with valid data
      stub(DeviceManagerMock, :get_cached_data, fn _ -> {:ok, @valid_meter_data} end)

      # Trigger refresh via PubSub
      send(pid, :data_refreshed)
      Process.sleep(50)

      status = WaterMeter.status(name)
      assert status.error == nil
      assert status.flow_rate == 2.5
    end
  end

  describe "optional sensor data" do
    test "handles missing optional sensors gracefully", %{devices: devices} do
      name = "test_wm_minimal_#{System.unique_integer([:positive])}"

      # Minimal data - only required flow_rate
      stub(DeviceManagerMock, :get_cached_data, fn _ ->
        {:ok, %{flow_rate: 1.5, pipe_status: "full"}}
      end)

      opts = [name: name, meter: devices.meter]
      {:ok, _pid} = WaterMeter.start(opts)

      status = WaterMeter.status(name)
      assert status.error == nil
      assert status.flow_rate == 1.5

      # Optional fields are nil
      assert status.pressure == nil
      assert status.temperature == nil
      assert status.battery_voltage == nil
    end

    test "handles non-numeric values in optional fields", %{devices: devices} do
      name = "test_wm_non_numeric_#{System.unique_integer([:positive])}"

      stub(DeviceManagerMock, :get_cached_data, fn _ ->
        {:ok,
         %{
           flow_rate: 1.5,
           pipe_status: "full",
           pressure: "invalid",
           temperature: nil,
           battery_voltage: :not_a_number
         }}
      end)

      opts = [name: name, meter: devices.meter]
      {:ok, _pid} = WaterMeter.start(opts)

      status = WaterMeter.status(name)
      assert status.error == nil
      assert status.flow_rate == 1.5

      # Non-numeric values become nil
      assert status.pressure == nil
      assert status.temperature == nil
      assert status.battery_voltage == nil
    end
  end

  describe "valve_status passthrough" do
    test "passes valve_status map through unchanged", %{devices: devices} do
      name = "test_wm_valve_#{System.unique_integer([:positive])}"

      valve_status = %{
        open: false,
        closed: true,
        abnormal: true,
        low_battery: true
      }

      stub(DeviceManagerMock, :get_cached_data, fn _ ->
        {:ok, %{@valid_meter_data | valve_status: valve_status}}
      end)

      opts = [name: name, meter: devices.meter]
      {:ok, _pid} = WaterMeter.start(opts)

      status = WaterMeter.status(name)
      assert status.valve_status == valve_status
    end
  end
end

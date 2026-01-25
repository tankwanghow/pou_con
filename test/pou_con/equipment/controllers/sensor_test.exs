defmodule PouCon.Equipment.Controllers.SensorTest do
  use PouCon.DataCase
  import Mox

  alias PouCon.Equipment.Controllers.Sensor
  alias PouCon.DataPointManagerMock

  setup :verify_on_exit!

  setup do
    Mox.set_mox_global(PouCon.DataPointManagerMock)

    id = System.unique_integer([:positive])

    device_names = %{
      temperature: "test_temp_sensor_#{id}",
      humidity: "test_hum_sensor_#{id}",
      co2: "test_co2_sensor_#{id}"
    }

    # Default stub: return numeric values
    stub(DataPointManagerMock, :read_direct, fn
      n when n == device_names.temperature -> {:ok, %{value: 25.5, color_zones: []}}
      n when n == device_names.humidity -> {:ok, %{value: 65.0, color_zones: []}}
      n when n == device_names.co2 -> {:ok, %{value: 800, color_zones: []}}
      _ -> {:ok, %{value: 0, color_zones: []}}
    end)

    %{devices: device_names}
  end

  describe "start/1 and initialization" do
    test "starts successfully with valid single data point", %{devices: devices} do
      opts = [
        name: "test_sensor_single_#{System.unique_integer([:positive])}",
        title: "Test Temperature",
        temperature: devices.temperature
      ]

      assert {:ok, pid} = Sensor.start(opts)
      assert Process.alive?(pid)
    end

    test "starts successfully with multiple data points", %{devices: devices} do
      opts = [
        name: "test_sensor_multi_#{System.unique_integer([:positive])}",
        title: "Test Multi Sensor",
        temperature: devices.temperature,
        humidity: devices.humidity,
        co2: devices.co2
      ]

      assert {:ok, pid} = Sensor.start(opts)
      assert Process.alive?(pid)
    end

    test "fails gracefully when no data points configured" do
      opts = [
        name: "test_sensor_empty_#{System.unique_integer([:positive])}",
        title: "Test Empty Sensor"
      ]

      result = Sensor.start(opts)

      case result do
        {:ok, pid} ->
          Process.sleep(50)
          refute Process.alive?(pid)

        {:error, {:missing_config, :data_points, _}} ->
          assert true
      end
    end
  end

  describe "status/1" do
    setup %{devices: devices} do
      name = "test_sensor_status_#{System.unique_integer([:positive])}"

      opts = [
        name: name,
        title: "Test Status Sensor",
        temperature: devices.temperature,
        humidity: devices.humidity
      ]

      {:ok, _pid} = Sensor.start(opts)
      Process.sleep(50)
      %{name: name}
    end

    test "returns status map with all required fields", %{name: name} do
      status = Sensor.status(name)

      assert is_map(status)
      assert status.name == name
      assert status.error == nil
      assert status.error_message == "OK"
      assert Map.has_key?(status, :thresholds)
    end

    test "includes all configured data point values in status", %{name: name} do
      status = Sensor.status(name)

      assert status.temperature == 25.5
      assert status.humidity == 65.0
    end

    test "includes thresholds for each configured data point", %{name: name} do
      status = Sensor.status(name)

      assert is_map(status.thresholds)
      assert Map.has_key?(status.thresholds, :temperature)
      assert Map.has_key?(status.thresholds, :humidity)
    end
  end

  describe "error handling" do
    test "detects timeout when primary sensor fails", %{devices: devices} do
      name = "test_sensor_timeout_#{System.unique_integer([:positive])}"

      # Stub primary sensor to timeout
      stub(DataPointManagerMock, :read_direct, fn
        n when n == devices.temperature -> {:error, :timeout}
        _ -> {:ok, %{value: 65.0}}
      end)

      opts = [
        name: name,
        temperature: devices.temperature,
        humidity: devices.humidity
      ]

      {:ok, _pid} = Sensor.start(opts)
      Process.sleep(50)

      status = Sensor.status(name)
      assert status.error == :timeout
      assert status.error_message == "SENSOR TIMEOUT"
    end

    test "sets secondary readings to nil when they fail", %{devices: devices} do
      name = "test_sensor_partial_#{System.unique_integer([:positive])}"

      # Stub: primary works, secondary times out
      stub(DataPointManagerMock, :read_direct, fn
        n when n == devices.temperature -> {:ok, %{value: 25.5}}
        n when n == devices.humidity -> {:error, :timeout}
        _ -> {:ok, %{value: 0}}
      end)

      opts = [
        name: name,
        temperature: devices.temperature,
        humidity: devices.humidity
      ]

      {:ok, _pid} = Sensor.start(opts)
      Process.sleep(50)

      status = Sensor.status(name)
      # Primary works so no error
      assert status.error == nil
      assert status.temperature == 25.5
      # Secondary failed
      assert status.humidity == nil
    end
  end

  describe "raw value handling" do
    test "extracts value from :raw key when :value not present" do
      name = "test_sensor_raw_#{System.unique_integer([:positive])}"
      dp_name = "test_raw_dp_#{System.unique_integer([:positive])}"

      # Return raw instead of value
      stub(DataPointManagerMock, :read_direct, fn
        n when n == dp_name -> {:ok, %{raw: 42}}
        _ -> {:ok, %{value: 0}}
      end)

      opts = [
        name: name,
        reading: dp_name
      ]

      {:ok, _pid} = Sensor.start(opts)
      Process.sleep(50)

      status = Sensor.status(name)
      assert status.reading == 42
    end

    test "handles plain numeric value response" do
      name = "test_sensor_plain_#{System.unique_integer([:positive])}"
      dp_name = "test_plain_dp_#{System.unique_integer([:positive])}"

      # Return plain number
      stub(DataPointManagerMock, :read_direct, fn
        n when n == dp_name -> {:ok, 123.45}
        _ -> {:ok, %{value: 0}}
      end)

      opts = [
        name: name,
        value: dp_name
      ]

      {:ok, _pid} = Sensor.start(opts)
      Process.sleep(50)

      status = Sensor.status(name)
      assert status.value == 123.45
    end

    test "handles string values" do
      name = "test_sensor_string_#{System.unique_integer([:positive])}"
      dp_name = "test_string_dp_#{System.unique_integer([:positive])}"

      stub(DataPointManagerMock, :read_direct, fn
        n when n == dp_name -> {:ok, "ACTIVE"}
        _ -> {:ok, %{value: 0}}
      end)

      opts = [
        name: name,
        status_text: dp_name
      ]

      {:ok, _pid} = Sensor.start(opts)
      Process.sleep(50)

      status = Sensor.status(name)
      assert status.status_text == "ACTIVE"
    end
  end

  describe "polling behavior" do
    test "updates readings on subsequent polls", %{devices: devices} do
      name = "test_sensor_poll_#{System.unique_integer([:positive])}"

      # Start with initial value
      stub(DataPointManagerMock, :read_direct, fn
        n when n == devices.temperature -> {:ok, %{value: 25.0}}
        _ -> {:ok, %{value: 0}}
      end)

      opts = [
        name: name,
        temperature: devices.temperature,
        poll_interval_ms: 100
      ]

      {:ok, pid} = Sensor.start(opts)
      Process.sleep(50)

      status1 = Sensor.status(name)
      assert status1.temperature == 25.0

      # Update stub to return new value
      stub(DataPointManagerMock, :read_direct, fn
        n when n == devices.temperature -> {:ok, %{value: 30.0}}
        _ -> {:ok, %{value: 0}}
      end)

      # Trigger poll manually
      send(pid, :poll)
      Process.sleep(50)

      status2 = Sensor.status(name)
      assert status2.temperature == 30.0
    end
  end
end

defmodule PouCon.Equipment.Controllers.AverageSensorTest do
  use PouCon.DataCase
  import Mox

  alias PouCon.Equipment.Controllers.AverageSensor
  alias PouCon.DataPointManagerMock

  setup :verify_on_exit!

  setup do
    Mox.set_mox_global(PouCon.DataPointManagerMock)

    id = System.unique_integer([:positive])

    device_names = %{
      temp1: "test_temp1_#{id}",
      temp2: "test_temp2_#{id}",
      hum1: "test_hum1_#{id}",
      hum2: "test_hum2_#{id}",
      co2: "test_co2_#{id}",
      nh3: "test_nh3_#{id}"
    }

    # Default stub: return valid sensor values
    stub(DataPointManagerMock, :read_direct, fn
      n when n == device_names.temp1 -> {:ok, %{value: 25.0, valid: true}}
      n when n == device_names.temp2 -> {:ok, %{value: 27.0, valid: true}}
      n when n == device_names.hum1 -> {:ok, %{value: 60.0, valid: true}}
      n when n == device_names.hum2 -> {:ok, %{value: 70.0, valid: true}}
      n when n == device_names.co2 -> {:ok, %{value: 800, valid: true}}
      n when n == device_names.nh3 -> {:ok, %{value: 15.0, valid: true}}
      _ -> {:ok, %{value: 0, valid: true}}
    end)

    %{devices: device_names}
  end

  describe "start/1 and initialization" do
    test "starts successfully with temperature sensors only", %{devices: devices} do
      opts = [
        name: "test_avg_temp_#{System.unique_integer([:positive])}",
        title: "Test Temp Average",
        temp_sensors: [devices.temp1, devices.temp2]
      ]

      assert {:ok, pid} = AverageSensor.start(opts)
      assert Process.alive?(pid)
    end

    test "starts successfully with all sensor types", %{devices: devices} do
      opts = [
        name: "test_avg_all_#{System.unique_integer([:positive])}",
        temp_sensors: [devices.temp1, devices.temp2],
        humidity_sensors: [devices.hum1, devices.hum2],
        co2_sensors: [devices.co2],
        nh3_sensors: [devices.nh3]
      ]

      assert {:ok, pid} = AverageSensor.start(opts)
      assert Process.alive?(pid)
    end

    test "starts with no sensors configured (reports error state)" do
      opts = [
        name: "test_avg_empty_#{System.unique_integer([:positive])}",
        title: "Test Empty"
      ]

      assert {:ok, pid} = AverageSensor.start(opts)
      assert Process.alive?(pid)
      Process.sleep(50)

      status = AverageSensor.status(opts[:name])
      assert status.error == :no_sensors_configured
    end
  end

  describe "status/1" do
    setup %{devices: devices} do
      name = "test_avg_status_#{System.unique_integer([:positive])}"

      opts = [
        name: name,
        title: "Test Average Sensor",
        temp_sensors: [devices.temp1, devices.temp2],
        humidity_sensors: [devices.hum1, devices.hum2]
      ]

      {:ok, _pid} = AverageSensor.start(opts)
      Process.sleep(50)
      %{name: name}
    end

    test "returns status map with all required fields", %{name: name} do
      status = AverageSensor.status(name)

      assert is_map(status)
      assert status.name == name
      assert Map.has_key?(status, :avg_temp)
      assert Map.has_key?(status, :avg_humidity)
      assert Map.has_key?(status, :avg_co2)
      assert Map.has_key?(status, :avg_nh3)
      assert Map.has_key?(status, :temp_count)
      assert Map.has_key?(status, :humidity_count)
      assert Map.has_key?(status, :error)
      assert Map.has_key?(status, :thresholds)
    end

    test "calculates correct temperature average", %{name: name} do
      status = AverageSensor.status(name)

      # (25.0 + 27.0) / 2 = 26.0
      assert status.avg_temp == 26.0
      assert status.temp_count == 2
    end

    test "calculates correct humidity average", %{name: name} do
      status = AverageSensor.status(name)

      # (60.0 + 70.0) / 2 = 65.0
      assert status.avg_humidity == 65.0
      assert status.humidity_count == 2
    end

    test "returns nil for unconfigured sensor types", %{name: name} do
      status = AverageSensor.status(name)

      # CO2 and NH3 were not configured
      assert status.avg_co2 == nil
      assert status.avg_nh3 == nil
      assert status.co2_count == 0
      assert status.nh3_count == 0
    end

    test "includes individual readings", %{name: name, devices: devices} do
      status = AverageSensor.status(name)

      assert is_list(status.temp_readings)
      assert length(status.temp_readings) == 2

      # Check readings are tuples of {sensor_name, value}
      temp_names = Enum.map(status.temp_readings, fn {name, _val} -> name end)
      assert devices.temp1 in temp_names
      assert devices.temp2 in temp_names
    end
  end

  describe "get_averages/1" do
    setup %{devices: devices} do
      name = "test_avg_get_#{System.unique_integer([:positive])}"

      opts = [
        name: name,
        temp_sensors: [devices.temp1, devices.temp2],
        humidity_sensors: [devices.hum1, devices.hum2]
      ]

      {:ok, _pid} = AverageSensor.start(opts)
      Process.sleep(50)
      %{name: name}
    end

    test "returns {temp, humidity} tuple", %{name: name} do
      result = AverageSensor.get_averages(name)

      assert is_tuple(result)
      assert tuple_size(result) == 2

      {temp, humidity} = result
      assert temp == 26.0
      assert humidity == 65.0
    end
  end

  describe "get_all_averages/1" do
    setup %{devices: devices} do
      name = "test_avg_all_get_#{System.unique_integer([:positive])}"

      opts = [
        name: name,
        temp_sensors: [devices.temp1],
        humidity_sensors: [devices.hum1],
        co2_sensors: [devices.co2],
        nh3_sensors: [devices.nh3]
      ]

      {:ok, _pid} = AverageSensor.start(opts)
      Process.sleep(50)
      %{name: name}
    end

    test "returns map with all sensor types", %{name: name} do
      result = AverageSensor.get_all_averages(name)

      assert is_map(result)
      assert result.temp == 25.0
      assert result.humidity == 60.0
      assert result.co2 == 800.0
      assert result.nh3 == 15.0
    end
  end

  describe "error handling" do
    test "reports :no_temp_data when all temp sensors fail", %{devices: devices} do
      name = "test_avg_no_temp_#{System.unique_integer([:positive])}"

      # Stub all temp sensors to fail
      stub(DataPointManagerMock, :read_direct, fn
        n when n == devices.temp1 -> {:error, :timeout}
        n when n == devices.temp2 -> {:error, :timeout}
        n when n == devices.hum1 -> {:ok, %{value: 65.0, valid: true}}
        _ -> {:ok, %{value: 0, valid: true}}
      end)

      opts = [
        name: name,
        temp_sensors: [devices.temp1, devices.temp2],
        humidity_sensors: [devices.hum1]
      ]

      {:ok, _pid} = AverageSensor.start(opts)
      Process.sleep(50)

      status = AverageSensor.status(name)
      assert status.error == :no_temp_data
      assert status.error_message == "No temperature data available"
    end

    test "reports :partial_data when some sensors fail", %{devices: devices} do
      name = "test_avg_partial_#{System.unique_integer([:positive])}"

      # Stub one temp sensor to fail
      stub(DataPointManagerMock, :read_direct, fn
        n when n == devices.temp1 -> {:ok, %{value: 25.0, valid: true}}
        n when n == devices.temp2 -> {:error, :timeout}
        _ -> {:ok, %{value: 0, valid: true}}
      end)

      opts = [
        name: name,
        temp_sensors: [devices.temp1, devices.temp2]
      ]

      {:ok, _pid} = AverageSensor.start(opts)
      Process.sleep(50)

      status = AverageSensor.status(name)
      assert status.error == :partial_data
      assert status.temp_count == 1
      assert status.avg_temp == 25.0
    end

    test "excludes invalid readings from average", %{devices: devices} do
      name = "test_avg_invalid_#{System.unique_integer([:positive])}"

      # Mark one sensor as invalid
      stub(DataPointManagerMock, :read_direct, fn
        n when n == devices.temp1 -> {:ok, %{value: 25.0, valid: true}}
        n when n == devices.temp2 -> {:ok, %{value: 100.0, valid: false}}
        _ -> {:ok, %{value: 0, valid: true}}
      end)

      opts = [
        name: name,
        temp_sensors: [devices.temp1, devices.temp2]
      ]

      {:ok, _pid} = AverageSensor.start(opts)
      Process.sleep(50)

      status = AverageSensor.status(name)
      # Only temp1 should be counted
      assert status.temp_count == 1
      assert status.avg_temp == 25.0
    end
  end

  describe "single sensor handling" do
    test "handles single string value for temp_sensors", %{devices: devices} do
      name = "test_avg_single_str_#{System.unique_integer([:positive])}"

      # Note: temp_sensors is a single string, not a list
      opts = [
        name: name,
        temp_sensors: devices.temp1
      ]

      {:ok, _pid} = AverageSensor.start(opts)
      Process.sleep(50)

      status = AverageSensor.status(name)
      assert status.temp_count == 1
      assert status.avg_temp == 25.0
    end
  end

  describe "polling behavior" do
    test "updates averages on subsequent polls", %{devices: devices} do
      name = "test_avg_poll_#{System.unique_integer([:positive])}"

      # Start with initial values
      stub(DataPointManagerMock, :read_direct, fn
        n when n == devices.temp1 -> {:ok, %{value: 25.0, valid: true}}
        _ -> {:ok, %{value: 0, valid: true}}
      end)

      opts = [
        name: name,
        temp_sensors: [devices.temp1],
        poll_interval_ms: 100
      ]

      {:ok, pid} = AverageSensor.start(opts)
      Process.sleep(50)

      status1 = AverageSensor.status(name)
      assert status1.avg_temp == 25.0

      # Update sensor value
      stub(DataPointManagerMock, :read_direct, fn
        n when n == devices.temp1 -> {:ok, %{value: 30.0, valid: true}}
        _ -> {:ok, %{value: 0, valid: true}}
      end)

      send(pid, :poll)
      Process.sleep(50)

      status2 = AverageSensor.status(name)
      assert status2.avg_temp == 30.0
    end
  end

  describe "precision handling" do
    test "rounds temperature to 1 decimal place", %{devices: devices} do
      name = "test_avg_precision_#{System.unique_integer([:positive])}"

      stub(DataPointManagerMock, :read_direct, fn
        n when n == devices.temp1 -> {:ok, %{value: 25.333, valid: true}}
        n when n == devices.temp2 -> {:ok, %{value: 26.666, valid: true}}
        _ -> {:ok, %{value: 0, valid: true}}
      end)

      opts = [
        name: name,
        temp_sensors: [devices.temp1, devices.temp2]
      ]

      {:ok, _pid} = AverageSensor.start(opts)
      Process.sleep(50)

      status = AverageSensor.status(name)
      # (25.333 + 26.666) / 2 = 25.9995 -> 26.0
      assert status.avg_temp == 26.0
    end

    test "rounds CO2 to whole number", %{devices: devices} do
      name = "test_avg_co2_precision_#{System.unique_integer([:positive])}"

      stub(DataPointManagerMock, :read_direct, fn
        n when n == devices.temp1 -> {:ok, %{value: 25.0, valid: true}}
        n when n == devices.co2 -> {:ok, %{value: 823.7, valid: true}}
        _ -> {:ok, %{value: 0, valid: true}}
      end)

      opts = [
        name: name,
        temp_sensors: [devices.temp1],
        co2_sensors: [devices.co2]
      ]

      {:ok, _pid} = AverageSensor.start(opts)
      Process.sleep(50)

      status = AverageSensor.status(name)
      # 823.7 -> 824.0 (rounded to whole number)
      assert status.avg_co2 == 824.0
    end
  end
end

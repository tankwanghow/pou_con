defmodule PouCon.DeviceControllers.TempHumSenControllerTest do
  use PouCon.DataCase
  import Mox

  alias PouCon.DeviceControllers.TempHumSenController
  alias PouCon.DeviceManagerMock

  setup :verify_on_exit!

  setup do
    Mox.set_mox_global(PouCon.DeviceManagerMock)

    id = System.unique_integer([:positive])
    device_names = %{
      sensor: "temp_hum_#{id}"
    }

    stub(DeviceManagerMock, :get_cached_data, fn _name -> {:ok, %{temperature: 25.0, humidity: 50.0}} end)

    %{devices: device_names}
  end

  describe "start/1" do
    test "starts successfully", %{devices: devices} do
      opts = [
        name: "test_th_1_#{System.unique_integer([:positive])}",
        title: "Test TH 1",
        sensor: devices.sensor
      ]

      assert {:ok, pid} = TempHumSenController.start(opts)
      assert Process.alive?(pid)
    end
  end

  describe "status/1" do
    setup %{devices: devices} do
      name = "test_th_status_#{System.unique_integer([:positive])}"
      opts = [
        name: name,
        title: "Test Status TH",
        sensor: devices.sensor
      ]

      {:ok, _pid} = TempHumSenController.start(opts)
      %{name: name}
    end

    test "returns status map", %{name: name} do
      status = TempHumSenController.status(name)
      assert is_map(status)
      assert status.name == name
      assert status.temperature == 25.0
      assert status.humidity == 50.0
      assert status.error == nil
    end

    test "calculates dew point", %{name: name} do
      status = TempHumSenController.status(name)
      assert status.dew_point != nil
      assert is_float(status.dew_point)
    end

    test "handles sensor error", %{devices: devices} do
      name = "test_th_error_#{System.unique_integer([:positive])}"
      stub(DeviceManagerMock, :get_cached_data, fn _ -> {:error, :timeout} end)

      opts = [
        name: name,
        sensor: devices.sensor
      ]

      {:ok, _pid} = TempHumSenController.start(opts)
      Process.sleep(50)

      status = TempHumSenController.status(name)
      assert status.error == :timeout
      assert status.error_message == "SENSOR TIMEOUT"
    end
  end
end

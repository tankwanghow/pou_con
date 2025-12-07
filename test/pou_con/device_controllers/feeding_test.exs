defmodule PouCon.DeviceControllers.FeedingTest do
  use PouCon.DataCase
  import Mox

  alias PouCon.DeviceControllers.Feeding
  alias PouCon.DeviceManagerMock

  setup :verify_on_exit!

  setup do
    Mox.set_mox_global(PouCon.DeviceManagerMock)

    id = System.unique_integer([:positive])

    device_names = %{
      device_to_back_limit: "dev_back_#{id}",
      device_to_front_limit: "dev_front_#{id}",
      front_limit: "lim_front_#{id}",
      back_limit: "lim_back_#{id}",
      pulse_sensor: "pulse_#{id}",
      auto_manual: "am_#{id}"
    }

    stub(DeviceManagerMock, :get_cached_data, fn _name -> {:ok, %{state: 0}} end)
    stub(DeviceManagerMock, :command, fn _name, _cmd, _params -> {:ok, :success} end)

    %{devices: device_names}
  end

  describe "start/1" do
    test "starts successfully with valid options", %{devices: devices} do
      opts = [
        name: "test_feeding_1_#{System.unique_integer([:positive])}",
        title: "Test Feeding 1",
        device_to_back_limit: devices.device_to_back_limit,
        device_to_front_limit: devices.device_to_front_limit,
        front_limit: devices.front_limit,
        back_limit: devices.back_limit,
        pulse_sensor: devices.pulse_sensor,
        auto_manual: devices.auto_manual
      ]

      assert {:ok, pid} = Feeding.start(opts)
      assert Process.alive?(pid)
    end
  end

  describe "status/1" do
    setup %{devices: devices} do
      name = "test_feeding_status_#{System.unique_integer([:positive])}"

      opts = [
        name: name,
        title: "Test Status Feeding",
        device_to_back_limit: devices.device_to_back_limit,
        device_to_front_limit: devices.device_to_front_limit,
        front_limit: devices.front_limit,
        back_limit: devices.back_limit,
        pulse_sensor: devices.pulse_sensor,
        auto_manual: devices.auto_manual
      ]

      {:ok, _pid} = Feeding.start(opts)
      %{name: name}
    end

    test "returns status map", %{name: name} do
      status = Feeding.status(name)
      assert is_map(status)
      assert status.name == name
      assert status.moving == false
      assert status.mode == :auto
      assert status.error == nil
    end

    test "reflects state", %{devices: devices} do
      name = "test_feeding_state_#{System.unique_integer([:positive])}"

      stub(DeviceManagerMock, :get_cached_data, fn
        n when n == devices.front_limit -> {:ok, %{state: 1}}
        n when n == devices.back_limit -> {:ok, %{state: 0}}
        # Moving
        n when n == devices.pulse_sensor -> {:ok, %{state: 1}}
        # Manual
        n when n == devices.auto_manual -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      opts = [
        name: name,
        device_to_back_limit: devices.device_to_back_limit,
        device_to_front_limit: devices.device_to_front_limit,
        front_limit: devices.front_limit,
        back_limit: devices.back_limit,
        pulse_sensor: devices.pulse_sensor,
        auto_manual: devices.auto_manual
      ]

      {:ok, _pid} = Feeding.start(opts)
      Process.sleep(50)

      status = Feeding.status(name)
      assert status.at_front == true
      assert status.at_back == false
      assert status.moving == true
      assert status.mode == :manual
    end
  end

  describe "commands" do
    setup %{devices: devices} do
      name = "test_feeding_cmd_#{System.unique_integer([:positive])}"

      opts = [
        name: name,
        device_to_back_limit: devices.device_to_back_limit,
        device_to_front_limit: devices.device_to_front_limit,
        front_limit: devices.front_limit,
        back_limit: devices.back_limit,
        pulse_sensor: devices.pulse_sensor,
        auto_manual: devices.auto_manual
      ]

      {:ok, pid} = Feeding.start(opts)
      %{name: name, pid: pid}
    end

    test "move_to_back_limit sends commands", %{name: name, devices: devices} do
      # Expect coils activation
      expect(DeviceManagerMock, :command, 2, fn
        n, :set_state, %{state: 0} when n == devices.device_to_front_limit -> {:ok, :success}
        n, :set_state, %{state: 1} when n == devices.device_to_back_limit -> {:ok, :success}
        _, _, _ -> {:error, :unexpected}
      end)

      Feeding.move_to_back_limit(name)
      Process.sleep(50)

      status = Feeding.status(name)
      assert status.target_limit == :to_back_limit
    end

    test "stop_movement sends commands", %{name: name, devices: devices} do
      expect(DeviceManagerMock, :command, 2, fn
        n, :set_state, %{state: 0} when n == devices.device_to_front_limit -> {:ok, :success}
        n, :set_state, %{state: 0} when n == devices.device_to_back_limit -> {:ok, :success}
        _, _, _ -> {:error, :unexpected}
      end)

      Feeding.stop_movement(name)
      Process.sleep(50)
    end
  end
end

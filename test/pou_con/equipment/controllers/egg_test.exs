defmodule PouCon.Equipment.Controllers.EggTest do
  use PouCon.DataCase
  import Mox

  alias PouCon.Equipment.Controllers.Egg
  alias PouCon.DataPointManagerMock

  setup :verify_on_exit!

  setup do
    Mox.set_mox_global(PouCon.DataPointManagerMock)

    id = System.unique_integer([:positive])

    device_names = %{
      on_off_coil: "test_egg_coil_#{id}",
      running_feedback: "test_egg_fb_#{id}",
      auto_manual: "test_egg_am_#{id}"
    }

    stub(DataPointManagerMock, :read_direct, fn _name -> {:ok, %{state: 0}} end)
    stub(DataPointManagerMock, :command, fn _name, _cmd, _params -> {:ok, :success} end)

    %{devices: device_names}
  end

  describe "start/1 and initialization" do
    test "starts successfully with valid options", %{devices: devices} do
      opts = [
        name: "test_egg_1_#{System.unique_integer([:positive])}",
        title: "Test Egg 1",
        on_off_coil: devices.on_off_coil,
        running_feedback: devices.running_feedback,
        auto_manual: devices.auto_manual
      ]

      assert {:ok, pid} = Egg.start(opts)
      assert Process.alive?(pid)
    end
  end

  describe "status/1" do
    setup %{devices: devices} do
      name = "test_egg_status_#{System.unique_integer([:positive])}"

      opts = [
        name: name,
        title: "Test Status Egg",
        on_off_coil: devices.on_off_coil,
        running_feedback: devices.running_feedback,
        auto_manual: devices.auto_manual
      ]

      {:ok, _pid} = Egg.start(opts)
      %{name: name}
    end

    test "returns status map with all required fields", %{name: name} do
      status = Egg.status(name)
      assert is_map(status)
      assert status.name == name
      assert status.mode == :auto
      assert status.error == nil
    end

    test "reflects state from DataPointManager", %{devices: devices} do
      name = "test_egg_state_#{System.unique_integer([:positive])}"

      stub(DataPointManagerMock, :read_direct, fn
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

      {:ok, _pid} = Egg.start(opts)
      Process.sleep(50)

      status = Egg.status(name)
      assert status.actual_on == true
      assert status.is_running == true
      assert status.mode == :manual
    end

    test "returns error message when DataPointManager returns error", %{devices: devices} do
      name = "test_egg_error_#{System.unique_integer([:positive])}"
      stub(DataPointManagerMock, :read_direct, fn _ -> {:error, :timeout} end)

      opts = [
        name: name,
        on_off_coil: devices.on_off_coil,
        running_feedback: devices.running_feedback,
        auto_manual: devices.auto_manual
      ]

      {:ok, _pid} = Egg.start(opts)
      Process.sleep(50)

      status = Egg.status(name)
      assert status.error == :timeout
      assert status.error_message == "SENSOR TIMEOUT"
    end
  end

  describe "commands" do
    setup %{devices: devices} do
      name = "test_egg_cmd_#{System.unique_integer([:positive])}"

      # Create a virtual port and data point for auto_manual to enable set_mode
      {:ok, _port} =
        PouCon.Repo.insert(%PouCon.Hardware.Ports.Port{
          device_path: "virtual",
          protocol: "virtual"
        })

      {:ok, _data_point} =
        PouCon.Repo.insert(%PouCon.Equipment.Schemas.DataPoint{
          name: devices.auto_manual,
          type: "VDI",
          slave_id: 0,
          port_path: "virtual"
        })

      opts = [
        name: name,
        on_off_coil: devices.on_off_coil,
        running_feedback: devices.running_feedback,
        auto_manual: devices.auto_manual
      ]

      {:ok, pid} = Egg.start(opts)
      %{name: name, pid: pid}
    end

    test "turn_on sends command to DataPointManager", %{name: name, devices: devices} do
      expect(DataPointManagerMock, :command, fn n, :set_state, %{state: 1} ->
        assert n == devices.on_off_coil
        {:ok, :success}
      end)

      Egg.turn_on(name)
      Process.sleep(50)

      status = Egg.status(name)
      assert status.commanded_on == true
    end

    test "turn_off sends command to DataPointManager", %{name: name, pid: pid, devices: devices} do
      stub(DataPointManagerMock, :read_direct, fn
        n when n == devices.on_off_coil -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      send(pid, :data_refreshed)
      Process.sleep(50)

      expect(DataPointManagerMock, :command, fn n, :set_state, %{state: 0} ->
        assert n == devices.on_off_coil
        {:ok, :success}
      end)

      Egg.turn_off(name)
      Process.sleep(50)

      status = Egg.status(name)
      assert status.commanded_on == false
    end

    test "set_mode(:manual) sends command to DataPointManager", %{name: name, devices: devices} do
      expect(DataPointManagerMock, :command, fn n, :set_state, %{state: 1} ->
        assert n == devices.auto_manual
        {:ok, :success}
      end)

      Egg.set_mode(name, :manual)
      Process.sleep(50)
    end
  end
end

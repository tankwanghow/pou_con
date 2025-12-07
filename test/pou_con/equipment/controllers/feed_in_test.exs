defmodule PouCon.Equipment.Controllers.FeedInTest do
  use PouCon.DataCase
  import Mox

  alias PouCon.Equipment.Controllers.FeedIn
  alias PouCon.DeviceManagerMock

  setup :verify_on_exit!

  setup do
    Mox.set_mox_global(PouCon.DeviceManagerMock)

    id = System.unique_integer([:positive])

    device_names = %{
      filling_coil: "fill_#{id}",
      running_feedback: "fb_#{id}",
      auto_manual: "am_#{id}",
      full_switch: "full_#{id}"
    }

    # Default: bucket is full (state: 1) so AUTO mode doesn't try to auto-fill
    stub(DeviceManagerMock, :get_cached_data, fn
      name ->
        if String.starts_with?(name, "full_") do
          {:ok, %{state: 1}}
        else
          {:ok, %{state: 0}}
        end
    end)

    stub(DeviceManagerMock, :command, fn _name, _cmd, _params -> {:ok, :success} end)

    %{devices: device_names}
  end

  describe "start/1" do
    test "starts successfully", %{devices: devices} do
      opts = [
        name: "test_feedin_1_#{System.unique_integer([:positive])}",
        title: "Test FeedIn 1",
        filling_coil: devices.filling_coil,
        running_feedback: devices.running_feedback,
        auto_manual: devices.auto_manual,
        full_switch: devices.full_switch
      ]

      assert {:ok, pid} = FeedIn.start(opts)
      assert Process.alive?(pid)
    end
  end

  describe "status/1" do
    setup %{devices: devices} do
      name = "test_feedin_status_#{System.unique_integer([:positive])}"

      opts = [
        name: name,
        title: "Test Status FeedIn",
        filling_coil: devices.filling_coil,
        running_feedback: devices.running_feedback,
        auto_manual: devices.auto_manual,
        full_switch: devices.full_switch
      ]

      {:ok, _pid} = FeedIn.start(opts)
      %{name: name}
    end

    test "returns status map", %{name: name} do
      status = FeedIn.status(name)
      assert is_map(status)
      assert status.name == name
      assert status.mode == :auto
      assert status.error == nil
    end

    test "reflects state", %{devices: devices} do
      name = "test_feedin_state_#{System.unique_integer([:positive])}"

      stub(DeviceManagerMock, :get_cached_data, fn
        n when n == devices.full_switch -> {:ok, %{state: 1}}
        n when n == devices.filling_coil -> {:ok, %{state: 1}}
        n when n == devices.running_feedback -> {:ok, %{state: 1}}
        # Manual
        n when n == devices.auto_manual -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      opts = [
        name: name,
        filling_coil: devices.filling_coil,
        running_feedback: devices.running_feedback,
        auto_manual: devices.auto_manual,
        full_switch: devices.full_switch
      ]

      {:ok, _pid} = FeedIn.start(opts)
      Process.sleep(50)

      status = FeedIn.status(name)
      assert status.bucket_full == true
      assert status.actual_on == true
      assert status.is_running == true
      assert status.mode == :manual
    end
  end

  describe "commands" do
    setup %{devices: devices} do
      name = "test_feedin_cmd_#{System.unique_integer([:positive])}"

      opts = [
        name: name,
        filling_coil: devices.filling_coil,
        running_feedback: devices.running_feedback,
        auto_manual: devices.auto_manual,
        full_switch: devices.full_switch
      ]

      {:ok, pid} = FeedIn.start(opts)
      %{name: name, pid: pid}
    end

    test "turn_on sends command", %{name: name, devices: devices} do
      expect(DeviceManagerMock, :command, fn n, :set_state, %{state: 1} ->
        assert n == devices.filling_coil
        {:ok, :success}
      end)

      FeedIn.turn_on(name)
      Process.sleep(50)

      status = FeedIn.status(name)
      assert status.commanded_on == true
    end
  end
end

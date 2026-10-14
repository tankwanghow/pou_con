defmodule PouCon.Equipment.Controllers.FeedInTest do
  use PouCon.DataCase
  import Mox

  alias PouCon.Equipment.Controllers.FeedIn
  alias PouCon.DataPointManagerMock

  setup :verify_on_exit!

  setup do
    Mox.set_mox_global(PouCon.DataPointManagerMock)

    id = System.unique_integer([:positive])

    device_names = %{
      filling_coil: "fill_#{id}",
      running_feedback: "fb_#{id}",
      auto_manual: "am_#{id}",
      full_switch: "full_#{id}"
    }

    # Default: bucket is full (state: 1) so AUTO mode doesn't try to auto-fill
    # auto_manual state: 1 = AUTO mode
    stub(DataPointManagerMock, :read_direct, fn
      name ->
        cond do
          String.starts_with?(name, "full_") -> {:ok, %{state: 1}}
          String.starts_with?(name, "am_") -> {:ok, %{state: 1}}
          true -> {:ok, %{state: 0}}
        end
    end)

    stub(DataPointManagerMock, :command, fn _name, _cmd, _params -> {:ok, :success} end)

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

      stub(DataPointManagerMock, :read_direct, fn
        n when n == devices.full_switch -> {:ok, %{state: 1}}
        n when n == devices.filling_coil -> {:ok, %{state: 1}}
        n when n == devices.running_feedback -> {:ok, %{state: 1}}
        # Manual mode: state 0 = manual, state 1 = auto
        n when n == devices.auto_manual -> {:ok, %{state: 0}}
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
      expect(DataPointManagerMock, :command, fn n, :set_state, %{state: 1} ->
        assert n == devices.filling_coil
        {:ok, :success}
      end)

      FeedIn.turn_on(name)
      Process.sleep(50)

      status = FeedIn.status(name)
      assert status.commanded_on == true
    end
  end

  describe "stops (trip, hopper full, max-fill timer)" do
    # Simulated hardware: coil writes land in the Agent so reads reflect them.
    setup %{devices: devices} do
      trip = "trip_#{System.unique_integer([:positive])}"

      {:ok, hw} =
        Agent.start_link(fn ->
          %{
            devices.filling_coil => 0,
            devices.running_feedback => 0,
            devices.auto_manual => 1,
            devices.full_switch => 0,
            trip => 0
          }
        end)

      stub(DataPointManagerMock, :read_direct, fn n ->
        {:ok, %{state: Agent.get(hw, &Map.get(&1, n, 0))}}
      end)

      stub(DataPointManagerMock, :command, fn n, :set_state, %{state: v} ->
        Agent.update(hw, &Map.put(&1, n, v))
        {:ok, :success}
      end)

      %{hw: hw, trip: trip}
    end

    defp start_feedin(devices, trip, full_switch) do
      name = "test_feedin_trip_#{System.unique_integer([:positive])}"

      {:ok, pid} =
        FeedIn.start(
          name: name,
          filling_coil: devices.filling_coil,
          running_feedback: devices.running_feedback,
          auto_manual: devices.auto_manual,
          full_switch: full_switch,
          trip: trip,
          # Polls are driven manually below
          poll_interval_ms: 60_000
        )

      {name, pid}
    end

    defp poll(pid) do
      send(pid, :poll)
      :sys.get_state(pid)
    end

    # Event writes are async (Task.Supervisor), so poll the DB briefly
    defp wait_for_events(name, type, attempts \\ 50) do
      events = PouCon.Logging.EquipmentLogger.query_events(equipment_name: name, event_type: type)

      if events == [] and attempts > 0 do
        Process.sleep(10)
        wait_for_events(name, type, attempts - 1)
      else
        events
      end
    end

    defp set_hw(hw, changes), do: Agent.update(hw, &Map.merge(&1, changes))
    defp hw_value(hw, key), do: Agent.get(hw, &Map.fetch!(&1, key))

    for {label, with_full_switch?} <- [{"with full switch", true}, {"without full switch", false}] do
      test "trip during an AUTO fill turns START-CMD off and it stays off after reset (#{label})",
           %{devices: devices, hw: hw, trip: trip} do
        full = if unquote(with_full_switch?), do: devices.full_switch, else: nil
        {name, pid} = start_feedin(devices, trip, full)

        FeedIn.turn_on(name)
        :sys.get_state(pid)
        assert hw_value(hw, devices.filling_coil) == 1

        set_hw(hw, %{devices.running_feedback => 1})
        poll(pid)

        # Overload trips: motor stops
        set_hw(hw, %{trip => 1, devices.running_feedback => 0})
        poll(pid)

        assert hw_value(hw, devices.filling_coil) == 0
        status = FeedIn.status(name)
        assert status.commanded_on == false
        assert status.error == :tripped

        # Operator resets the overload: auger must NOT restart by itself
        set_hw(hw, %{trip => 0})
        poll(pid)
        poll(pid)

        assert hw_value(hw, devices.filling_coil) == 0
        assert FeedIn.status(name).commanded_on == false
      end
    end

    test "full switch stopping an AUTO fill logs a bucket_full stop event",
         %{devices: devices, hw: hw, trip: trip} do
      start_supervised!({Task.Supervisor, name: PouCon.TaskSupervisor})
      {name, pid} = start_feedin(devices, trip, devices.full_switch)

      FeedIn.turn_on(name)
      :sys.get_state(pid)
      set_hw(hw, %{devices.running_feedback => 1})
      poll(pid)

      # Hopper full: hardwired contact drops the contactor, PLC sees FULL=1
      set_hw(hw, %{devices.full_switch => 1, devices.running_feedback => 0})
      poll(pid)
      poll(pid)

      assert [event] = wait_for_events(name, "stop")
      assert event.mode == "auto"
      assert event.triggered_by == "system"

      assert %{"reason" => "bucket_full", "source" => "full_switch"} =
               Jason.decode!(event.metadata)

      assert hw_value(hw, devices.filling_coil) == 0
    end

    test "max-fill timer stop is written to the event log",
         %{devices: devices, hw: hw, trip: trip} do
      start_supervised!({Task.Supervisor, name: PouCon.TaskSupervisor})
      {name, pid} = start_feedin(devices, trip, devices.full_switch)

      FeedIn.turn_on(name)
      set_hw(hw, %{devices.running_feedback => 1})
      poll(pid)

      send(pid, :fill_timeout)
      :sys.get_state(pid)

      assert [event] = wait_for_events(name, "stop")
      assert event.triggered_by == "system"
      assert %{"reason" => "silo_bridging"} = Jason.decode!(event.metadata)
    end

    test "turn_on is refused while tripped", %{devices: devices, hw: hw, trip: trip} do
      set_hw(hw, %{trip => 1})
      {name, pid} = start_feedin(devices, trip, devices.full_switch)

      FeedIn.turn_on(name)
      :sys.get_state(pid)

      assert hw_value(hw, devices.filling_coil) == 0
      assert FeedIn.status(name).commanded_on == false
    end

    test "trip while running in MANUAL turns START-CMD off",
         %{devices: devices, hw: hw, trip: trip} do
      set_hw(hw, %{
        devices.auto_manual => 0,
        devices.filling_coil => 1,
        devices.running_feedback => 1
      })

      {name, pid} = start_feedin(devices, trip, devices.full_switch)
      assert FeedIn.status(name).actual_on == true

      set_hw(hw, %{trip => 1, devices.running_feedback => 0})
      poll(pid)

      assert hw_value(hw, devices.filling_coil) == 0

      set_hw(hw, %{trip => 0})
      poll(pid)

      assert hw_value(hw, devices.filling_coil) == 0
    end
  end
end

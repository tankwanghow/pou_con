defmodule PouCon.Automation.EggCollection.EggCollectionSchedulerTest do
  use PouCon.DataCase, async: false
  import Mox
  import PouCon.AutomationTestHelpers

  alias PouCon.Automation.EggCollection.EggCollectionScheduler
  alias PouCon.Equipment.Controllers.Egg

  setup :verify_on_exit!

  setup do
    setup_automation_test()

    on_exit(fn ->
      stop_genserver(EggCollectionScheduler)
      Ecto.Adapters.SQL.Sandbox.mode(PouCon.Repo, :manual)
    end)

    :ok
  end

  describe "start_link/1" do
    test "starts the scheduler successfully" do
      stop_genserver(EggCollectionScheduler)

      assert {:ok, pid} = EggCollectionScheduler.start_link()
      assert Process.alive?(pid)
    end

    test "registers with module name" do
      stop_genserver(EggCollectionScheduler)

      {:ok, pid} = EggCollectionScheduler.start_link()
      assert Process.whereis(EggCollectionScheduler) == pid
    end
  end

  describe "schedule execution" do
    test "turns on egg collection when within schedule period" do
      stop_genserver(EggCollectionScheduler)

      equipment = create_equipment!("sched_egg_1", "egg")
      {_name, _pid, _devs} = start_egg!(name: "sched_egg_1")

      # Set egg in AUTO mode
      stub_read_direct(fn
        "sched_egg_1_am" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      wait_for_init()

      # Create schedule that includes current time
      now = current_time_truncated()
      start_time = Time.add(now, -60, :second)
      stop_time = Time.add(now, 3600, :second)

      create_egg_schedule!(equipment, start_time, stop_time)

      {:ok, _pid} = EggCollectionScheduler.start_link()
      EggCollectionScheduler.force_check()
      Process.sleep(200)

      # Egg should be commanded on
      status = Egg.status("sched_egg_1")
      assert status.commanded_on == true
    end

    test "turns off egg collection when outside schedule period" do
      stop_genserver(EggCollectionScheduler)

      equipment = create_equipment!("sched_egg_2", "egg")
      {_name, _pid, _devs} = start_egg!(name: "sched_egg_2")

      # Set egg in AUTO mode, currently ON
      stub_read_direct(fn
        "sched_egg_2_am" -> {:ok, %{state: 1}}
        "sched_egg_2_coil" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      wait_for_init()

      # Turn on first
      Egg.turn_on("sched_egg_2")
      Process.sleep(100)

      # Create schedule that ended an hour ago
      now = current_time_truncated()
      start_time = Time.add(now, -7200, :second)
      stop_time = Time.add(now, -3600, :second)

      # Avoid negative wrap-around issues
      if Time.compare(start_time, stop_time) == :lt do
        create_egg_schedule!(equipment, start_time, stop_time)

        {:ok, _pid} = EggCollectionScheduler.start_link()
        EggCollectionScheduler.force_check()
        Process.sleep(200)

        status = Egg.status("sched_egg_2")
        assert status.commanded_on == false
      end
    end
  end

  describe "mode filtering" do
    test "skips egg equipment in MANUAL mode" do
      stop_genserver(EggCollectionScheduler)

      equipment = create_equipment!("manual_egg", "egg")
      {_name, _pid, _devs} = start_egg!(name: "manual_egg")

      # Set egg in MANUAL mode (auto_manual DI = 0)
      stub_read_direct(fn _ -> {:ok, %{state: 0}} end)
      wait_for_init()

      now = current_time_truncated()
      start_time = Time.add(now, -60, :second)
      stop_time = Time.add(now, 3600, :second)

      create_egg_schedule!(equipment, start_time, stop_time)

      {:ok, _pid} = EggCollectionScheduler.start_link()
      EggCollectionScheduler.force_check()
      Process.sleep(200)

      # Egg should remain off since it's in MANUAL mode
      status = Egg.status("manual_egg")
      assert status.commanded_on == false
    end
  end

  describe "reload_schedules/0" do
    test "reloads schedules from database" do
      stop_genserver(EggCollectionScheduler)

      {:ok, _pid} = EggCollectionScheduler.start_link()
      assert :ok = EggCollectionScheduler.reload_schedules()
      Process.sleep(100)
    end
  end

  describe "error handling" do
    test "handles unavailable controller gracefully" do
      stop_genserver(EggCollectionScheduler)

      # Create equipment but don't start controller
      equipment = create_equipment!("ghost_egg", "egg")

      now = current_time_truncated()
      start_time = Time.add(now, -60, :second)
      stop_time = Time.add(now, 3600, :second)

      create_egg_schedule!(equipment, start_time, stop_time)

      {:ok, pid} = EggCollectionScheduler.start_link()
      EggCollectionScheduler.force_check()
      Process.sleep(200)

      # Should not crash
      assert Process.alive?(pid)
    end
  end

  # ——————————————————————————————————————————————————————————————
  # Helper Functions
  # ——————————————————————————————————————————————————————————————

  defp current_time_truncated do
    timezone = PouCon.Auth.get_timezone()
    current_datetime = DateTime.now!(timezone)
    current_time = DateTime.to_time(current_datetime)
    %{current_time | second: 0, microsecond: {0, 0}}
  end
end

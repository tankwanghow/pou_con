defmodule PouCon.Automation.Feeding.FeedingSchedulerTest do
  use PouCon.DataCase, async: false
  import Mox
  import PouCon.AutomationTestHelpers

  alias PouCon.Automation.Feeding.FeedingScheduler
  alias PouCon.Equipment.Controllers.Feeding

  setup :verify_on_exit!

  setup do
    setup_automation_test()

    on_exit(fn ->
      stop_genserver(FeedingScheduler)
      Ecto.Adapters.SQL.Sandbox.mode(PouCon.Repo, :manual)
    end)

    :ok
  end

  describe "start_link/1" do
    test "starts the scheduler successfully" do
      stop_genserver(FeedingScheduler)

      assert {:ok, pid} = FeedingScheduler.start_link()
      assert Process.alive?(pid)
    end

    test "registers with module name" do
      stop_genserver(FeedingScheduler)

      {:ok, pid} = FeedingScheduler.start_link()
      assert Process.whereis(FeedingScheduler) == pid
    end
  end

  describe "force_check/0" do
    test "triggers an immediate check" do
      stop_genserver(FeedingScheduler)

      {:ok, pid} = FeedingScheduler.start_link()
      FeedingScheduler.force_check()
      Process.sleep(100)

      assert Process.alive?(pid)
    end
  end

  describe "reload_schedules/0" do
    test "reloads schedules from database" do
      stop_genserver(FeedingScheduler)

      {:ok, _pid} = FeedingScheduler.start_link()
      assert :ok = FeedingScheduler.reload_schedules()
      Process.sleep(100)
    end
  end

  describe "schedule_updated/0" do
    test "calls reload_schedules for legacy compatibility" do
      stop_genserver(FeedingScheduler)

      {:ok, _pid} = FeedingScheduler.start_link()
      assert :ok = FeedingScheduler.schedule_updated()
      Process.sleep(100)
    end
  end

  describe "mode filtering" do
    test "skips feeding equipment in MANUAL mode" do
      stop_genserver(FeedingScheduler)

      create_equipment!("manual_feeding", "feeding")
      {_name, _pid, _devs} = start_feeding!(name: "manual_feeding")

      # Set feeding in MANUAL mode (auto_manual DI = 0)
      stub_read_direct(fn _ -> {:ok, %{state: 0}} end)
      wait_for_init()

      now = current_time_truncated()

      create_feeding_schedule!(
        move_to_back_limit_time: now,
        move_to_front_limit_time: Time.add(now, -3600, :second),
        enabled: true
      )

      {:ok, pid} = FeedingScheduler.start_link()
      FeedingScheduler.force_check()
      Process.sleep(200)

      # Should not crash and should not move equipment in MANUAL mode
      assert Process.alive?(pid)
    end
  end

  describe "error handling" do
    test "handles unavailable feeding controller gracefully" do
      stop_genserver(FeedingScheduler)

      # Create equipment but don't start controller
      create_equipment!("ghost_feeding", "feeding")

      now = current_time_truncated()

      create_feeding_schedule!(
        move_to_back_limit_time: now,
        move_to_front_limit_time: Time.add(now, -3600, :second),
        enabled: true
      )

      {:ok, pid} = FeedingScheduler.start_link()
      FeedingScheduler.force_check()
      Process.sleep(200)

      # Should not crash
      assert Process.alive?(pid)
    end

    test "handles no schedules gracefully" do
      stop_genserver(FeedingScheduler)

      {:ok, pid} = FeedingScheduler.start_link()
      FeedingScheduler.force_check()
      Process.sleep(100)

      assert Process.alive?(pid)
    end
  end

  describe "move_to_back with FeedIn prerequisite" do
    test "skips move_to_back when no FeedIn equipment exists but allows it" do
      stop_genserver(FeedingScheduler)

      create_equipment!("back_feeding", "feeding")
      {_name, _pid, _devs} = start_feeding!(name: "back_feeding")

      # Set feeding in AUTO mode, at front limit, not at back
      stub_read_direct(fn
        "back_feeding_am" -> {:ok, %{state: 1}}
        "back_feeding_front" -> {:ok, %{state: 1}}
        "back_feeding_back" -> {:ok, %{state: 0}}
        _ -> {:ok, %{state: 0}}
      end)

      wait_for_init()

      now = current_time_truncated()

      create_feeding_schedule!(
        move_to_back_limit_time: now,
        enabled: true
      )

      {:ok, pid} = FeedingScheduler.start_link()
      FeedingScheduler.force_check()
      Process.sleep(200)

      # Should not crash - when no FeedIn exists, it allows the move
      assert Process.alive?(pid)
    end
  end

  describe "move_to_front scheduling" do
    test "does not move to front when not at back limit" do
      stop_genserver(FeedingScheduler)

      create_equipment!("front_feeding", "feeding")
      {_name, _pid, _devs} = start_feeding!(name: "front_feeding")

      # Set feeding in AUTO mode, NOT at back limit, NOT at front
      stub_read_direct(fn
        "front_feeding_am" -> {:ok, %{state: 1}}
        "front_feeding_front" -> {:ok, %{state: 0}}
        "front_feeding_back" -> {:ok, %{state: 0}}
        _ -> {:ok, %{state: 0}}
      end)

      wait_for_init()

      now = current_time_truncated()

      create_feeding_schedule!(
        move_to_front_limit_time: now,
        enabled: true
      )

      {:ok, pid} = FeedingScheduler.start_link()
      FeedingScheduler.force_check()
      Process.sleep(200)

      # Should not crash and should not move (back_limit not ON)
      assert Process.alive?(pid)
      status = Feeding.status("front_feeding")
      assert status.moving == false
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

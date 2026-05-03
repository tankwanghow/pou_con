defmodule PouCon.Automation.Feeding.FeedingSchedulerTest do
  use PouCon.DataCase, async: false
  import Mox
  import PouCon.AutomationTestHelpers

  alias PouCon.Automation.Feeding.FeedingScheduler
  alias PouCon.Equipment.Controllers.{FeedIn, Feeding}

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

    test "preserves armed-fill state across reload" do
      stop_genserver(FeedingScheduler)

      trigger = create_equipment!("preserve_trigger", "feeding")

      _schedule =
        create_feeding_schedule!(
          move_to_front_limit_time: ~T[03:00:00],
          feedin_front_limit_bucket_id: trigger.id,
          enabled: true
        )

      {:ok, _pid} = FeedingScheduler.start_link()

      armed_until = System.monotonic_time(:millisecond) + :timer.minutes(10)

      :sys.replace_state(FeedingScheduler, fn state ->
        state
        |> Map.put(:armed_fill_until_mono, armed_until)
        |> Map.put(:armed_for_schedule_id, 1234)
      end)

      assert :ok = FeedingScheduler.reload_schedules()
      Process.sleep(100)

      sched_state = :sys.get_state(FeedingScheduler)
      assert sched_state.armed_fill_until_mono == armed_until
      assert sched_state.armed_for_schedule_id == 1234
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

      assert Process.alive?(pid)
    end
  end

  describe "error handling" do
    test "handles unavailable feeding controller gracefully" do
      stop_genserver(FeedingScheduler)

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

      assert Process.alive?(pid)
    end
  end

  describe "move_to_front scheduling" do
    test "does not move to front when not at back limit" do
      stop_genserver(FeedingScheduler)

      create_equipment!("front_feeding", "feeding")
      {_name, _pid, _devs} = start_feeding!(name: "front_feeding")

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

      assert Process.alive?(pid)
      status = Feeding.status("front_feeding")
      assert status.moving == false
    end
  end

  # ——————————————————————————————————————————————————————————————
  # Fill arming
  # ——————————————————————————————————————————————————————————————

  describe "fill arming" do
    test "schedule with no trigger flag does not arm at front_time" do
      stop_genserver(FeedingScheduler)

      now = current_time_truncated()

      _schedule =
        create_feeding_schedule!(
          move_to_front_limit_time: now,
          enabled: true
        )

      {:ok, _pid} = FeedingScheduler.start_link()
      FeedingScheduler.force_check()
      Process.sleep(100)

      sched_state = :sys.get_state(FeedingScheduler)
      assert sched_state.armed_fill_until_mono == nil
      assert sched_state.armed_for_schedule_id == nil
    end

    test "schedule with trigger flag arms at front_time" do
      stop_genserver(FeedingScheduler)

      trigger = create_equipment!("arm_trigger", "feeding")

      now = current_time_truncated()

      schedule =
        create_feeding_schedule!(
          move_to_front_limit_time: now,
          feedin_front_limit_bucket_id: trigger.id,
          enabled: true
        )

      {:ok, _pid} = FeedingScheduler.start_link()
      FeedingScheduler.force_check()
      Process.sleep(150)

      sched_state = :sys.get_state(FeedingScheduler)
      assert is_integer(sched_state.armed_fill_until_mono)
      assert sched_state.armed_for_schedule_id == schedule.id
      assert sched_state.last_armed_minute == now
    end

    test "does not re-arm in same minute" do
      stop_genserver(FeedingScheduler)

      trigger = create_equipment!("nodouble_trigger", "feeding")

      now = current_time_truncated()

      schedule =
        create_feeding_schedule!(
          move_to_front_limit_time: now,
          feedin_front_limit_bucket_id: trigger.id,
          enabled: true
        )

      {:ok, _pid} = FeedingScheduler.start_link()

      :sys.replace_state(FeedingScheduler, fn state ->
        state
        |> Map.put(:armed_fill_until_mono, nil)
        |> Map.put(:armed_for_schedule_id, nil)
        |> Map.put(:last_armed_minute, now)
      end)

      FeedingScheduler.force_check()
      Process.sleep(150)

      sched_state = :sys.get_state(FeedingScheduler)
      assert sched_state.armed_fill_until_mono == nil
      assert sched_state.armed_for_schedule_id == nil
      _ = schedule
    end
  end

  describe "fill firing" do
    test "fires FeedIn.turn_on once all feeding buckets at_front" do
      stop_genserver(FeedingScheduler)

      bucket = create_equipment!("fire_bucket", "feeding")
      {_n1, _p1, _d1} = start_feeding!(name: "fire_bucket")

      create_equipment!("fire_feedin", "feed_in")
      {_n2, _p2, _d2} = start_feed_in!(name: "fire_feedin")

      stub_read_direct(fn
        "fire_bucket_am" -> {:ok, %{state: 1}}
        "fire_bucket_front" -> {:ok, %{state: 1}}
        "fire_bucket_back" -> {:ok, %{state: 0}}
        "fire_feedin_am" -> {:ok, %{state: 1}}
        "fire_feedin_full" -> {:ok, %{state: 0}}
        "fire_feedin_fb" -> {:ok, %{state: 0}}
        "fire_feedin_fill" -> {:ok, %{state: 0}}
        "fire_feedin_trip" -> {:ok, %{state: 0}}
        _ -> {:ok, %{state: 0}}
      end)

      wait_for_init(300)

      schedule =
        create_feeding_schedule!(
          move_to_front_limit_time: ~T[03:00:00],
          feedin_front_limit_bucket_id: bucket.id,
          enabled: true
        )

      {:ok, _pid} = FeedingScheduler.start_link()

      :sys.replace_state(FeedingScheduler, fn state ->
        state
        |> Map.put(
          :armed_fill_until_mono,
          System.monotonic_time(:millisecond) + :timer.minutes(10)
        )
        |> Map.put(:armed_for_schedule_id, schedule.id)
      end)

      FeedingScheduler.force_check()
      Process.sleep(150)

      sched_state = :sys.get_state(FeedingScheduler)
      assert sched_state.armed_fill_until_mono == nil
      assert sched_state.armed_for_schedule_id == nil

      status = FeedIn.status("fire_feedin")
      assert status.commanded_on == true
    end

    test "does not fire when not all buckets at_front" do
      stop_genserver(FeedingScheduler)

      bucket = create_equipment!("hold_bucket", "feeding")
      {_n1, _p1, _d1} = start_feeding!(name: "hold_bucket")

      create_equipment!("hold_feedin", "feed_in")
      {_n2, _p2, _d2} = start_feed_in!(name: "hold_feedin")

      # bucket is NOT at front
      stub_read_direct(fn
        "hold_bucket_am" -> {:ok, %{state: 1}}
        "hold_bucket_front" -> {:ok, %{state: 0}}
        "hold_bucket_back" -> {:ok, %{state: 1}}
        "hold_feedin_am" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      wait_for_init(300)

      schedule =
        create_feeding_schedule!(
          move_to_front_limit_time: ~T[03:00:00],
          feedin_front_limit_bucket_id: bucket.id,
          enabled: true
        )

      {:ok, _pid} = FeedingScheduler.start_link()

      armed_until = System.monotonic_time(:millisecond) + :timer.minutes(10)

      :sys.replace_state(FeedingScheduler, fn state ->
        state
        |> Map.put(:armed_fill_until_mono, armed_until)
        |> Map.put(:armed_for_schedule_id, schedule.id)
      end)

      FeedingScheduler.force_check()
      Process.sleep(150)

      sched_state = :sys.get_state(FeedingScheduler)
      assert sched_state.armed_fill_until_mono == armed_until
      assert sched_state.armed_for_schedule_id == schedule.id

      status = FeedIn.status("hold_feedin")
      assert status.commanded_on == false
    end

    test "30-minute arm timeout returns scheduler to idle" do
      stop_genserver(FeedingScheduler)

      trigger = create_equipment!("timeout_bucket", "feeding")

      _schedule =
        create_feeding_schedule!(
          move_to_front_limit_time: ~T[03:00:00],
          feedin_front_limit_bucket_id: trigger.id,
          enabled: true
        )

      {:ok, _pid} = FeedingScheduler.start_link()

      stale_armed = System.monotonic_time(:millisecond) - :timer.minutes(1)

      :sys.replace_state(FeedingScheduler, fn state ->
        state
        |> Map.put(:armed_fill_until_mono, stale_armed)
        |> Map.put(:armed_for_schedule_id, 999)
      end)

      FeedingScheduler.force_check()
      Process.sleep(150)

      sched_state = :sys.get_state(FeedingScheduler)
      assert sched_state.armed_fill_until_mono == nil
      assert sched_state.armed_for_schedule_id == nil
    end

    test "skips fill when FeedIn already running" do
      stop_genserver(FeedingScheduler)

      bucket = create_equipment!("dup_bucket", "feeding")
      {_n1, _p1, _d1} = start_feeding!(name: "dup_bucket")

      create_equipment!("dup_feedin", "feed_in")
      {_n2, _p2, _d2} = start_feed_in!(name: "dup_feedin")

      stub_read_direct(fn
        "dup_bucket_am" -> {:ok, %{state: 1}}
        "dup_bucket_front" -> {:ok, %{state: 1}}
        "dup_bucket_back" -> {:ok, %{state: 0}}
        "dup_feedin_am" -> {:ok, %{state: 1}}
        "dup_feedin_fb" -> {:ok, %{state: 1}}
        "dup_feedin_fill" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      wait_for_init(300)

      schedule =
        create_feeding_schedule!(
          move_to_front_limit_time: ~T[03:00:00],
          feedin_front_limit_bucket_id: bucket.id,
          enabled: true
        )

      {:ok, _pid} = FeedingScheduler.start_link()

      armed_until = System.monotonic_time(:millisecond) + :timer.minutes(10)

      :sys.replace_state(FeedingScheduler, fn state ->
        state
        |> Map.put(:armed_fill_until_mono, armed_until)
        |> Map.put(:armed_for_schedule_id, schedule.id)
      end)

      FeedingScheduler.force_check()
      Process.sleep(150)

      sched_state = :sys.get_state(FeedingScheduler)
      # arm stays — precheck blocked the fire, but the arm hasn't timed out
      assert sched_state.armed_fill_until_mono == armed_until
    end
  end

  # ——————————————————————————————————————————————————————————————
  # Phase / timeline
  # ——————————————————————————————————————————————————————————————

  describe "get_timeline/0" do
    test "returns offline timeline when scheduler not running" do
      stop_genserver(FeedingScheduler)

      timeline = FeedingScheduler.get_timeline()
      assert timeline.current.phase == :unknown
      assert timeline.previous == nil
    end

    test "reports idle_position_error when no buckets exist" do
      stop_genserver(FeedingScheduler)

      {:ok, _pid} = FeedingScheduler.start_link()
      Process.sleep(100)

      timeline = FeedingScheduler.get_timeline()
      assert timeline.current.phase == :idle_position_error
    end

    test "reports idle_at_front when all buckets at_front" do
      stop_genserver(FeedingScheduler)

      create_equipment!("phase_at_front", "feeding")
      {_n, _p, _d} = start_feeding!(name: "phase_at_front")

      stub_read_direct(fn
        "phase_at_front_am" -> {:ok, %{state: 1}}
        "phase_at_front_front" -> {:ok, %{state: 1}}
        "phase_at_front_back" -> {:ok, %{state: 0}}
        _ -> {:ok, %{state: 0}}
      end)

      wait_for_init(300)

      now = current_time_truncated()
      back_time = Time.add(now, 3600, :second)

      create_feeding_schedule!(
        move_to_back_limit_time: back_time,
        enabled: true
      )

      {:ok, _pid} = FeedingScheduler.start_link()
      Process.sleep(100)

      timeline = FeedingScheduler.get_timeline()
      assert timeline.current.phase == :idle_at_front
      assert timeline.next.label == "move to BACK"
      assert timeline.next.time == back_time
    end

    test "tracks previous_phase across phase transitions" do
      stop_genserver(FeedingScheduler)

      {:ok, _pid} = FeedingScheduler.start_link()
      Process.sleep(50)

      :sys.replace_state(FeedingScheduler, fn state ->
        state
        |> Map.put(:last_seen_phase, :moving_to_back)
        |> Map.put(:previous_phase, :idle_at_front)
      end)

      timeline = FeedingScheduler.get_timeline()
      assert timeline.previous == %{phase: :idle_at_front}
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

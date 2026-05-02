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

    test "preserves fill_state for schedules that still exist" do
      stop_genserver(FeedingScheduler)

      trigger = create_equipment!("preserve_trigger", "feeding")

      schedule =
        create_feeding_schedule!(
          move_to_front_limit_time: ~T[03:00:00],
          feedin_front_limit_bucket_id: trigger.id,
          enabled: true
        )

      {:ok, _pid} = FeedingScheduler.start_link()

      :sys.replace_state(FeedingScheduler, fn state ->
        fill_state = %{
          state: :waiting_front_limit_signal,
          prev_at_front: false,
          reached_at: nil,
          waiting_entered_at: System.monotonic_time(:millisecond),
          fill_issued_at: nil,
          last_fired_minute: ~T[03:00:00]
        }

        Map.put(state, :fill_states, %{schedule.id => fill_state})
      end)

      assert :ok = FeedingScheduler.reload_schedules()
      Process.sleep(100)

      sched_state = :sys.get_state(FeedingScheduler)
      preserved = sched_state.fill_states[schedule.id]
      assert preserved.state == :waiting_front_limit_signal
      assert preserved.last_fired_minute == ~T[03:00:00]
    end

    test "drops fill_state for schedules that no longer exist" do
      stop_genserver(FeedingScheduler)

      {:ok, _pid} = FeedingScheduler.start_link()

      :sys.replace_state(FeedingScheduler, fn state ->
        ghost = %{
          state: :pending_fill,
          prev_at_front: true,
          reached_at: System.monotonic_time(:millisecond),
          waiting_entered_at: nil,
          fill_issued_at: nil,
          last_fired_minute: nil
        }

        Map.put(state, :fill_states, %{99_999 => ghost})
      end)

      assert :ok = FeedingScheduler.reload_schedules()
      Process.sleep(100)

      sched_state = :sys.get_state(FeedingScheduler)
      assert sched_state.fill_states == %{}
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
  # Fill state machine
  # ——————————————————————————————————————————————————————————————

  describe "fill state machine — entry" do
    test "schedule with no trigger bucket stays in :idle at front_time" do
      stop_genserver(FeedingScheduler)

      now = current_time_truncated()

      schedule =
        create_feeding_schedule!(
          move_to_front_limit_time: now,
          enabled: true
        )

      {:ok, _pid} = FeedingScheduler.start_link()
      FeedingScheduler.force_check()
      Process.sleep(100)

      sched_state = :sys.get_state(FeedingScheduler)
      fill = sched_state.fill_states[schedule.id] || %{state: :idle}
      assert fill.state == :idle
    end

    test "schedule with trigger bucket transitions to :waiting at front_time" do
      stop_genserver(FeedingScheduler)

      trigger = create_equipment!("waiting_trigger", "feeding")
      {_name, _pid, _devs} = start_feeding!(name: "waiting_trigger")

      stub_read_direct(fn
        "waiting_trigger_am" -> {:ok, %{state: 1}}
        "waiting_trigger_front" -> {:ok, %{state: 0}}
        "waiting_trigger_back" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      wait_for_init()

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
      fill = sched_state.fill_states[schedule.id]
      assert fill.state == :waiting_front_limit_signal
      assert fill.prev_at_front == false
      assert fill.last_fired_minute == now
    end

    test "does not double-fire :waiting in same minute after returning to :idle" do
      stop_genserver(FeedingScheduler)

      trigger = create_equipment!("nodouble_trigger", "feeding")
      {_name, _pid, _devs} = start_feeding!(name: "nodouble_trigger")

      stub_read_direct(fn
        "nodouble_trigger_am" -> {:ok, %{state: 1}}
        "nodouble_trigger_front" -> {:ok, %{state: 0}}
        "nodouble_trigger_back" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      wait_for_init()

      now = current_time_truncated()

      schedule =
        create_feeding_schedule!(
          move_to_front_limit_time: now,
          feedin_front_limit_bucket_id: trigger.id,
          enabled: true
        )

      {:ok, _pid} = FeedingScheduler.start_link()

      :sys.replace_state(FeedingScheduler, fn state ->
        fill_state = %{
          state: :idle,
          prev_at_front: nil,
          reached_at: nil,
          waiting_entered_at: nil,
          fill_issued_at: nil,
          last_fired_minute: now
        }

        Map.put(state, :fill_states, %{schedule.id => fill_state})
      end)

      FeedingScheduler.force_check()
      Process.sleep(150)

      sched_state = :sys.get_state(FeedingScheduler)
      fill = sched_state.fill_states[schedule.id]
      assert fill.state == :idle
    end
  end

  describe "fill state machine — edge detection and timeout" do
    test "detects OFF→ON edge and transitions to :pending_fill" do
      stop_genserver(FeedingScheduler)

      trigger = create_equipment!("edge_trigger", "feeding")
      {_name, _pid, _devs} = start_feeding!(name: "edge_trigger")

      stub_read_direct(fn
        "edge_trigger_am" -> {:ok, %{state: 1}}
        "edge_trigger_front" -> {:ok, %{state: 1}}
        "edge_trigger_back" -> {:ok, %{state: 0}}
        _ -> {:ok, %{state: 0}}
      end)

      wait_for_init()

      schedule =
        create_feeding_schedule!(
          move_to_front_limit_time: ~T[03:00:00],
          feedin_front_limit_bucket_id: trigger.id,
          enabled: true
        )

      {:ok, _pid} = FeedingScheduler.start_link()

      :sys.replace_state(FeedingScheduler, fn state ->
        fill_state = %{
          state: :waiting_front_limit_signal,
          prev_at_front: false,
          reached_at: nil,
          waiting_entered_at: System.monotonic_time(:millisecond),
          fill_issued_at: nil,
          last_fired_minute: ~T[03:00:00]
        }

        Map.put(state, :fill_states, %{schedule.id => fill_state})
      end)

      FeedingScheduler.force_check()
      Process.sleep(150)

      sched_state = :sys.get_state(FeedingScheduler)
      fill = sched_state.fill_states[schedule.id]
      assert fill.state == :pending_fill
      assert fill.prev_at_front == true
      assert is_integer(fill.reached_at)
    end

    test "stays in :waiting_front_limit_signal when no edge" do
      stop_genserver(FeedingScheduler)

      trigger = create_equipment!("noedge_trigger", "feeding")
      {_name, _pid, _devs} = start_feeding!(name: "noedge_trigger")

      stub_read_direct(fn
        "noedge_trigger_am" -> {:ok, %{state: 1}}
        "noedge_trigger_front" -> {:ok, %{state: 0}}
        "noedge_trigger_back" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      wait_for_init()

      schedule =
        create_feeding_schedule!(
          move_to_front_limit_time: ~T[03:00:00],
          feedin_front_limit_bucket_id: trigger.id,
          enabled: true
        )

      {:ok, _pid} = FeedingScheduler.start_link()

      :sys.replace_state(FeedingScheduler, fn state ->
        fill_state = %{
          state: :waiting_front_limit_signal,
          prev_at_front: false,
          reached_at: nil,
          waiting_entered_at: System.monotonic_time(:millisecond),
          fill_issued_at: nil,
          last_fired_minute: ~T[03:00:00]
        }

        Map.put(state, :fill_states, %{schedule.id => fill_state})
      end)

      FeedingScheduler.force_check()
      Process.sleep(150)

      sched_state = :sys.get_state(FeedingScheduler)
      fill = sched_state.fill_states[schedule.id]
      assert fill.state == :waiting_front_limit_signal
      assert fill.prev_at_front == false
    end

    test "30 minute timeout returns to :idle preserving last_fired_minute" do
      stop_genserver(FeedingScheduler)

      trigger = create_equipment!("timeout_trigger", "feeding")
      {_name, _pid, _devs} = start_feeding!(name: "timeout_trigger")

      stub_read_direct(fn
        "timeout_trigger_am" -> {:ok, %{state: 1}}
        "timeout_trigger_front" -> {:ok, %{state: 0}}
        _ -> {:ok, %{state: 0}}
      end)

      wait_for_init()

      schedule =
        create_feeding_schedule!(
          move_to_front_limit_time: ~T[03:00:00],
          feedin_front_limit_bucket_id: trigger.id,
          enabled: true
        )

      {:ok, _pid} = FeedingScheduler.start_link()

      thirty_one_minutes_ago = System.monotonic_time(:millisecond) - :timer.minutes(31)

      :sys.replace_state(FeedingScheduler, fn state ->
        fill_state = %{
          state: :waiting_front_limit_signal,
          prev_at_front: false,
          reached_at: nil,
          waiting_entered_at: thirty_one_minutes_ago,
          fill_issued_at: nil,
          last_fired_minute: ~T[03:00:00]
        }

        Map.put(state, :fill_states, %{schedule.id => fill_state})
      end)

      FeedingScheduler.force_check()
      Process.sleep(150)

      sched_state = :sys.get_state(FeedingScheduler)
      fill = sched_state.fill_states[schedule.id]
      assert fill.state == :idle
      assert fill.last_fired_minute == ~T[03:00:00]
    end
  end

  describe "fill state machine — pending_fill" do
    test "issues FeedIn.turn_on after settle delay when pre-check passes" do
      stop_genserver(FeedingScheduler)

      create_equipment!("pf_feedin", "feed_in")
      {_n, _p, _d} = start_feed_in!(name: "pf_feedin")

      stub_read_direct(fn
        "pf_feedin_am" -> {:ok, %{state: 1}}
        "pf_feedin_full" -> {:ok, %{state: 0}}
        "pf_feedin_fb" -> {:ok, %{state: 0}}
        "pf_feedin_fill" -> {:ok, %{state: 0}}
        "pf_feedin_trip" -> {:ok, %{state: 0}}
        _ -> {:ok, %{state: 0}}
      end)

      wait_for_init(300)

      schedule =
        create_feeding_schedule!(
          move_to_front_limit_time: ~T[03:00:00],
          enabled: true
        )

      {:ok, _pid} = FeedingScheduler.start_link()

      thirty_one_seconds_ago = System.monotonic_time(:millisecond) - :timer.seconds(31)

      :sys.replace_state(FeedingScheduler, fn state ->
        fill_state = %{
          state: :pending_fill,
          prev_at_front: true,
          reached_at: thirty_one_seconds_ago,
          waiting_entered_at: nil,
          fill_issued_at: nil,
          last_fired_minute: ~T[03:00:00]
        }

        Map.put(state, :fill_states, %{schedule.id => fill_state})
      end)

      FeedingScheduler.force_check()
      Process.sleep(150)

      sched_state = :sys.get_state(FeedingScheduler)
      fill = sched_state.fill_states[schedule.id]
      assert fill.state == :verifying_fill_started
      assert is_integer(fill.fill_issued_at)

      # FeedIn should have been commanded on
      status = FeedIn.status("pf_feedin")
      assert status.commanded_on == true
    end

    test "stays in :pending_fill before settle delay elapses" do
      stop_genserver(FeedingScheduler)

      create_equipment!("settle_feedin", "feed_in")
      {_n, _p, _d} = start_feed_in!(name: "settle_feedin")

      stub_read_direct(fn
        "settle_feedin_am" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      wait_for_init(300)

      schedule =
        create_feeding_schedule!(
          move_to_front_limit_time: ~T[03:00:00],
          enabled: true
        )

      {:ok, _pid} = FeedingScheduler.start_link()

      :sys.replace_state(FeedingScheduler, fn state ->
        fill_state = %{
          state: :pending_fill,
          prev_at_front: true,
          # just reached, not 30s yet
          reached_at: System.monotonic_time(:millisecond),
          waiting_entered_at: nil,
          fill_issued_at: nil,
          last_fired_minute: ~T[03:00:00]
        }

        Map.put(state, :fill_states, %{schedule.id => fill_state})
      end)

      FeedingScheduler.force_check()
      Process.sleep(100)

      sched_state = :sys.get_state(FeedingScheduler)
      fill = sched_state.fill_states[schedule.id]
      assert fill.state == :pending_fill
    end

    test "skips fill and returns to :idle when FeedIn already running" do
      stop_genserver(FeedingScheduler)

      create_equipment!("running_feedin", "feed_in")
      {_n, _p, _d} = start_feed_in!(name: "running_feedin")

      # Mode AUTO, running_feedback ON => is_running: true
      stub_read_direct(fn
        "running_feedin_am" -> {:ok, %{state: 1}}
        "running_feedin_fb" -> {:ok, %{state: 1}}
        "running_feedin_fill" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      wait_for_init(300)

      schedule =
        create_feeding_schedule!(
          move_to_front_limit_time: ~T[03:00:00],
          enabled: true
        )

      {:ok, _pid} = FeedingScheduler.start_link()

      thirty_one_seconds_ago = System.monotonic_time(:millisecond) - :timer.seconds(31)

      :sys.replace_state(FeedingScheduler, fn state ->
        fill_state = %{
          state: :pending_fill,
          prev_at_front: true,
          reached_at: thirty_one_seconds_ago,
          waiting_entered_at: nil,
          fill_issued_at: nil,
          last_fired_minute: ~T[03:00:00]
        }

        Map.put(state, :fill_states, %{schedule.id => fill_state})
      end)

      FeedingScheduler.force_check()
      Process.sleep(100)

      sched_state = :sys.get_state(FeedingScheduler)
      fill = sched_state.fill_states[schedule.id]
      assert fill.state == :idle
      assert fill.last_fired_minute == ~T[03:00:00]
    end

    test "skips fill and returns to :idle when FeedIn in MANUAL mode" do
      stop_genserver(FeedingScheduler)

      create_equipment!("manual_feedin", "feed_in")
      {_n, _p, _d} = start_feed_in!(name: "manual_feedin")

      stub_read_direct(fn _ -> {:ok, %{state: 0}} end)
      wait_for_init(300)

      schedule =
        create_feeding_schedule!(
          move_to_front_limit_time: ~T[03:00:00],
          enabled: true
        )

      {:ok, _pid} = FeedingScheduler.start_link()

      thirty_one_seconds_ago = System.monotonic_time(:millisecond) - :timer.seconds(31)

      :sys.replace_state(FeedingScheduler, fn state ->
        fill_state = %{
          state: :pending_fill,
          prev_at_front: true,
          reached_at: thirty_one_seconds_ago,
          waiting_entered_at: nil,
          fill_issued_at: nil,
          last_fired_minute: ~T[03:00:00]
        }

        Map.put(state, :fill_states, %{schedule.id => fill_state})
      end)

      FeedingScheduler.force_check()
      Process.sleep(100)

      sched_state = :sys.get_state(FeedingScheduler)
      fill = sched_state.fill_states[schedule.id]
      assert fill.state == :idle
    end
  end

  describe "fill state machine — verify" do
    test "returns to :idle after verify window elapses" do
      stop_genserver(FeedingScheduler)

      create_equipment!("verify_feedin", "feed_in")
      {_n, _p, _d} = start_feed_in!(name: "verify_feedin")

      stub_read_direct(fn
        "verify_feedin_am" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      wait_for_init(300)

      schedule =
        create_feeding_schedule!(
          move_to_front_limit_time: ~T[03:00:00],
          enabled: true
        )

      {:ok, _pid} = FeedingScheduler.start_link()

      six_seconds_ago = System.monotonic_time(:millisecond) - :timer.seconds(6)

      :sys.replace_state(FeedingScheduler, fn state ->
        fill_state = %{
          state: :verifying_fill_started,
          prev_at_front: true,
          reached_at: nil,
          waiting_entered_at: nil,
          fill_issued_at: six_seconds_ago,
          last_fired_minute: ~T[03:00:00]
        }

        Map.put(state, :fill_states, %{schedule.id => fill_state})
      end)

      FeedingScheduler.force_check()
      Process.sleep(100)

      sched_state = :sys.get_state(FeedingScheduler)
      fill = sched_state.fill_states[schedule.id]
      assert fill.state == :idle
      assert fill.last_fired_minute == ~T[03:00:00]
    end

    test "stays in :verifying_fill_started before verify window elapses" do
      stop_genserver(FeedingScheduler)

      create_equipment!("v2_feedin", "feed_in")
      {_n, _p, _d} = start_feed_in!(name: "v2_feedin")

      stub_read_direct(fn _ -> {:ok, %{state: 0}} end)
      wait_for_init(300)

      schedule =
        create_feeding_schedule!(
          move_to_front_limit_time: ~T[03:00:00],
          enabled: true
        )

      {:ok, _pid} = FeedingScheduler.start_link()

      :sys.replace_state(FeedingScheduler, fn state ->
        fill_state = %{
          state: :verifying_fill_started,
          prev_at_front: true,
          reached_at: nil,
          waiting_entered_at: nil,
          fill_issued_at: System.monotonic_time(:millisecond),
          last_fired_minute: ~T[03:00:00]
        }

        Map.put(state, :fill_states, %{schedule.id => fill_state})
      end)

      FeedingScheduler.force_check()
      Process.sleep(100)

      sched_state = :sys.get_state(FeedingScheduler)
      fill = sched_state.fill_states[schedule.id]
      assert fill.state == :verifying_fill_started
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

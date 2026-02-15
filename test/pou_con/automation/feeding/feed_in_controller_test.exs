defmodule PouCon.Automation.Feeding.FeedInControllerTest do
  use PouCon.DataCase, async: false
  import Mox
  import PouCon.AutomationTestHelpers

  alias PouCon.Automation.Feeding.FeedInController

  setup :verify_on_exit!

  setup do
    setup_automation_test()

    on_exit(fn ->
      stop_genserver(FeedInController)
      Ecto.Adapters.SQL.Sandbox.mode(PouCon.Repo, :manual)
    end)

    :ok
  end

  describe "start_link/1" do
    test "starts the controller successfully" do
      stop_genserver(FeedInController)

      assert {:ok, pid} = FeedInController.start_link()
      assert Process.alive?(pid)
    end

    test "registers with module name" do
      stop_genserver(FeedInController)

      {:ok, pid} = FeedInController.start_link()
      assert Process.whereis(FeedInController) == pid
    end
  end

  describe "reload_schedules/0" do
    test "sends reload message to controller" do
      stop_genserver(FeedInController)

      {:ok, _pid} = FeedInController.start_link()
      assert :ok = FeedInController.reload_schedules()
      Process.sleep(100)
    end
  end

  describe "schedule_updated/0" do
    test "calls reload_schedules" do
      stop_genserver(FeedInController)

      {:ok, _pid} = FeedInController.start_link()
      assert :ok = FeedInController.schedule_updated()
      Process.sleep(100)
    end
  end

  describe "trigger bucket monitoring" do
    test "handles missing feeding controller gracefully" do
      stop_genserver(FeedInController)

      # Create a feeding equipment (trigger bucket) and a schedule referencing it
      trigger_bucket = create_equipment!("trigger_bucket_1", "feeding")

      create_feeding_schedule!(
        move_to_back_limit_time: ~T[06:00:00],
        move_to_front_limit_time: ~T[05:00:00],
        feedin_front_limit_bucket_id: trigger_bucket.id,
        enabled: true
      )

      {:ok, pid} = FeedInController.start_link(poll_interval_ms: 100)
      wait_for_init(300)

      # Should not crash even though feeding controller isn't started
      assert Process.alive?(pid)
    end

    test "skips trigger bucket in MANUAL mode" do
      stop_genserver(FeedInController)

      trigger_bucket = create_equipment!("manual_trigger", "feeding")
      {_name, _pid, _devs} = start_feeding!(name: "manual_trigger")

      create_feeding_schedule!(
        move_to_back_limit_time: ~T[06:00:00],
        move_to_front_limit_time: ~T[05:00:00],
        feedin_front_limit_bucket_id: trigger_bucket.id,
        enabled: true
      )

      # Set feeding in MANUAL mode
      stub_read_direct(fn _ -> {:ok, %{state: 0}} end)
      wait_for_init()

      {:ok, pid} = FeedInController.start_link(poll_interval_ms: 100)
      wait_for_init(300)

      # Should keep running without issues
      assert Process.alive?(pid)
    end

    test "skips trigger bucket with error" do
      stop_genserver(FeedInController)

      trigger_bucket = create_equipment!("error_trigger", "feeding")
      {_name, _pid, _devs} = start_feeding!(name: "error_trigger")

      create_feeding_schedule!(
        move_to_back_limit_time: ~T[06:00:00],
        move_to_front_limit_time: ~T[05:00:00],
        feedin_front_limit_bucket_id: trigger_bucket.id,
        enabled: true
      )

      # Set feeding in AUTO mode but with timeout (no data)
      stub_read_direct(fn
        "error_trigger_am" -> {:ok, %{state: 1}}
        _ -> {:error, :timeout}
      end)

      wait_for_init(300)

      {:ok, pid} = FeedInController.start_link(poll_interval_ms: 100)
      wait_for_init(300)

      assert Process.alive?(pid)
    end
  end

  describe "error resilience" do
    test "continues operating after controller restart" do
      stop_genserver(FeedInController)

      {:ok, pid1} = FeedInController.start_link()
      wait_for_init()
      GenServer.stop(pid1)

      {:ok, pid2} = FeedInController.start_link()
      wait_for_init()
      assert Process.alive?(pid2)
    end

    test "handles no schedules gracefully" do
      stop_genserver(FeedInController)

      {:ok, pid} = FeedInController.start_link(poll_interval_ms: 100)
      wait_for_init(300)

      assert Process.alive?(pid)
    end
  end
end

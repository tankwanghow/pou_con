defmodule PouCon.Automation.Lighting.LightSchedulerTest do
  use PouCon.DataCase, async: false
  import Mox
  import PouCon.AutomationTestHelpers

  alias PouCon.Automation.Lighting.LightScheduler
  alias PouCon.Equipment.Controllers.Light

  setup :verify_on_exit!

  setup do
    setup_automation_test()

    on_exit(fn ->
      stop_genserver(LightScheduler)
      Ecto.Adapters.SQL.Sandbox.mode(PouCon.Repo, :manual)
    end)

    :ok
  end

  describe "start_link/1" do
    test "starts the scheduler successfully" do
      stop_genserver(LightScheduler)

      assert {:ok, pid} = LightScheduler.start_link()
      assert Process.alive?(pid)
    end

    test "registers with module name" do
      stop_genserver(LightScheduler)

      {:ok, pid} = LightScheduler.start_link()
      assert Process.whereis(LightScheduler) == pid
    end
  end

  describe "same-day schedule execution" do
    test "turns on light when current time is within schedule" do
      stop_genserver(LightScheduler)

      # Create equipment and start controller
      equipment = create_equipment!("sched_light_1", "light")
      {_name, _pid, _devs} = start_light!(name: "sched_light_1")

      # Set light in AUTO mode
      stub_read_direct(fn
        "sched_light_1_am" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)
      wait_for_init()

      # Create schedule that includes current time
      now = current_time_truncated()
      on_time = Time.add(now, -60, :second)
      off_time = Time.add(now, 3600, :second)

      create_light_schedule!(equipment, on_time, off_time)

      {:ok, _pid} = LightScheduler.start_link()
      LightScheduler.force_check()
      Process.sleep(200)

      # Light should be commanded on
      status = Light.status("sched_light_1")
      assert status.commanded_on == true
    end

    test "turns off light when current time is outside schedule" do
      stop_genserver(LightScheduler)

      equipment = create_equipment!("sched_light_2", "light")
      {_name, _pid, _devs} = start_light!(name: "sched_light_2")

      # Set light in AUTO mode, currently ON
      stub_read_direct(fn
        "sched_light_2_am" -> {:ok, %{state: 1}}
        "sched_light_2_coil" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)
      wait_for_init()

      # Turn light on first
      Light.turn_on("sched_light_2")
      Process.sleep(100)

      # Create schedule that ended an hour ago
      now = current_time_truncated()
      on_time = Time.add(now, -7200, :second)
      off_time = Time.add(now, -3600, :second)

      # Avoid negative wrap-around issues
      if Time.compare(on_time, off_time) == :lt do
        create_light_schedule!(equipment, on_time, off_time)

        {:ok, _pid} = LightScheduler.start_link()
        LightScheduler.force_check()
        Process.sleep(200)

        status = Light.status("sched_light_2")
        assert status.commanded_on == false
      end
    end
  end

  describe "overnight schedule support" do
    test "time_in_range? handles overnight schedule correctly" do
      # Overnight: 18:00 → 06:00
      on_time = ~T[18:00:00]
      off_time = ~T[06:00:00]

      # 20:00 should be in range
      assert time_in_range?(~T[20:00:00], on_time, off_time) == true

      # 03:00 should be in range (after midnight)
      assert time_in_range?(~T[03:00:00], on_time, off_time) == true

      # 12:00 should NOT be in range
      assert time_in_range?(~T[12:00:00], on_time, off_time) == false

      # 06:00 should NOT be in range (off_time boundary)
      assert time_in_range?(~T[06:00:00], on_time, off_time) == false

      # 18:00 should be in range (on_time boundary)
      assert time_in_range?(~T[18:00:00], on_time, off_time) == true
    end

    test "time_in_range? handles same-day schedule correctly" do
      on_time = ~T[06:00:00]
      off_time = ~T[18:00:00]

      assert time_in_range?(~T[12:00:00], on_time, off_time) == true
      assert time_in_range?(~T[06:00:00], on_time, off_time) == true
      assert time_in_range?(~T[18:00:00], on_time, off_time) == false
      assert time_in_range?(~T[20:00:00], on_time, off_time) == false
      assert time_in_range?(~T[03:00:00], on_time, off_time) == false
    end
  end

  describe "mode filtering" do
    test "skips lights in MANUAL mode" do
      stop_genserver(LightScheduler)

      equipment = create_equipment!("manual_light", "light")
      {_name, _pid, _devs} = start_light!(name: "manual_light")

      # Set light in MANUAL mode (auto_manual DI = 0)
      stub_read_direct(fn _ -> {:ok, %{state: 0}} end)
      wait_for_init()

      now = current_time_truncated()
      on_time = Time.add(now, -60, :second)
      off_time = Time.add(now, 3600, :second)

      create_light_schedule!(equipment, on_time, off_time)

      {:ok, _pid} = LightScheduler.start_link()
      LightScheduler.force_check()
      Process.sleep(200)

      # Light should remain off since it's in MANUAL mode
      status = Light.status("manual_light")
      assert status.commanded_on == false
    end
  end

  describe "error handling" do
    test "handles unavailable controller gracefully" do
      stop_genserver(LightScheduler)

      # Create equipment but don't start controller
      equipment = create_equipment!("ghost_light", "light")

      now = current_time_truncated()
      on_time = Time.add(now, -60, :second)
      off_time = Time.add(now, 3600, :second)

      create_light_schedule!(equipment, on_time, off_time)

      {:ok, pid} = LightScheduler.start_link()
      LightScheduler.force_check()
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

  defp time_in_range?(current_time, on_time, off_time) do
    if Time.compare(on_time, off_time) in [:eq, :gt] do
      Time.compare(current_time, on_time) in [:eq, :gt] or
        Time.compare(current_time, off_time) == :lt
    else
      Time.compare(current_time, on_time) in [:eq, :gt] and
        Time.compare(current_time, off_time) == :lt
    end
  end
end

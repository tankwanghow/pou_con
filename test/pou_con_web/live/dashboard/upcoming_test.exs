defmodule PouConWeb.Live.Dashboard.UpcomingTest do
  use ExUnit.Case, async: true

  alias PouConWeb.Live.Dashboard.Upcoming

  defp light(title, on, off), do: %{equipment: %{title: title}, on_time: on, off_time: off}

  defp egg(title, start, stop),
    do: %{equipment: %{title: title}, start_time: start, stop_time: stop}

  describe "next_light/2" do
    test "picks the soonest on/off across lights" do
      schedules = [
        light("Light 1", ~T[06:00:00], ~T[18:00:00]),
        light("Light 2", ~T[07:00:00], ~T[17:30:00])
      ]

      assert %{title: "Light 2", action: "OFF", seconds: 1800, at: ~T[17:30:00]} =
               Upcoming.next_light(schedules, ~T[17:00:00])
    end

    test "wraps past midnight" do
      assert %{title: "Light 1", action: "ON", seconds: 25_200} =
               Upcoming.next_light([light("Light 1", ~T[06:00:00], ~T[18:00:00])], ~T[23:00:00])
    end

    test "an event at exactly now is treated as tomorrow" do
      assert %{action: "OFF", seconds: 43_200} =
               Upcoming.next_light([light("L", ~T[06:00:00], ~T[18:00:00])], ~T[06:00:00])
    end

    test "falls back to the equipment name, and nil when no schedules" do
      s = %{
        equipment: %{title: nil, name: "light_1"},
        on_time: ~T[06:00:00],
        off_time: ~T[18:00:00]
      }

      assert %{title: "light_1"} = Upcoming.next_light([s], ~T[05:00:00])
      assert Upcoming.next_light([], ~T[05:00:00]) == nil
    end
  end

  describe "next_egg/2" do
    test "uses start/stop times" do
      assert %{title: "Egg 1", action: "START", seconds: 2400} =
               Upcoming.next_egg([egg("Egg 1", ~T[09:40:00], ~T[10:00:00])], ~T[09:00:00])
    end
  end

  describe "environment/1" do
    @steady %{
      enabled: true,
      current_step: 1,
      pending_step: 1,
      seconds_until_step_change: 0,
      delta_boost_active: false,
      temp_delta: nil,
      avg_temp: 28.0,
      step_configs: %{1 => %{fans: 3, pumps: 0}, 2 => %{fans: 6, pumps: 2}},
      highest_step_info: %{fans: 6, pumps: 2}
    }

    test "steady step shows the current step and its fans/pumps" do
      assert Upcoming.environment(@steady) ==
               {:step, %{step: 1, fans: 3, pumps: 0, pending: nil}}
    end

    test "pending change is attached to the current step" do
      env = %{@steady | pending_step: 2, seconds_until_step_change: 45}

      assert {:step, %{step: 1, fans: 3, pending: %{to_step: 2, fans: {3, 6}, seconds: 45}}} =
               Upcoming.environment(env)
    end

    test "pending change includes pumps and average temperature" do
      env = %{@steady | pending_step: 2, seconds_until_step_change: 45}

      assert {:step, %{pending: %{pumps: {0, 2}, avg_temp: 28.0}}} = Upcoming.environment(env)

      assert {:step, %{pending: nil}} =
               Upcoming.environment(%{env | seconds_until_step_change: 0})
    end

    test "delta boost reports the boosted fans/pumps and delta" do
      env = %{@steady | delta_boost_active: true, temp_delta: 2.3}
      assert Upcoming.environment(env) == {:boost, %{fans: 6, pumps: 2, delta: 2.3}}
    end

    test "disabled or unavailable" do
      assert Upcoming.environment(%{@steady | enabled: false}) == :off
      assert Upcoming.environment(nil) == :off
    end
  end

  describe "feeding/2" do
    test "in-progress phases" do
      assert Upcoming.feeding(%{current: %{phase: :moving_to_back}}, ~T[10:00:00]) ==
               {:now, "moving to BACK"}

      assert Upcoming.feeding(%{current: %{phase: :filling}}, ~T[10:00:00]) == {:now, "filling"}
    end

    test "next scheduled move" do
      timeline = %{
        current: %{phase: :idle_at_front},
        next: %{label: "move to BACK", time: ~T[10:12:30]}
      }

      assert Upcoming.feeding(timeline, ~T[10:00:00]) ==
               {:next, %{action: "→ BACK", seconds: 750, at: ~T[10:12:30]}}
    end

    test "nothing scheduled or scheduler offline" do
      assert Upcoming.feeding(
               %{current: %{phase: :idle_at_front}, next: %{label: "x", time: nil}},
               ~T[10:00:00]
             ) ==
               :none

      assert Upcoming.feeding(%{current: %{phase: :unknown}, next: %{time: nil}}, ~T[10:00:00]) ==
               :none
    end
  end

  describe "when_text/2" do
    test "MM:SS under an hour, clock time otherwise" do
      assert Upcoming.when_text(750, ~T[10:12:30]) == "in 12:30"
      assert Upcoming.when_text(5, nil) == "in 00:05"
      assert Upcoming.when_text(3600, ~T[18:00:00]) == "at 18:00"
    end

    test "both forms are the same width" do
      assert String.length(Upcoming.when_text(59, nil)) ==
               String.length(Upcoming.when_text(7200, ~T[06:00:00]))
    end
  end
end

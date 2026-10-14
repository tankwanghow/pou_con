defmodule PouConWeb.Live.Dashboard.Upcoming do
  @moduledoc """
  Works out the next event per category for the dashboard's Upcoming row:
  feeding moves, environment step changes, light on/off and egg start/stop.

  Pure functions over already-fetched data (schedules, `FeedingScheduler`
  timeline, `EnvironmentController` status) and the current local time, so
  they can be tested without the GenServers.
  """

  @day 86_400

  @doc "Soonest ON/OFF across enabled light schedules, or nil."
  def next_light(schedules, now), do: next_event(schedules, now, on_time: "ON", off_time: "OFF")

  @doc "Soonest START/STOP across enabled egg collection schedules, or nil."
  def next_egg(schedules, now),
    do: next_event(schedules, now, start_time: "START", stop_time: "STOP")

  defp next_event(schedules, now, fields) do
    schedules
    |> Enum.flat_map(fn schedule ->
      for {field, action} <- fields, at = Map.get(schedule, field), at != nil do
        %{title: title(schedule), action: action, at: at, seconds: seconds_until(at, now)}
      end
    end)
    |> Enum.min_by(& &1.seconds, fn -> nil end)
  end

  @doc """
  Environment control state for the dashboard: `{:step, %{step, fans, pumps,
  pending}}` (pending is nil or the counting-down change), `{:boost, %{fans,
  pumps, delta}}` during delta boost, or `:off` when disabled/unavailable.
  """
  def environment(%{enabled: true, delta_boost_active: true} = status) do
    info = status.highest_step_info || %{fans: 0, pumps: 0}
    {:boost, %{fans: info.fans, pumps: info.pumps, delta: status.temp_delta}}
  end

  def environment(%{enabled: true} = status) do
    info = Map.get(status.step_configs, status.current_step, %{fans: 0, pumps: 0})

    {:step,
     %{
       step: status.current_step,
       fans: info.fans,
       pumps: info.pumps,
       pending: pending_change(status)
     }}
  end

  def environment(_status), do: :off

  defp pending_change(%{pending_step: p, current_step: c, seconds_until_step_change: s} = status)
       when not is_nil(p) and not is_nil(c) and p != c and is_integer(s) and s > 0 do
    from = Map.get(status.step_configs, c, %{fans: 0, pumps: 0})
    to = Map.get(status.step_configs, p, %{fans: 0, pumps: 0})

    %{
      to_step: p,
      fans: {from.fans, to.fans},
      pumps: {from.pumps, to.pumps},
      seconds: s,
      avg_temp: status.avg_temp
    }
  end

  defp pending_change(_status), do: nil

  @doc """
  Feeding from `FeedingScheduler.get_timeline/0`: `{:now, text}` while moving
  or filling, `{:next, event}` for the next scheduled move, or `:none`.
  """
  def feeding(%{current: %{phase: :moving_to_back}}, _now), do: {:now, "moving to BACK"}
  def feeding(%{current: %{phase: :moving_to_front}}, _now), do: {:now, "moving to FRONT"}
  def feeding(%{current: %{phase: :filling}}, _now), do: {:now, "filling"}

  def feeding(%{next: %{label: label, time: %Time{} = at}}, now) do
    action = if label =~ "BACK", do: "→ BACK", else: "→ FRONT"
    {:next, %{action: action, seconds: seconds_until(at, now), at: at}}
  end

  def feeding(_timeline, _now), do: :none

  @doc "`in MM:SS` under an hour, else `at HH:MM` (same width)."
  def when_text(seconds, _at) when seconds < 3600 do
    "in " <> pad2(div(seconds, 60)) <> ":" <> pad2(rem(seconds, 60))
  end

  def when_text(_seconds, %Time{} = at), do: "at " <> pad2(at.hour) <> ":" <> pad2(at.minute)

  # Strictly in the future: an event at exactly `now` already fired, so it's tomorrow's
  defp seconds_until(at, now) do
    diff = Time.diff(truncate(at), truncate(now))
    if diff <= 0, do: diff + @day, else: diff
  end

  defp truncate(time), do: %{time | microsecond: {0, 0}}

  defp title(%{equipment: %{} = eq}), do: Map.get(eq, :title) || Map.get(eq, :name)
  defp title(_), do: "?"

  defp pad2(n), do: n |> to_string() |> String.pad_leading(2, "0")
end

defmodule PouCon.Automation.Feeding.FeedingScheduler do
  @moduledoc """
  GenServer that drives feeding automation on a 1s tick.

  ## Cycle (system-wide, all feeding buckets treated as a unit)

      idle (at front | at back | position error)
        ↓ move_to_back_limit_time fires
      moving to back
        ↓ all buckets at_back
      idle, at back
        ↓ move_to_front_limit_time fires
      moving to front
        ↓ all buckets at_front
      idle, at front
        ↓ (if schedule wants fill: armed; once all at_front, fire FeedIn.turn_on)
      filling
        ↓ FeedIn stops (hardwired full-limit switch in series with contactor)
      idle, at front

  ## Fill arming

  When a schedule's `move_to_front_limit_time` fires AND the schedule has
  `trigger_fill: true`, the scheduler arms a fill. Fill is issued as soon
  as **every** feeding bucket reports `at_front: true` with
  `mode: :auto, error: nil`, AND the FeedIn precheck passes. There is no
  settle delay.

  Arm times out after 30 minutes if the all-at-front condition isn't met
  (fail closed — operator must intervene).

  FeedIn stop is hardwired (full-limit switch in series with the contactor
  coil). The scheduler never issues `FeedIn.turn_off`. As a software safety
  net, each `FeedIn.turn_on/2` call passes the schedule's `max_fill_minutes`;
  the FeedIn controller forces itself off after that window if the
  hopper-full path hasn't already stopped it.
  """

  use GenServer
  require Logger

  alias PouCon.Auth
  alias PouCon.Automation.Feeding.FeedingSchedules
  alias PouCon.Equipment.Controllers.{FeedIn, Feeding}
  alias PouCon.Equipment.Devices
  alias PouCon.Logging.EquipmentLogger

  @check_interval :timer.seconds(1)
  @arm_timeout_ms :timer.minutes(30)

  defmodule State do
    defstruct schedules: [],
              armed_fill_until_mono: nil,
              armed_for_schedule_id: nil,
              last_armed_minute: nil,
              last_seen_phase: nil,
              previous_phase: nil
  end

  # ——————————————————————————————————————————————————————————————
  # Client API
  # ——————————————————————————————————————————————————————————————

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def force_check do
    GenServer.cast(__MODULE__, :check_schedules)
  end

  def reload_schedules do
    GenServer.cast(__MODULE__, :reload_schedules)
  end

  def schedule_updated do
    Logger.info("FeedingScheduler: Schedule updated, reloading schedules")
    reload_schedules()
  end

  @doc """
  Returns the scheduler's previous/current/next phase for UI display.

  Shape:

      %{
        previous: phase | nil,
        current:  phase,
        next:     %{label: String.t(), time: Time.t() | nil}
      }

  `phase` is `%{phase: atom}`, with values:
  `:idle_at_front | :idle_at_back | :idle_position_error |
   :moving_to_back | :moving_to_front | :filling`.

  `previous` is the most recent *different* phase the scheduler observed
  since process start. It is `nil` until the phase changes once. State is
  in-memory only; reboots reset it.
  """
  def get_timeline do
    try do
      GenServer.call(__MODULE__, :get_timeline, 1000)
    catch
      :exit, _ ->
        %{
          previous: nil,
          current: %{phase: :unknown},
          next: %{label: "scheduler offline", time: nil}
        }
    end
  end

  # ——————————————————————————————————————————————————————————————
  # Server Callbacks
  # ——————————————————————————————————————————————————————————————

  @impl true
  def init(_opts) do
    Logger.info("FeedingScheduler started")
    schedules = load_schedules()
    schedule_next_check()
    {:ok, %State{schedules: schedules}}
  end

  @impl true
  def handle_info(:check_schedules, state) do
    new_state = tick(state)
    schedule_next_check()
    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:check_schedules, state) do
    {:noreply, tick(state)}
  end

  @impl true
  def handle_cast(:reload_schedules, %State{} = state) do
    Logger.info("FeedingScheduler: Reloading schedules from database")
    {:noreply, %State{state | schedules: load_schedules()}}
  end

  @impl true
  def handle_call(:get_timeline, _from, %State{} = state) do
    timezone = Auth.get_timezone()
    now = DateTime.now!(timezone)
    current_time = DateTime.to_time(now)

    current = compute_phase()

    timeline = %{
      previous: state.previous_phase && %{phase: state.previous_phase},
      current: current,
      next: compute_next(current.phase, state.schedules, current_time)
    }

    {:reply, timeline, state}
  end

  # ——————————————————————————————————————————————————————————————
  # Tick
  # ——————————————————————————————————————————————————————————————

  defp schedule_next_check do
    Process.send_after(self(), :check_schedules, @check_interval)
  end

  defp load_schedules do
    schedules = FeedingSchedules.list_enabled_schedules()
    Logger.info("FeedingScheduler: Loaded #{length(schedules)} enabled schedules")
    schedules
  end

  defp tick(%State{} = state) do
    timezone = Auth.get_timezone()
    current_datetime = DateTime.now!(timezone)
    current_time = DateTime.to_time(current_datetime)
    current_minute = %{current_time | second: 0, microsecond: {0, 0}}
    now_mono = System.monotonic_time(:millisecond)

    Logger.debug(
      "FeedingScheduler checking schedules at #{Time.to_string(current_minute)} (#{timezone})"
    )

    state
    |> fire_move_commands(current_minute)
    |> maybe_arm_for_fill(current_minute, now_mono)
    |> maybe_clear_armed_timeout(now_mono)
    |> maybe_fire_fill(now_mono)
    |> update_phase_history()
  end

  # ——————————————————————————————————————————————————————————————
  # Move commands
  # ——————————————————————————————————————————————————————————————

  defp fire_move_commands(%State{} = state, current_minute) do
    feeding_equipment =
      Devices.list_equipment()
      |> Enum.filter(&(&1.type == "feeding"))

    Enum.each(feeding_equipment, fn equipment ->
      check_equipment_schedules(equipment, state.schedules, current_minute)
    end)

    state
  end

  defp check_equipment_schedules(equipment, schedules, current_minute) do
    name = equipment.name

    case feeding_status_safe(name) do
      nil ->
        :ok

      %{mode: :manual} ->
        Logger.debug("FeedingScheduler: Skipping #{name} - in MANUAL mode")

      %{error: error} when error != nil ->
        Logger.debug("FeedingScheduler: Skipping #{name} - has error: #{inspect(error)}")

      %{mode: :auto, at_front: front_limit, at_back: back_limit} ->
        Enum.each(schedules, fn schedule ->
          check_schedule_for_equipment(schedule, name, current_minute, front_limit, back_limit)
        end)

      _ ->
        Logger.warning("FeedingScheduler: Unknown status for #{name}")
    end
  end

  defp check_schedule_for_equipment(schedule, name, current_minute, front_limit, back_limit) do
    if schedule.move_to_back_limit_time &&
         time_match?(schedule.move_to_back_limit_time, current_minute) &&
         not back_limit do
      case check_feedin_not_filling() do
        :ok ->
          Logger.info(
            "FeedingScheduler: Moving #{name} to BACK (schedule ##{schedule.id}, back_limit=OFF)"
          )

          Feeding.move_to_back_limit(name)

          EquipmentLogger.log_start(name, "auto", "schedule", %{
            "schedule_id" => schedule.id,
            "action" => "move_to_back",
            "move_to_back_time" => Time.to_string(schedule.move_to_back_limit_time)
          })

        {:error, reason} ->
          Logger.warning("FeedingScheduler: Skipping #{name} move to back - #{reason}")
      end
    end

    if schedule.move_to_front_limit_time &&
         time_match?(schedule.move_to_front_limit_time, current_minute) &&
         not front_limit do
      case check_feedin_not_filling() do
        :ok ->
          Logger.info(
            "FeedingScheduler: Moving #{name} to FRONT (schedule ##{schedule.id}, front_limit=OFF)"
          )

          Feeding.move_to_front_limit(name)

          EquipmentLogger.log_start(name, "auto", "schedule", %{
            "schedule_id" => schedule.id,
            "action" => "move_to_front",
            "move_to_front_time" => Time.to_string(schedule.move_to_front_limit_time)
          })

        {:error, reason} ->
          Logger.warning("FeedingScheduler: Skipping #{name} move to front - #{reason}")
      end
    end
  end

  defp time_match?(time, current_minute) do
    Time.compare(current_minute, %{time | second: 0, microsecond: {0, 0}}) == :eq
  end

  defp check_feedin_not_filling do
    case feedin_equipment() do
      nil ->
        :ok

      %{name: name} ->
        case feedin_status_safe(name) do
          nil -> {:error, "FeedIn controller not ready"}
          %{is_running: true} -> {:error, "FeedIn is still filling"}
          _ -> :ok
        end
    end
  end

  # ——————————————————————————————————————————————————————————————
  # Fill arming
  # ——————————————————————————————————————————————————————————————

  defp maybe_arm_for_fill(%State{} = state, current_minute, now_mono) do
    armable =
      Enum.find(state.schedules, fn schedule ->
        wants_fill?(schedule) and
          time_match?(schedule.move_to_front_limit_time, current_minute) and
          state.last_armed_minute != current_minute
      end)

    case armable do
      nil ->
        state

      schedule ->
        Logger.info(
          "FeedingScheduler: schedule ##{schedule.id} armed for fill at " <>
            "#{Time.to_string(current_minute)} (waiting for all feeding buckets at_front)"
        )

        %State{
          state
          | armed_fill_until_mono: now_mono + @arm_timeout_ms,
            armed_for_schedule_id: schedule.id,
            last_armed_minute: current_minute
        }
    end
  end

  defp wants_fill?(schedule) do
    schedule.move_to_front_limit_time != nil and schedule.trigger_fill == true
  end

  defp maybe_clear_armed_timeout(%State{armed_fill_until_mono: nil} = state, _), do: state

  defp maybe_clear_armed_timeout(%State{} = state, now_mono) do
    if now_mono > state.armed_fill_until_mono do
      Logger.warning(
        "FeedingScheduler: fill arm (schedule ##{state.armed_for_schedule_id}) timed out — " <>
          "not all buckets reached at_front within 30 min; returning to idle"
      )

      %State{state | armed_fill_until_mono: nil, armed_for_schedule_id: nil}
    else
      state
    end
  end

  defp maybe_fire_fill(%State{armed_fill_until_mono: nil} = state, _now_mono), do: state

  defp maybe_fire_fill(%State{} = state, _now_mono) do
    cond do
      not all_feeding_at_front?() ->
        state

      true ->
        case feedin_precheck() do
          {:ok, name} ->
            max_fill_minutes = max_fill_minutes_for(state.schedules, state.armed_for_schedule_id)

            Logger.info(
              "FeedingScheduler: all feeding buckets at_front; starting FeedIn fill " <>
                "(#{name}, max #{max_fill_minutes} min)"
            )

            FeedIn.turn_on(name, max_fill_minutes)

            EquipmentLogger.log_start(name, "auto", "schedule", %{
              "schedule_id" => state.armed_for_schedule_id,
              "action" => "feedin_fill",
              "max_fill_minutes" => max_fill_minutes
            })

            %State{state | armed_fill_until_mono: nil, armed_for_schedule_id: nil}

          {:skip, reason} ->
            Logger.debug("FeedingScheduler: fill arm waiting — FeedIn precheck: #{reason}")
            state
        end
    end
  end

  defp max_fill_minutes_for(schedules, schedule_id) do
    case Enum.find(schedules, &(&1.id == schedule_id)) do
      %{max_fill_minutes: m} when is_integer(m) and m > 0 -> m
      _ -> 30
    end
  end

  defp all_feeding_at_front? do
    statuses = list_feeding_statuses()

    statuses != [] and
      Enum.all?(statuses, fn s ->
        s[:at_front] == true and s[:mode] == :auto and s[:error] == nil
      end)
  end

  # ——————————————————————————————————————————————————————————————
  # Phase computation
  # ——————————————————————————————————————————————————————————————

  defp compute_phase do
    feedin_status = feedin_status_safe()
    feeding_statuses = list_feeding_statuses()

    cond do
      feedin_status && feedin_status[:is_running] ->
        %{phase: :filling}

      Enum.any?(feeding_statuses, &(&1[:moving] && &1[:target_limit] == :to_back_limit)) ->
        %{phase: :moving_to_back}

      Enum.any?(feeding_statuses, &(&1[:moving] && &1[:target_limit] == :to_front_limit)) ->
        %{phase: :moving_to_front}

      feeding_statuses != [] && Enum.all?(feeding_statuses, &(&1[:at_front] == true)) ->
        %{phase: :idle_at_front}

      feeding_statuses != [] && Enum.all?(feeding_statuses, &(&1[:at_back] == true)) ->
        %{phase: :idle_at_back}

      true ->
        %{phase: :idle_position_error}
    end
  end

  defp update_phase_history(%State{} = state) do
    current_phase = compute_phase().phase

    cond do
      state.last_seen_phase == nil ->
        %State{state | last_seen_phase: current_phase}

      current_phase == state.last_seen_phase ->
        state

      true ->
        %State{state | previous_phase: state.last_seen_phase, last_seen_phase: current_phase}
    end
  end

  # ——————————————————————————————————————————————————————————————
  # Next-step computation (UI display)
  # ——————————————————————————————————————————————————————————————

  defp compute_next(:filling, _schedules, _now), do: %{label: "waiting filling stop", time: nil}

  defp compute_next(:moving_to_back, _, _), do: %{label: "waiting all back limits", time: nil}

  defp compute_next(:moving_to_front, _, _), do: %{label: "waiting all front limits", time: nil}

  defp compute_next(:idle_at_front, schedules, now) do
    next_for_direction(:move_to_back, schedules, now)
  end

  defp compute_next(:idle_at_back, schedules, now) do
    next_for_direction(:move_to_front, schedules, now)
  end

  defp compute_next(:idle_position_error, _, _) do
    %{label: "waiting bucket position error clear", time: nil}
  end

  defp next_for_direction(direction, schedules, current_time) do
    field =
      case direction do
        :move_to_back -> :move_to_back_limit_time
        :move_to_front -> :move_to_front_limit_time
      end

    times =
      schedules
      |> Enum.map(&Map.get(&1, field))
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(&Time.to_erl/1)

    case times do
      [] ->
        %{label: "waiting #{direction_label(direction)} time", time: nil}

      sorted ->
        upcoming = Enum.find(sorted, fn t -> Time.compare(t, current_time) == :gt end)
        time = upcoming || hd(sorted)
        %{label: direction_label(direction), time: time}
    end
  end

  defp direction_label(:move_to_back), do: "move to BACK"
  defp direction_label(:move_to_front), do: "move to FRONT"

  # ——————————————————————————————————————————————————————————————
  # FeedIn / equipment helpers
  # ——————————————————————————————————————————————————————————————

  defp list_feeding_statuses do
    Devices.list_equipment()
    |> Enum.filter(&(&1.type == "feeding"))
    |> Enum.map(fn eq -> feeding_status_safe(eq.name) end)
    |> Enum.reject(&is_nil/1)
  end

  defp feeding_status_safe(name) do
    try do
      Feeding.status(name)
    catch
      :exit, _ -> nil
    end
  end

  defp feedin_equipment do
    Devices.list_equipment()
    |> Enum.find(&(&1.type == "feed_in"))
  end

  defp feedin_status_safe do
    case feedin_equipment() do
      nil -> nil
      %{name: name} -> feedin_status_safe(name)
    end
  end

  defp feedin_status_safe(name) do
    try do
      FeedIn.status(name)
    catch
      :exit, _ -> nil
    end
  end

  defp feedin_precheck do
    case feedin_equipment() do
      nil ->
        {:skip, "no FeedIn equipment configured"}

      %{name: name} ->
        case feedin_status_safe(name) do
          nil -> {:skip, "FeedIn controller not available"}
          %{mode: :manual} -> {:skip, "FeedIn in MANUAL mode"}
          %{is_running: true} -> {:skip, "FeedIn already running"}
          %{is_tripped: true} -> {:skip, "FeedIn is tripped"}

          # When real full_switch DI is present: only real bucket_full allows next cycle
          %{has_full_switch: true, bucket_full: true} ->
            {:skip, "FeedIn bucket full"}
          %{has_full_switch: true, mode: :auto} ->
            {:ok, name}

          # When full_switch DI is missing (temporary mode):
          # The ONLY condition that allows the next schedule cycle is a successful
          # hardwired full detection after running >= half the max-fill timer.
          %{has_full_switch: false, fill_completed: true} ->
            {:ok, name}

          # All other situations in temporary mode block the next cycle
          # (early stop, max-fill timer, trip, etc.)
          %{has_full_switch: false} ->
            {:skip, "FeedIn requires successful hardwired full detection (≥ half timer) to continue schedule"}

          _ -> {:skip, "FeedIn pre-check unmatched"}
        end
    end
  end
end

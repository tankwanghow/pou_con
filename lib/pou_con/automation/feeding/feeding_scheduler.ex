defmodule PouCon.Automation.Feeding.FeedingScheduler do
  @moduledoc """
  GenServer that periodically (1s tick) drives feeding automation:

  - Issues `move_to_back_limit` and `move_to_front_limit` commands at the
    times configured on each schedule.
  - Owns the FeedIn fill trigger state machine: when a schedule fires its
    `move_to_front_limit_time` and a `feedin_front_limit_bucket` is
    configured, the scheduler watches that bucket's front-limit for an
    OFF→ON edge and then starts FeedIn filling after a settle delay.

  Per-schedule fill state machine:

      :idle
        ↓ (current_minute matches move_to_front_limit_time AND
        ↓  feedin_front_limit_bucket_id is set)
      :waiting_front_limit_signal
        ↓ (trigger bucket at_front edge: false → true)
      :pending_fill
        ↓ (@fill_settle_delay_ms elapsed AND FeedIn pre-check passes)
      :verifying_fill_started
        ↓ (@verify_fill_started_ms elapsed)
      :idle

  Timeouts:
  - `:waiting_front_limit_signal` → `:idle` after @waiting_timeout_ms
    (logs a warning).

  Reboot recovery is fail-closed: all schedules start in `:idle`. On init,
  any schedule whose `move_to_front_limit_time` was within the last
  @catchup_window_ms is logged for operator awareness — no automatic fill
  recovery is performed.

  FeedIn stop is hardwired (full-limit switch in series with the contactor
  coil). The scheduler never issues `FeedIn.turn_off`.
  """

  use GenServer
  require Logger

  alias PouCon.Auth
  alias PouCon.Automation.Feeding.FeedingSchedules
  alias PouCon.Equipment.Controllers.{FeedIn, Feeding}
  alias PouCon.Equipment.Devices
  alias PouCon.Logging.EquipmentLogger

  @check_interval :timer.seconds(1)
  @fill_settle_delay_ms :timer.seconds(30)
  @waiting_timeout_ms :timer.minutes(30)
  @verify_fill_started_ms :timer.seconds(5)
  @catchup_window_ms :timer.minutes(2)

  defmodule State do
    defstruct schedules: [], fill_states: %{}
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

  # Legacy compatibility - schedule_updated now calls reload_schedules
  def schedule_updated do
    Logger.info("FeedingScheduler: Schedule updated, reloading schedules")
    reload_schedules()
  end

  # ——————————————————————————————————————————————————————————————
  # Server Callbacks
  # ——————————————————————————————————————————————————————————————

  @impl true
  def init(_opts) do
    Logger.info("FeedingScheduler started")
    schedules = load_schedules()
    log_recent_front_moves(schedules)
    schedule_next_check()
    {:ok, %State{schedules: schedules, fill_states: %{}}}
  end

  @impl true
  def handle_info(:check_schedules, state) do
    new_state = tick(state)
    schedule_next_check()
    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:check_schedules, state) do
    new_state = tick(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:reload_schedules, %State{} = state) do
    Logger.info("FeedingScheduler: Reloading schedules from database")
    schedules = load_schedules()
    new_ids = MapSet.new(schedules, & &1.id)

    fill_states =
      state.fill_states
      |> Enum.filter(fn {id, _} -> MapSet.member?(new_ids, id) end)
      |> Map.new()

    {:noreply, %State{state | schedules: schedules, fill_states: fill_states}}
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

  defp log_recent_front_moves(schedules) do
    timezone = Auth.get_timezone()
    now = DateTime.now!(timezone) |> DateTime.to_time()

    Enum.each(schedules, fn schedule ->
      front_time = schedule.move_to_front_limit_time

      if not is_nil(front_time) and not is_nil(schedule.feedin_front_limit_bucket_id) do
        diff_ms = Time.diff(now, front_time, :millisecond)

        if diff_ms >= 0 and diff_ms <= @catchup_window_ms do
          Logger.info(
            "FeedingScheduler: Catch-up — schedule ##{schedule.id} " <>
              "move_to_front_limit_time #{Time.to_string(front_time)} was " <>
              "#{div(diff_ms, 1000)}s ago. Failing closed; no automatic fill recovery."
          )
        end
      end
    end)
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

    feeding_equipment =
      Devices.list_equipment()
      |> Enum.filter(&(&1.type == "feeding"))

    for equipment <- feeding_equipment do
      check_equipment_schedules(equipment, state.schedules, current_minute)
    end

    fill_states =
      Enum.reduce(state.schedules, state.fill_states, fn schedule, acc ->
        current = Map.get(acc, schedule.id, default_fill_state())
        next = advance_fill_state(schedule, current, current_minute, now_mono)
        Map.put(acc, schedule.id, next)
      end)

    %State{state | fill_states: fill_states}
  end

  # ——————————————————————————————————————————————————————————————
  # Movement scheduling (per equipment)
  # ——————————————————————————————————————————————————————————————

  defp check_equipment_schedules(equipment, schedules, current_minute) do
    name = equipment.name

    status =
      try do
        Feeding.status(name)
      catch
        :exit, _ ->
          Logger.debug("FeedingScheduler: Controller #{name} not available yet")
          nil
      end

    case status do
      nil ->
        :ok

      %{mode: :manual} ->
        Logger.debug("FeedingScheduler: Skipping #{name} - in MANUAL mode")

      %{error: error} when error != nil ->
        Logger.debug("FeedingScheduler: Skipping #{name} - has error: #{inspect(error)}")

      %{mode: :auto, at_front: front_limit, at_back: back_limit} = status ->
        for schedule <- schedules do
          check_schedule_for_equipment(
            schedule,
            name,
            status,
            current_minute,
            front_limit,
            back_limit
          )
        end

      _ ->
        Logger.warning("FeedingScheduler: Unknown status for #{name}")
    end
  end

  defp check_schedule_for_equipment(
         schedule,
         equipment_name,
         _status,
         current_minute,
         front_limit,
         back_limit
       ) do
    if schedule.move_to_back_limit_time do
      back_time = %{schedule.move_to_back_limit_time | second: 0, microsecond: {0, 0}}

      if Time.compare(current_minute, back_time) == :eq and not back_limit do
        case check_feedin_not_filling() do
          :ok ->
            Logger.info(
              "FeedingScheduler: Moving #{equipment_name} to BACK (schedule ##{schedule.id}, " <>
                "back_limit=OFF)"
            )

            Feeding.move_to_back_limit(equipment_name)

            EquipmentLogger.log_start(equipment_name, "auto", "schedule", %{
              "schedule_id" => schedule.id,
              "action" => "move_to_back",
              "move_to_back_time" => Time.to_string(schedule.move_to_back_limit_time)
            })

          {:error, reason} ->
            Logger.warning(
              "FeedingScheduler: Skipping #{equipment_name} move to back - #{reason}"
            )
        end
      end
    end

    if schedule.move_to_front_limit_time do
      front_time = %{schedule.move_to_front_limit_time | second: 0, microsecond: {0, 0}}

      if Time.compare(current_minute, front_time) == :eq and not front_limit do
        case check_feedin_not_filling() do
          :ok ->
            Logger.info(
              "FeedingScheduler: Moving #{equipment_name} to FRONT (schedule ##{schedule.id}, " <>
                "front_limit=OFF)"
            )

            Feeding.move_to_front_limit(equipment_name)

            EquipmentLogger.log_start(equipment_name, "auto", "schedule", %{
              "schedule_id" => schedule.id,
              "action" => "move_to_front",
              "move_to_front_time" => Time.to_string(schedule.move_to_front_limit_time)
            })

          {:error, reason} ->
            Logger.warning(
              "FeedingScheduler: Skipping #{equipment_name} move to front - #{reason}"
            )
        end
      end
    end
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
  # Per-schedule fill state machine
  # ——————————————————————————————————————————————————————————————

  defp default_fill_state do
    %{
      state: :idle,
      prev_at_front: nil,
      reached_at: nil,
      waiting_entered_at: nil,
      fill_issued_at: nil,
      last_fired_minute: nil
    }
  end

  defp reset_to_idle(current) do
    %{default_fill_state() | last_fired_minute: current.last_fired_minute}
  end

  defp advance_fill_state(schedule, current, current_minute, now_mono) do
    case current.state do
      :idle -> maybe_enter_waiting(schedule, current, current_minute, now_mono)
      :waiting_front_limit_signal -> check_for_edge_or_timeout(schedule, current, now_mono)
      :pending_fill -> maybe_issue_fill(schedule, current, now_mono)
      :verifying_fill_started -> maybe_finish_verify(schedule, current, now_mono)
    end
  end

  defp maybe_enter_waiting(schedule, current, current_minute, now_mono) do
    bucket_id = schedule.feedin_front_limit_bucket_id
    front_time = schedule.move_to_front_limit_time

    cond do
      is_nil(bucket_id) ->
        current

      is_nil(front_time) ->
        current

      Time.compare(current_minute, %{front_time | second: 0, microsecond: {0, 0}}) != :eq ->
        current

      current.last_fired_minute == current_minute ->
        current

      true ->
        Logger.info(
          "FeedingScheduler: schedule ##{schedule.id} entered :waiting_front_limit_signal " <>
            "(trigger bucket: #{trigger_bucket_name(schedule)})"
        )

        %{
          current
          | state: :waiting_front_limit_signal,
            waiting_entered_at: now_mono,
            prev_at_front: read_trigger_at_front(schedule),
            reached_at: nil,
            fill_issued_at: nil,
            last_fired_minute: current_minute
        }
    end
  end

  defp check_for_edge_or_timeout(schedule, current, now_mono) do
    if now_mono - current.waiting_entered_at > @waiting_timeout_ms do
      Logger.warning(
        "FeedingScheduler: schedule ##{schedule.id} timed out waiting for front_limit " <>
          "signal from #{trigger_bucket_name(schedule)}; returning to idle"
      )

      reset_to_idle(current)
    else
      case read_trigger_at_front(schedule) do
        nil ->
          current

        curr_at_front ->
          if current.prev_at_front == false and curr_at_front == true do
            Logger.info(
              "FeedingScheduler: schedule ##{schedule.id} detected " <>
                "#{trigger_bucket_name(schedule)} at_front edge OFF→ON; " <>
                "entering :pending_fill"
            )

            %{current | state: :pending_fill, reached_at: now_mono, prev_at_front: curr_at_front}
          else
            %{current | prev_at_front: curr_at_front}
          end
      end
    end
  end

  defp maybe_issue_fill(schedule, current, now_mono) do
    if now_mono - current.reached_at < @fill_settle_delay_ms do
      current
    else
      case feedin_precheck() do
        {:ok, name} ->
          Logger.info(
            "FeedingScheduler: schedule ##{schedule.id} settle delay elapsed; " <>
              "starting FeedIn fill (#{name})"
          )

          FeedIn.turn_on(name)

          EquipmentLogger.log_start(name, "auto", "schedule", %{
            "schedule_id" => schedule.id,
            "action" => "feedin_fill",
            "trigger_bucket" => trigger_bucket_name(schedule)
          })

          %{current | state: :verifying_fill_started, fill_issued_at: now_mono}

        {:skip, reason} ->
          Logger.info(
            "FeedingScheduler: schedule ##{schedule.id} pre-check failed (#{reason}); " <>
              "returning to idle without filling"
          )

          reset_to_idle(current)
      end
    end
  end

  defp maybe_finish_verify(schedule, current, now_mono) do
    if now_mono - current.fill_issued_at < @verify_fill_started_ms do
      current
    else
      case feedin_status_safe() do
        %{is_running: true} ->
          Logger.info(
            "FeedingScheduler: schedule ##{schedule.id} FeedIn confirmed running; " <>
              "returning to idle"
          )

        %{is_running: false} = status ->
          Logger.warning(
            "FeedingScheduler: schedule ##{schedule.id} FeedIn did not start within " <>
              "verify window (status=#{inspect(status)}); returning to idle"
          )

        _ ->
          Logger.warning(
            "FeedingScheduler: schedule ##{schedule.id} FeedIn status unavailable in " <>
              "verify window; returning to idle"
          )
      end

      reset_to_idle(current)
    end
  end

  # ——————————————————————————————————————————————————————————————
  # FeedIn / trigger-bucket helpers
  # ——————————————————————————————————————————————————————————————

  defp trigger_bucket_name(schedule) do
    case schedule.feedin_front_limit_bucket do
      %{name: name} -> name
      _ -> "<unknown>"
    end
  end

  defp read_trigger_at_front(schedule) do
    case schedule.feedin_front_limit_bucket do
      %{name: name} ->
        try do
          case Feeding.status(name) do
            %{at_front: at_front, mode: :auto, error: nil} -> at_front
            _ -> nil
          end
        catch
          :exit, _ -> nil
        end

      _ ->
        nil
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
          %{bucket_full: true} -> {:skip, "FeedIn bucket full"}
          %{mode: :auto} -> {:ok, name}
          _ -> {:skip, "FeedIn pre-check unmatched"}
        end
    end
  end
end

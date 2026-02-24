defmodule PouCon.Automation.Feeding.FeedingScheduler do
  @moduledoc """
  GenServer that periodically checks feeding schedules and executes feeding cycles.

  Feeding Cycle Requirements:
  1. Check each feeding equipment individually based on its limit switch states
  2. Move to back only if: time matches AND not already at back_limit AND FeedIn is not filling
  3. Move to front only if: time matches AND not already at front_limit AND FeedIn is not filling
  4. Skip feeding buckets in MANUAL mode or with errors

  Note: FeedIn filling is handled by FeedInController (separate process)
  """

  use GenServer
  require Logger

  alias PouCon.Auth
  alias PouCon.Automation.Feeding.FeedingSchedules
  alias PouCon.Equipment.Controllers.{FeedIn, Feeding}
  alias PouCon.Equipment.Devices
  alias PouCon.Logging.EquipmentLogger

  @check_interval :timer.seconds(1)

  defmodule State do
    defstruct schedules: []
  end

  # Client API

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

  # Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("FeedingScheduler started")
    schedules = load_schedules()
    schedule_next_check()
    {:ok, %State{schedules: schedules}}
  end

  @impl true
  def handle_info(:check_schedules, state) do
    check_and_execute_schedules(state)
    schedule_next_check()
    {:noreply, state}
  end

  @impl true
  def handle_cast(:check_schedules, state) do
    check_and_execute_schedules(state)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:reload_schedules, %State{} = state) do
    Logger.info("FeedingScheduler: Reloading schedules from database")
    schedules = load_schedules()
    {:noreply, %State{state | schedules: schedules}}
  end

  # Private Functions

  defp schedule_next_check do
    Process.send_after(self(), :check_schedules, @check_interval)
  end

  defp load_schedules do
    schedules = FeedingSchedules.list_enabled_schedules()
    Logger.info("FeedingScheduler: Loaded #{length(schedules)} enabled schedules")
    schedules
  end

  defp check_and_execute_schedules(state) do
    timezone = Auth.get_timezone()
    current_datetime = DateTime.now!(timezone)
    current_time = DateTime.to_time(current_datetime)
    current_minute = %{current_time | second: 0, microsecond: {0, 0}}

    Logger.debug(
      "FeedingScheduler checking schedules at #{Time.to_string(current_minute)} (#{timezone})"
    )

    # Get all feeding equipment
    feeding_equipment =
      Devices.list_equipment()
      |> Enum.filter(&(&1.type == "feeding"))

    # Check each feeding equipment individually for scheduled movements
    for equipment <- feeding_equipment do
      check_equipment_schedules(equipment, state.schedules, current_minute)
    end
  end

  defp check_equipment_schedules(equipment, schedules, current_minute) do
    name = equipment.name

    # Get current status of this equipment (with defensive error handling)
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
        # Check each schedule to see if we should execute an action
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
    # Check if it's time to move to back limit
    if schedule.move_to_back_limit_time do
      back_time = %{schedule.move_to_back_limit_time | second: 0, microsecond: {0, 0}}

      if Time.compare(current_minute, back_time) == :eq and not back_limit do
        # Time matches, not already at back limit
        # Check if FeedIn is not currently filling
        case check_feedin_not_filling() do
          :ok ->
            Logger.info(
              "FeedingScheduler: Moving #{equipment_name} to BACK (schedule ##{schedule.id}, " <>
                "back_limit=OFF)"
            )

            Feeding.move_to_back_limit(equipment_name)

            # Log schedule-triggered action
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

    # Check if it's time to move to front limit
    if schedule.move_to_front_limit_time do
      front_time = %{schedule.move_to_front_limit_time | second: 0, microsecond: {0, 0}}

      if Time.compare(current_minute, front_time) == :eq and not front_limit do
        # Time matches, not already at front limit
        # Check if FeedIn is not currently filling
        case check_feedin_not_filling() do
          :ok ->
            Logger.info(
              "FeedingScheduler: Moving #{equipment_name} to FRONT (schedule ##{schedule.id}, " <>
                "front_limit=OFF)"
            )

            Feeding.move_to_front_limit(equipment_name)

            # Log schedule-triggered action
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
    # Find FeedIn equipment
    feed_in_equipment =
      Devices.list_equipment()
      |> Enum.find(&(&1.type == "feed_in"))

    if feed_in_equipment do
      # Get status with defensive error handling
      status =
        try do
          FeedIn.status(feed_in_equipment.name)
        catch
          :exit, _ ->
            Logger.debug("FeedingScheduler: FeedIn controller not available yet")
            nil
        end

      case status do
        nil ->
          {:error, "FeedIn controller not ready"}

        %{is_running: true} ->
          {:error, "FeedIn is still filling"}

        _ ->
          :ok
      end
    else
      # No FeedIn equipment configured, allow movement
      :ok
    end
  end
end

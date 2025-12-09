defmodule PouCon.Automation.EggCollection.EggCollectionScheduler do
  @moduledoc """
  GenServer that periodically checks egg collection schedules and executes them.
  Only operates when egg collection equipment is in AUTO mode.
  """

  use GenServer
  require Logger

  alias PouCon.Auth
  alias PouCon.Automation.EggCollection.EggCollectionSchedules
  alias PouCon.Equipment.Controllers.Egg
  alias PouCon.Logging.EquipmentLogger

  @check_interval :timer.seconds(30)

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

  # Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("EggCollectionScheduler started")
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
  def handle_cast(:reload_schedules, state) do
    Logger.info("EggCollectionScheduler: Reloading schedules from database")
    schedules = load_schedules()
    {:noreply, %State{state | schedules: schedules}}
  end

  # Private Functions

  defp schedule_next_check do
    Process.send_after(self(), :check_schedules, @check_interval)
  end

  defp load_schedules do
    schedules = EggCollectionSchedules.list_enabled_schedules()
    Logger.info("EggCollectionScheduler: Loaded #{length(schedules)} enabled schedules")
    schedules
  end

  defp check_and_execute_schedules(state) do
    timezone = Auth.get_timezone()
    current_datetime = DateTime.now!(timezone)
    current_time = DateTime.to_time(current_datetime)
    current_minute = %{current_time | second: 0, microsecond: {0, 0}}

    Logger.debug(
      "EggCollectionScheduler checking schedules at #{Time.to_string(current_minute)} (#{timezone})"
    )

    state.schedules
    |> Enum.each(fn schedule ->
      check_schedule(schedule, current_minute)
    end)
  end

  defp check_schedule(schedule, current_minute) do
    equipment_name = schedule.equipment.name
    start_time = %{schedule.start_time | second: 0, microsecond: {0, 0}}
    stop_time = %{schedule.stop_time | second: 0, microsecond: {0, 0}}

    # Determine if we're currently within the active period
    should_be_running = time_in_range?(current_minute, start_time, stop_time)

    # Get current equipment status
    case Egg.status(equipment_name) do
      %{mode: :auto, commanded_on: is_on} ->
        cond do
          should_be_running and not is_on ->
            Logger.info(
              "EggCollectionScheduler: Starting #{equipment_name} (currently in schedule period)"
            )

            Egg.turn_on(equipment_name)

            # Log schedule-triggered action
            EquipmentLogger.log_start(equipment_name, "auto", "schedule", %{
              "schedule_id" => schedule.id,
              "start_time" => Time.to_string(schedule.start_time),
              "stop_time" => Time.to_string(schedule.stop_time)
            })

          not should_be_running and is_on ->
            Logger.info(
              "EggCollectionScheduler: Stopping #{equipment_name} (outside schedule period)"
            )

            Egg.turn_off(equipment_name)

            # Log schedule-triggered action
            EquipmentLogger.log_stop(equipment_name, "auto", "schedule", "running", %{
              "schedule_id" => schedule.id,
              "start_time" => Time.to_string(schedule.start_time),
              "stop_time" => Time.to_string(schedule.stop_time)
            })

          true ->
            :ok
        end

      %{mode: :manual} ->
        Logger.debug("EggCollectionScheduler: Skipping #{equipment_name} - in MANUAL mode")

      {:error, reason} ->
        Logger.warning(
          "EggCollectionScheduler: Failed to get status for #{equipment_name}: #{inspect(reason)}"
        )
    end
  end

  # Check if current_time is within the range [start_time, stop_time)
  defp time_in_range?(current_time, start_time, stop_time) do
    Time.compare(current_time, start_time) in [:eq, :gt] and
      Time.compare(current_time, stop_time) == :lt
  end
end

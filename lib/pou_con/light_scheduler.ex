defmodule PouCon.LightScheduler do
  @moduledoc """
  GenServer that periodically checks light schedules and executes them.
  Only operates when lights are in AUTO mode.
  """

  use GenServer
  require Logger

  alias PouCon.Auth
  alias PouCon.LightSchedules
  alias PouCon.DeviceControllers.Light

  @check_interval :timer.seconds(30)

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def force_check do
    GenServer.cast(__MODULE__, :check_schedules)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("LightScheduler started")
    schedule_next_check()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:check_schedules, state) do
    check_and_execute_schedules()
    schedule_next_check()
    {:noreply, state}
  end

  @impl true
  def handle_cast(:check_schedules, state) do
    check_and_execute_schedules()
    {:noreply, state}
  end

  # Private Functions

  defp schedule_next_check do
    Process.send_after(self(), :check_schedules, @check_interval)
  end

  defp check_and_execute_schedules do
    timezone = Auth.get_timezone()
    current_datetime = DateTime.now!(timezone)
    current_time = DateTime.to_time(current_datetime)
    current_minute = %{current_time | second: 0, microsecond: {0, 0}}

    Logger.debug("LightScheduler checking schedules at #{Time.to_string(current_minute)} (#{timezone})")

    LightSchedules.list_enabled_schedules()
    |> Enum.each(fn schedule ->
      check_schedule(schedule, current_minute)
    end)
  end

  defp check_schedule(schedule, current_minute) do
    equipment_name = schedule.equipment.name
    on_time = %{schedule.on_time | second: 0, microsecond: {0, 0}}
    off_time = %{schedule.off_time | second: 0, microsecond: {0, 0}}

    # Determine if we're currently within the active period
    should_be_on = time_in_range?(current_minute, on_time, off_time)

    # Get current equipment status
    case Light.status(equipment_name) do
      %{mode: :auto, commanded_on: is_on} ->
        cond do
          should_be_on and not is_on ->
            Logger.info(
              "LightScheduler: Turning ON #{equipment_name} (currently in schedule period)"
            )

            Light.turn_on(equipment_name)

          not should_be_on and is_on ->
            Logger.info("LightScheduler: Turning OFF #{equipment_name} (outside schedule period)")
            Light.turn_off(equipment_name)

          true ->
            :ok
        end

      %{mode: :manual} ->
        Logger.debug("LightScheduler: Skipping #{equipment_name} - in MANUAL mode")

      {:error, reason} ->
        Logger.warning(
          "LightScheduler: Failed to get status for #{equipment_name}: #{inspect(reason)}"
        )
    end
  end

  # Check if current_time is within the range [on_time, off_time)
  defp time_in_range?(current_time, on_time, off_time) do
    Time.compare(current_time, on_time) in [:eq, :gt] and
      Time.compare(current_time, off_time) == :lt
  end
end

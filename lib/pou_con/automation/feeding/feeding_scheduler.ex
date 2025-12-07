defmodule PouCon.Automation.Feeding.FeedingScheduler do
  @moduledoc """
  GenServer that periodically checks feeding schedules and executes feeding cycles.

  Feeding Cycle Requirements:
  1. Only start if FeedIn bucket is full and filling has stopped
  2. Skip feeding buckets in MANUAL mode or with errors
  3. Move each feeding bucket back to limit, then forward to limit
  4. Only allow FeedIn filling when feed_1 reaches front limit
  """

  use GenServer
  require Logger

  alias PouCon.Auth
  alias PouCon.Automation.Feeding.FeedingSchedules
  alias PouCon.Equipment.Controllers.{FeedIn, Feeding}
  alias PouCon.Equipment.Devices

  @check_interval :timer.seconds(30)

  defmodule State do
    defstruct last_executed_minute: nil,
              executed_schedule_ids: MapSet.new()
  end

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def force_check do
    GenServer.cast(__MODULE__, :check_schedules)
  end

  def status do
    GenServer.call(__MODULE__, :status)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("FeedingScheduler started")
    schedule_next_check()
    {:ok, %State{}}
  end

  @impl true
  def handle_info(:check_schedules, state) do
    new_state = check_and_execute_schedules(state)
    schedule_next_check()
    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:check_schedules, state) do
    new_state = check_and_execute_schedules(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, state, state}
  end

  # Private Functions

  defp schedule_next_check do
    Process.send_after(self(), :check_schedules, @check_interval)
  end

  defp check_and_execute_schedules(state) do
    timezone = Auth.get_timezone()
    current_datetime = DateTime.now!(timezone)
    current_time = DateTime.to_time(current_datetime)
    current_minute = %{current_time | second: 0, microsecond: {0, 0}}

    # Reset executed_schedule_ids if minute changed
    state =
      if state.last_executed_minute != current_minute do
        %State{state | last_executed_minute: current_minute, executed_schedule_ids: MapSet.new()}
      else
        state
      end

    Logger.debug(
      "FeedingScheduler checking schedules at #{Time.to_string(current_minute)} (#{timezone})"
    )

    # Find schedules with commands to execute at current time
    commands = find_commands_to_execute(current_minute, state.executed_schedule_ids)

    if length(commands) > 0 do
      Logger.info(
        "FeedingScheduler: Found #{length(commands)} command(s) to execute at #{current_minute}"
      )

      execute_commands(commands)

      executed_ids =
        Enum.reduce(commands, state.executed_schedule_ids, fn {schedule, _action}, acc ->
          MapSet.put(acc, {schedule.id, current_minute})
        end)

      %State{state | executed_schedule_ids: executed_ids}
    else
      state
    end
  end

  defp find_commands_to_execute(current_minute, executed_schedule_ids) do
    FeedingSchedules.list_enabled_schedules()
    |> Enum.flat_map(fn schedule ->
      commands = []

      # Check if it's time to move to back limit
      commands =
        if schedule.move_to_back_limit_time do
          back_minute = %{schedule.move_to_back_limit_time | second: 0, microsecond: {0, 0}}

          if Time.compare(current_minute, back_minute) == :eq and
               not MapSet.member?(executed_schedule_ids, {schedule.id, current_minute}) do
            [{schedule, :move_to_back_limit} | commands]
          else
            commands
          end
        else
          commands
        end

      # Check if it's time to move to front limit
      commands =
        if schedule.move_to_front_limit_time do
          front_minute = %{schedule.move_to_front_limit_time | second: 0, microsecond: {0, 0}}

          if Time.compare(current_minute, front_minute) == :eq and
               not MapSet.member?(executed_schedule_ids, {schedule.id, current_minute}) do
            [{schedule, :move_to_front_limit} | commands]
          else
            commands
          end
        else
          commands
        end

      commands
    end)
  end

  defp execute_commands(commands) do
    # Get all feeding equipment
    feeding_equipment =
      Devices.list_equipment()
      |> Enum.filter(&(&1.type == "feeding"))

    # Execute each command immediately - affects ALL feeding buckets
    for {schedule, action} <- commands do
      # Check FeedIn status if this is a move to back command
      if action == :move_to_back_limit do
        case check_feedin_ready_for_back_move() do
          :ok ->
            Logger.info("FeedingScheduler: FeedIn is full and stopped, executing move to back")
            execute_move_command(feeding_equipment, action)

          {:error, reason} ->
            Logger.warning("FeedingScheduler: Skipping move to back - #{reason}")
        end
      else
        # Move to front doesn't require FeedIn check
        Logger.info("FeedingScheduler: Executing #{action} for all feeding buckets")
        execute_move_command(feeding_equipment, action)
      end

      # Check if we should enable FeedIn filling for this schedule
      if action == :move_to_front_limit && schedule.feedin_front_limit_bucket_id do
        trigger_bucket = schedule.feedin_front_limit_bucket

        if trigger_bucket do
          Task.start(fn ->
            # Wait a bit for movement to complete
            Process.sleep(1000)
            check_and_enable_feedin_filling_for_bucket(trigger_bucket.name)
          end)
        end
      end
    end
  end

  defp check_feedin_ready_for_back_move do
    # Find FeedIn equipment
    feed_in_equipment =
      Devices.list_equipment()
      |> Enum.find(&(&1.type == "feed_in"))

    if feed_in_equipment do
      case FeedIn.status(feed_in_equipment.name) do
        %{bucket_full: true, is_running: false} ->
          :ok

        %{bucket_full: false} ->
          {:error, "FeedIn bucket is not full"}

        %{is_running: true} ->
          {:error, "FeedIn is still filling"}

        _ ->
          {:error, "FeedIn status unknown"}
      end
    else
      Logger.warning("FeedingScheduler: No FeedIn equipment found, allowing move")
      :ok
    end
  end

  defp execute_move_command(feeding_equipment, action) do
    # Send command to all feeding buckets
    for equipment <- feeding_equipment do
      name = equipment.name

      case Feeding.status(name) do
        %{mode: :manual} ->
          Logger.info("FeedingScheduler: Skipping #{name} - in MANUAL mode")

        %{error: error} when error != nil ->
          Logger.info("FeedingScheduler: Skipping #{name} - has error: #{inspect(error)}")

        %{mode: :auto} ->
          case action do
            :move_to_back_limit ->
              Logger.info("FeedingScheduler: Sending move_to_back_limit to #{name}")
              Feeding.move_to_back_limit(name)

            :move_to_front_limit ->
              Logger.info("FeedingScheduler: Sending move_to_front_limit to #{name}")
              Feeding.move_to_front_limit(name)
          end

        _ ->
          Logger.warning("FeedingScheduler: Unknown status for #{name}")
      end
    end
  end

  defp check_and_enable_feedin_filling_for_bucket(name) do
    case Feeding.status(name) do
      %{front_limit: true, mode: :auto, error: nil} ->
        Logger.info("FeedingScheduler: #{name} at front limit, enabling FeedIn filling")
        enable_feedin_filling()

      _ ->
        Logger.debug("FeedingScheduler: #{name} not at front limit yet")
    end
  end

  defp enable_feedin_filling do
    feed_in_equipment =
      Devices.list_equipment()
      |> Enum.find(&(&1.type == "feed_in"))

    if feed_in_equipment do
      name = feed_in_equipment.name

      # Check if FeedIn is in MANUAL mode
      case FeedIn.status(name) do
        %{mode: :manual} ->
          Logger.warning(
            "FeedingScheduler: FeedIn is in MANUAL mode, skipping auto-fill enable"
          )

        %{mode: :auto} ->
          # FeedIn already in AUTO mode, just turn on
          FeedIn.turn_on(name)
          Logger.info("FeedingScheduler: FeedIn filling enabled (already in AUTO)")

        _ ->
          Logger.error("FeedingScheduler: Cannot get FeedIn status")
      end
    else
      Logger.error("FeedingScheduler: No FeedIn equipment found")
    end
  end
end

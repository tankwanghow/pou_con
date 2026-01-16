defmodule PouCon.Automation.Feeding.FeedInController do
  @moduledoc """
  Monitors feeding buckets configured as FeedIn triggers and automatically
  starts FeedIn filling when conditions are met.

  Triggering Conditions:
  1. Trigger bucket's front_limit changes from OFF to ON
  2. Trigger bucket has recently completed move_to_front_limit (within 30 minutes)
  3. FeedIn bucket is not full
  4. FeedIn is not already running
  5. Both trigger bucket and FeedIn are in AUTO mode

  Note: Movement from back to front takes approximately 15 minutes, but timing
  can vary. A 30-minute timeout ensures we don't miss the transition.
  """

  use GenServer
  require Logger

  alias PouCon.Automation.Feeding.FeedingSchedules
  alias PouCon.Equipment.Controllers.{FeedIn, Feeding}
  alias PouCon.Equipment.Devices

  @pubsub_topic "data_point_data"
  # Movement takes ~15 mins, allow 30 min timeout
  @movement_timeout_ms :timer.minutes(30)

  defmodule State do
    # %{bucket_name => %{prev_at_front: bool, move_to_front_time: timestamp}}
    defstruct trigger_buckets: %{},
              schedules: []
  end

  # ------------------------------------------------------------------ #
  # Public API
  # ------------------------------------------------------------------ #
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def reload_schedules do
    GenServer.cast(__MODULE__, :reload_schedules)
  end

  # Legacy compatibility
  def schedule_updated do
    Logger.info("FeedInController: Schedule updated, reloading schedules")
    reload_schedules()
  end

  # ------------------------------------------------------------------ #
  # Server
  # ------------------------------------------------------------------ #
  @impl GenServer
  def init(_opts) do
    Logger.info("FeedInController started")
    Phoenix.PubSub.subscribe(PouCon.PubSub, @pubsub_topic)

    schedules = load_schedules()
    trigger_buckets = initialize_trigger_buckets(schedules)

    {:ok, %State{schedules: schedules, trigger_buckets: trigger_buckets}}
  end

  @impl GenServer
  def handle_info(:data_refreshed, state) do
    # Check each trigger bucket for state changes
    new_trigger_buckets = check_trigger_buckets(state.trigger_buckets)
    {:noreply, %State{state | trigger_buckets: new_trigger_buckets}}
  end

  @impl GenServer
  def handle_cast(:reload_schedules, state) do
    Logger.info("FeedInController: Reloading schedules from database")
    schedules = load_schedules()
    trigger_buckets = initialize_trigger_buckets(schedules)
    {:noreply, %State{state | schedules: schedules, trigger_buckets: trigger_buckets}}
  end

  # ------------------------------------------------------------------ #
  # Private
  # ------------------------------------------------------------------ #
  defp load_schedules do
    schedules = FeedingSchedules.list_enabled_schedules()
    Logger.info("FeedInController: Loaded #{length(schedules)} enabled schedules")
    schedules
  end

  defp initialize_trigger_buckets(schedules) do
    # Get all unique trigger buckets from enabled schedules
    trigger_bucket_names =
      schedules
      |> Enum.filter(& &1.feedin_front_limit_bucket_id)
      |> Enum.map(& &1.feedin_front_limit_bucket)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(& &1.id)
      |> Enum.map(& &1.name)

    # Initialize tracking state for each trigger bucket
    trigger_bucket_names
    |> Enum.map(fn name ->
      {name, %{prev_at_front: false, move_to_front_time: nil}}
    end)
    |> Map.new()
  end

  defp check_trigger_buckets(trigger_buckets) do
    Enum.map(trigger_buckets, fn {bucket_name, tracker} ->
      new_tracker = check_trigger_bucket(bucket_name, tracker)
      {bucket_name, new_tracker}
    end)
    |> Map.new()
  end

  defp check_trigger_bucket(bucket_name, tracker) do
    case Feeding.status(bucket_name) do
      %{at_front: current_at_front, mode: :auto, error: nil, moving: is_moving} ->
        prev_at_front = tracker.prev_at_front
        move_to_front_time = tracker.move_to_front_time

        # Update move_to_front_time if currently moving to front
        new_move_time =
          if is_moving and not current_at_front do
            # Currently moving (presumably to front) - record timestamp
            System.monotonic_time(:millisecond)
          else
            move_to_front_time
          end

        # Detect OFF -> ON transition
        if not prev_at_front and current_at_front do
          # Front limit changed from OFF to ON
          Logger.debug(
            "FeedInController: #{bucket_name} front_limit OFF -> ON " <>
              "(move_to_front_time: #{inspect(new_move_time)})"
          )

          # Check if this happened shortly after move_to_front_limit
          recently_moved =
            new_move_time != nil and
              System.monotonic_time(:millisecond) - new_move_time < @movement_timeout_ms

          if recently_moved do
            Logger.info(
              "FeedInController: #{bucket_name} reached front limit after movement, " <>
                "checking if FeedIn should start"
            )

            start_feedin_if_needed()
          else
            Logger.debug(
              "FeedInController: #{bucket_name} at front limit, " <>
                "but no recent move_to_front_limit detected"
            )
          end
        end

        # Return updated tracker
        %{prev_at_front: current_at_front, move_to_front_time: new_move_time}

      %{mode: :manual} ->
        Logger.debug("FeedInController: #{bucket_name} in MANUAL mode, skipping")
        tracker

      %{error: error} when error != nil ->
        Logger.debug("FeedInController: #{bucket_name} has error: #{inspect(error)}")
        tracker

      _ ->
        Logger.warning("FeedInController: Unknown status for #{bucket_name}")
        tracker
    end
  rescue
    e ->
      Logger.warning("FeedInController: Error checking #{bucket_name}: #{inspect(e)}")
      tracker
  catch
    :exit, reason ->
      Logger.warning("FeedInController: Exit when checking #{bucket_name}: #{inspect(reason)}")
      tracker
  end

  defp start_feedin_if_needed do
    # Find FeedIn equipment
    feed_in_equipment =
      Devices.list_equipment()
      |> Enum.find(&(&1.type == "feed_in"))

    if feed_in_equipment do
      name = feed_in_equipment.name

      # Get status with defensive error handling
      status =
        try do
          FeedIn.status(name)
        catch
          :exit, _ ->
            Logger.debug("FeedInController: FeedIn controller #{name} not available yet")
            nil
        end

      case status do
        nil ->
          :ok

        %{mode: :auto, bucket_full: false, is_running: false} ->
          # FeedIn is in auto, not full, and not running - start filling
          Logger.info(
            "FeedInController: Trigger bucket reached front limit, " <>
              "starting FeedIn filling"
          )

          FeedIn.turn_on(name)

        %{mode: :manual} ->
          Logger.debug("FeedInController: FeedIn in MANUAL mode, skipping auto-fill")

        %{bucket_full: true} ->
          Logger.debug("FeedInController: FeedIn bucket already full")

        %{is_running: true} ->
          Logger.debug("FeedInController: FeedIn already filling")

        _ ->
          :ok
      end
    else
      Logger.warning("FeedInController: No FeedIn equipment found")
    end
  end
end

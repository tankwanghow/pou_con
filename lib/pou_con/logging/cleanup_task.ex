defmodule PouCon.Logging.CleanupTask do
  @moduledoc """
  GenServer that handles automated data retention and database optimization.
  Runs daily cleanup at 3 AM and weekly VACUUM on Sunday.
  """

  use GenServer
  require Logger

  alias PouCon.Logging.Schemas.{EquipmentEvent, DataPointLog}
  alias PouCon.Repo

  import Ecto.Query

  # Configuration
  @event_retention_days 30
  @data_point_log_retention_days 30
  # 3 AM
  @cleanup_hour 3
  # Sunday
  @vacuum_day 0

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    Logger.info(
      "CleanupTask started - retention: #{@event_retention_days} days events/logs"
    )

    schedule_cleanup()
    {:ok, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    perform_cleanup()
    schedule_cleanup()
    {:noreply, state}
  end

  # Schedule next cleanup at 3 AM
  defp schedule_cleanup do
    now = DateTime.utc_now()
    next_cleanup = calculate_next_cleanup_time(now)
    ms_until_cleanup = DateTime.diff(next_cleanup, now, :millisecond)

    Process.send_after(self(), :cleanup, ms_until_cleanup)
    Logger.debug("Next cleanup scheduled for #{next_cleanup}")
  end

  # Calculate next 3 AM
  defp calculate_next_cleanup_time(now) do
    now
    |> DateTime.to_date()
    |> then(fn date ->
      if now.hour < @cleanup_hour do
        # If before 3 AM today, schedule for 3 AM today
        DateTime.new!(date, ~T[03:00:00])
      else
        # Otherwise schedule for 3 AM tomorrow
        DateTime.new!(Date.add(date, 1), ~T[03:00:00])
      end
    end)
  end

  # Perform cleanup operations
  defp perform_cleanup do
    Logger.info("Starting daily cleanup...")

    # Delete old equipment events
    event_cutoff = DateTime.utc_now() |> DateTime.add(-@event_retention_days, :day)

    {event_count, _} =
      Repo.delete_all(from e in EquipmentEvent, where: e.inserted_at < ^event_cutoff)

    Logger.info("Deleted #{event_count} old equipment events")

    # Delete old data point logs
    data_point_cutoff = DateTime.utc_now() |> DateTime.add(-@data_point_log_retention_days, :day)

    {data_point_count, _} =
      Repo.delete_all(from d in DataPointLog, where: d.inserted_at < ^data_point_cutoff)

    Logger.info("Deleted #{data_point_count} old data point logs")

    # Run VACUUM on Sunday
    if Date.day_of_week(Date.utc_today()) == @vacuum_day do
      Logger.info("Running VACUUM to reclaim disk space...")
      Repo.query!("VACUUM")
      Logger.info("VACUUM completed")
    end

    Logger.info("Cleanup completed")
  end

  # ===== Manual Operations =====

  @doc """
  Manually trigger cleanup (for testing).
  """
  def trigger_cleanup do
    GenServer.cast(__MODULE__, :manual_cleanup)
  end

  @impl true
  def handle_cast(:manual_cleanup, state) do
    perform_cleanup()
    {:noreply, state}
  end
end

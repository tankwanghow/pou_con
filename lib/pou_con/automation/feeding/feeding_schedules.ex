defmodule PouCon.Automation.Feeding.FeedingSchedules do
  @moduledoc """
  The FeedingSchedules context for managing feeding automation schedules.
  """

  import Ecto.Query, warn: false
  alias PouCon.Repo

  alias PouCon.Automation.Feeding.Schemas.Schedule

  @doc """
  Returns the list of feeding schedules.
  """
  def list_schedules do
    Schedule
    |> preload(:feedin_front_limit_bucket)
    |> order_by([s], s.id)
    |> Repo.all()
  end

  @doc """
  Returns the list of enabled feeding schedules.
  """
  def list_enabled_schedules do
    Schedule
    |> where([s], s.enabled == true)
    |> preload(:feedin_front_limit_bucket)
    |> order_by([s], s.id)
    |> Repo.all()
  end

  @doc """
  Gets a single schedule.
  """
  def get_schedule!(id) do
    Schedule
    |> preload(:feedin_front_limit_bucket)
    |> Repo.get!(id)
  end

  @doc """
  Creates a schedule.
  """
  def create_schedule(attrs \\ %{}) do
    result =
      %Schedule{}
      |> Schedule.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, _schedule} ->
        notify_scheduler_update()
        result

      _ ->
        result
    end
  end

  @doc """
  Updates a schedule.
  """
  def update_schedule(%Schedule{} = schedule, attrs) do
    result =
      schedule
      |> Schedule.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, _schedule} ->
        notify_scheduler_update()
        result

      _ ->
        result
    end
  end

  @doc """
  Deletes a schedule.
  """
  def delete_schedule(%Schedule{} = schedule) do
    result = Repo.delete(schedule)

    case result do
      {:ok, _schedule} ->
        notify_scheduler_update()
        result

      _ ->
        result
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking schedule changes.
  """
  def change_schedule(%Schedule{} = schedule, attrs \\ %{}) do
    Schedule.changeset(schedule, attrs)
  end

  @doc """
  Toggles the enabled status of a schedule.
  """
  def toggle_schedule(%Schedule{} = schedule) do
    update_schedule(schedule, %{enabled: !schedule.enabled})
  end

  # Private Functions

  defp notify_scheduler_update do
    # Reload schedules in the FeedingScheduler
    try do
      PouCon.Automation.Feeding.FeedingScheduler.reload_schedules()
    rescue
      _ -> :ok
    end
  end
end

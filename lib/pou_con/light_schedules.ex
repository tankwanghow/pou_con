defmodule PouCon.LightSchedules do
  @moduledoc """
  The LightSchedules context for managing light automation schedules.
  """

  import Ecto.Query, warn: false
  alias PouCon.Repo

  alias PouCon.LightSchedules.Schedule

  @doc """
  Returns the list of light schedules.

  ## Examples

      iex> list_schedules()
      [%Schedule{}, ...]

  """
  def list_schedules do
    Schedule
    |> preload(:equipment)
    |> order_by([s], s.id)
    |> Repo.all()
  end

  @doc """
  Returns the list of enabled light schedules.

  ## Examples

      iex> list_enabled_schedules()
      [%Schedule{}, ...]

  """
  def list_enabled_schedules do
    Schedule
    |> where([s], s.enabled == true)
    |> preload(:equipment)
    |> Repo.all()
  end

  @doc """
  Gets schedules for a specific equipment.

  ## Examples

      iex> list_schedules_by_equipment("light_1")
      [%Schedule{}, ...]

  """
  def list_schedules_by_equipment(equipment_name) when is_binary(equipment_name) do
    Schedule
    |> join(:inner, [s], e in assoc(s, :equipment))
    |> where([s, e], e.name == ^equipment_name)
    |> preload(:equipment)
    |> Repo.all()
  end

  def list_schedules_by_equipment(equipment_id) when is_integer(equipment_id) do
    Schedule
    |> where([s], s.equipment_id == ^equipment_id)
    |> preload(:equipment)
    |> Repo.all()
  end

  @doc """
  Gets a single schedule.

  Raises `Ecto.NoResultsError` if the Schedule does not exist.

  ## Examples

      iex> get_schedule!(123)
      %Schedule{}

      iex> get_schedule!(456)
      ** (Ecto.NoResultsError)

  """
  def get_schedule!(id) do
    Schedule
    |> preload(:equipment)
    |> Repo.get!(id)
  end

  @doc """
  Creates a schedule.

  ## Examples

      iex> create_schedule(%{field: value})
      {:ok, %Schedule{}}

      iex> create_schedule(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_schedule(attrs \\ %{}) do
    %Schedule{}
    |> Schedule.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a schedule.

  ## Examples

      iex> update_schedule(schedule, %{field: new_value})
      {:ok, %Schedule{}}

      iex> update_schedule(schedule, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_schedule(%Schedule{} = schedule, attrs) do
    schedule
    |> Schedule.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a schedule.

  ## Examples

      iex> delete_schedule(schedule)
      {:ok, %Schedule{}}

      iex> delete_schedule(schedule)
      {:error, %Ecto.Changeset{}}

  """
  def delete_schedule(%Schedule{} = schedule) do
    Repo.delete(schedule)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking schedule changes.

  ## Examples

      iex> change_schedule(schedule)
      %Ecto.Changeset{data: %Schedule{}}

  """
  def change_schedule(%Schedule{} = schedule, attrs \\ %{}) do
    Schedule.changeset(schedule, attrs)
  end

  @doc """
  Toggles the enabled status of a schedule.

  ## Examples

      iex> toggle_schedule(schedule)
      {:ok, %Schedule{}}

  """
  def toggle_schedule(%Schedule{} = schedule) do
    update_schedule(schedule, %{enabled: !schedule.enabled})
  end
end

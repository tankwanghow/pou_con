defmodule PouCon.Equipment.Devices do
  @moduledoc """
  The Equipment context.

  Note: DataPoint functions have moved to `PouCon.Equipment.DataPoints`.
  This module now only contains Equipment-related functions.
  """

  import Ecto.Query, warn: false
  alias PouCon.Repo

  alias PouCon.Equipment.Schemas.Equipment

  @doc """
  Returns the list of equipments.

  ## Examples

      iex> list_equipment()
      [%Equipment{}, ...]

  """
  def list_equipment(opts \\ []) do
    sort_field = Keyword.get(opts, :sort_field, :name)
    sort_order = Keyword.get(opts, :sort_order, :asc)
    filter = Keyword.get(opts, :filter)
    include_inactive = Keyword.get(opts, :include_inactive, false)

    query =
      Equipment
      |> order_by({^sort_order, ^sort_field})

    # Filter by active status (default: only active equipment)
    query =
      if include_inactive do
        query
      else
        from e in query, where: e.active == true
      end

    query =
      if filter && String.trim(filter) != "" do
        filter_pattern = "%#{String.downcase(filter)}%"

        from e in query,
          where:
            fragment("lower(?)", e.name) |> like(^filter_pattern) or
              fragment("lower(?)", e.title) |> like(^filter_pattern) or
              fragment("lower(?)", e.type) |> like(^filter_pattern)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Gets a single equipment.

  Raises `Ecto.NoResultsError` if the Equipment does not exist.

  ## Examples

      iex> get_equipment!(123)
      %Equipment{}

      iex> get_equipment!(456)
      ** (Ecto.NoResultsError)

  """
  def get_equipment!(id), do: Repo.get!(Equipment, id)

  @doc """
  Gets equipment by name.

  Returns nil if equipment doesn't exist.
  """
  def get_equipment_by_name(name) when is_binary(name) do
    Repo.get_by(Equipment, name: name)
  end

  @doc """
  Creates a equipment.

  ## Examples

      iex> create_equipment(%{field: value})
      {:ok, %Equipment{}}

      iex> create_equipment(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_equipment(attrs \\ %{}) do
    %Equipment{}
    |> Equipment.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a equipment.

  ## Examples

      iex> update_equipment(equipment, %{field: new_value})
      {:ok, %Equipment{}}

      iex> update_equipment(equipment, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_equipment(%Equipment{} = equipment, attrs) do
    equipment
    |> Equipment.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a equipment.

  ## Examples

      iex> delete_equipment(equipment)
      {:ok, %Equipment{}}

      iex> delete_equipment(equipment)
      {:error, %Ecto.Changeset{}}

  """
  def delete_equipment(%Equipment{} = equipment) do
    Repo.delete(equipment)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking equipment changes.

  ## Examples

      iex> change_equipment(equipment)
      %Ecto.Changeset{data: %Equipment{}}

  """
  def change_equipment(%Equipment{} = equipment, attrs \\ %{}) do
    Equipment.changeset(equipment, attrs)
  end
end

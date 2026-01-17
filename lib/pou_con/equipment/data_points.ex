defmodule PouCon.Equipment.DataPoints do
  @moduledoc """
  The DataPoints context.
  """

  import Ecto.Query, warn: false
  alias PouCon.Repo

  alias PouCon.Equipment.Schemas.DataPoint

  @doc """
  Returns the list of data_points.

  ## Examples

      iex> list_data_points()
      [%DataPoint{}, ...]

  """
  def list_data_points(opts \\ []) do
    sort_field = Keyword.get(opts, :sort_field, :name)
    sort_order = Keyword.get(opts, :sort_order, :asc)
    filter = Keyword.get(opts, :filter)

    query =
      DataPoint
      |> order_by({^sort_order, ^sort_field})

    query =
      if filter && String.trim(filter) != "" do
        filter_pattern = "%#{String.downcase(filter)}%"

        from d in query,
          where:
            fragment("lower(?)", d.name) |> like(^filter_pattern) or
              fragment("lower(?)", d.type) |> like(^filter_pattern)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Gets a single data_point.

  Raises `Ecto.NoResultsError` if the DataPoint does not exist.

  ## Examples

      iex> get_data_point!(123)
      %DataPoint{}

      iex> get_data_point!(456)
      ** (Ecto.NoResultsError)

  """
  def get_data_point!(id), do: Repo.get!(DataPoint, id)

  @doc """
  Creates a data_point.

  ## Examples

      iex> create_data_point(%{field: value})
      {:ok, %DataPoint{}}

      iex> create_data_point(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_data_point(attrs) do
    %DataPoint{}
    |> DataPoint.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a data_point.

  ## Examples

      iex> update_data_point(data_point, %{field: new_value})
      {:ok, %DataPoint{}}

      iex> update_data_point(data_point, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_data_point(%DataPoint{} = data_point, attrs) do
    data_point
    |> DataPoint.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a data_point.

  ## Examples

      iex> delete_data_point(data_point)
      {:ok, %DataPoint{}}

      iex> delete_data_point(data_point)
      {:error, %Ecto.Changeset{}}

  """
  def delete_data_point(%DataPoint{} = data_point) do
    Repo.delete(data_point)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking data_point changes.

  ## Examples

      iex> change_data_point(data_point)
      %Ecto.Changeset{data: %DataPoint{}}

  """
  def change_data_point(%DataPoint{} = data_point, attrs \\ %{}) do
    DataPoint.changeset(data_point, attrs)
  end

  @doc """
  Gets a single data_point by name.
  Returns nil if not found.
  """
  def get_data_point_by_name(name) when is_binary(name) do
    Repo.get_by(DataPoint, name: name)
  end

  @doc """
  Checks if a data point is virtual (port_path == "virtual").
  Returns false if data point not found.
  """
  def is_virtual?(name) when is_binary(name) do
    case get_data_point_by_name(name) do
      %DataPoint{port_path: "virtual"} -> true
      _ -> false
    end
  end
end

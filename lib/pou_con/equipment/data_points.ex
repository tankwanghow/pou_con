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

  @doc """
  Validates that all data points in a list have matching color_zones.
  Returns {:ok, color_zones} if all match, or {:error, reason} if they don't.

  Used by AverageSensor to ensure consistent color coding for averaged values.
  """
  def validate_matching_color_zones([]), do: {:ok, nil}

  def validate_matching_color_zones(data_point_names) when is_list(data_point_names) do
    # Fetch all data points and their color_zones
    data_points =
      data_point_names
      |> Enum.map(fn name ->
        case get_data_point_by_name(name) do
          nil -> {name, :not_found}
          dp -> {name, dp.color_zones}
        end
      end)

    # Check for missing data points
    missing = Enum.filter(data_points, fn {_name, zones} -> zones == :not_found end)

    if length(missing) > 0 do
      missing_names = Enum.map(missing, fn {name, _} -> name end)
      {:error, {:not_found, missing_names}}
    else
      # Normalize color_zones for comparison (nil and "[]" and [] are equivalent)
      normalized =
        Enum.map(data_points, fn {name, zones} ->
          {name, normalize_color_zones(zones)}
        end)

      # Get all unique color_zones
      unique_zones =
        normalized
        |> Enum.map(fn {_name, zones} -> zones end)
        |> Enum.uniq()

      case unique_zones do
        [single_zones] ->
          # All match - return the shared color_zones
          {:ok, single_zones}

        _multiple ->
          # Find which data points have different zones
          first_zones = normalized |> List.first() |> elem(1)

          mismatched =
            normalized
            |> Enum.filter(fn {_name, zones} -> zones != first_zones end)
            |> Enum.map(fn {name, _} -> name end)

          {:error, {:mismatched, mismatched}}
      end
    end
  end

  defp normalize_color_zones(nil), do: []
  defp normalize_color_zones(""), do: []
  defp normalize_color_zones("[]"), do: []

  defp normalize_color_zones(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, zones} when is_list(zones) -> zones
      _ -> []
    end
  end

  defp normalize_color_zones(zones) when is_list(zones), do: zones
  defp normalize_color_zones(_), do: []

  @doc """
  Gets the color_zones for a data point by name.
  Returns parsed list or empty list if not found/not set.
  """
  def get_color_zones(name) when is_binary(name) do
    case get_data_point_by_name(name) do
      nil -> []
      dp -> normalize_color_zones(dp.color_zones)
    end
  end
end

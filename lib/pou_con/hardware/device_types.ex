defmodule PouCon.Hardware.DeviceTypes do
  @moduledoc """
  The DeviceTypes context for managing generic device type templates.

  Device types define register maps for simple Modbus devices that don't
  require custom parsing logic. Complex devices should use dedicated
  device modules instead.
  """

  import Ecto.Query, warn: false
  alias PouCon.Repo
  alias PouCon.Hardware.DeviceType

  @doc """
  Returns the list of device types.

  ## Options

    * `:sort_field` - Field to sort by (default: `:name`)
    * `:sort_order` - Sort order, `:asc` or `:desc` (default: `:asc`)
    * `:filter` - Filter string to search name, manufacturer, model
    * `:category` - Filter by category

  ## Examples

      iex> list_device_types()
      [%DeviceType{}, ...]

      iex> list_device_types(category: "sensor")
      [%DeviceType{category: "sensor"}, ...]

  """
  def list_device_types(opts \\ []) do
    sort_field = Keyword.get(opts, :sort_field, :name)
    sort_order = Keyword.get(opts, :sort_order, :asc)
    filter = Keyword.get(opts, :filter)
    category = Keyword.get(opts, :category)

    query =
      DeviceType
      |> order_by({^sort_order, ^sort_field})

    query =
      if filter && String.trim(filter) != "" do
        filter_pattern = "%#{String.downcase(filter)}%"

        from dt in query,
          where:
            fragment("lower(?)", dt.name) |> like(^filter_pattern) or
              fragment("lower(coalesce(?, ''))", dt.manufacturer) |> like(^filter_pattern) or
              fragment("lower(coalesce(?, ''))", dt.model) |> like(^filter_pattern)
      else
        query
      end

    query =
      if category && category != "" do
        from dt in query, where: dt.category == ^category
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Returns device types as options for select inputs.

  Returns a list of tuples: `[{"Display Name", id}, ...]`
  """
  def device_type_options do
    DeviceType
    |> order_by(:name)
    |> select([dt], {fragment("? || ' (' || ? || ')'", dt.name, dt.category), dt.id})
    |> Repo.all()
  end

  @doc """
  Gets a single device type.

  Raises `Ecto.NoResultsError` if the DeviceType does not exist.

  ## Examples

      iex> get_device_type!(123)
      %DeviceType{}

      iex> get_device_type!(456)
      ** (Ecto.NoResultsError)

  """
  def get_device_type!(id), do: Repo.get!(DeviceType, id)

  @doc """
  Gets a device type by name.

  Returns nil if not found.
  """
  def get_device_type_by_name(name) when is_binary(name) do
    Repo.get_by(DeviceType, name: name)
  end

  @doc """
  Creates a device type.

  ## Examples

      iex> create_device_type(%{name: "temp_sensor", category: "sensor", register_map: %{...}})
      {:ok, %DeviceType{}}

      iex> create_device_type(%{name: nil})
      {:error, %Ecto.Changeset{}}

  """
  def create_device_type(attrs \\ %{}) do
    %DeviceType{}
    |> DeviceType.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a device type.

  ## Examples

      iex> update_device_type(device_type, %{name: "new_name"})
      {:ok, %DeviceType{}}

      iex> update_device_type(device_type, %{name: nil})
      {:error, %Ecto.Changeset{}}

  """
  def update_device_type(%DeviceType{} = device_type, attrs) do
    device_type
    |> DeviceType.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a device type.

  Will fail if any devices reference this type.

  ## Examples

      iex> delete_device_type(device_type)
      {:ok, %DeviceType{}}

      iex> delete_device_type(device_type_with_devices)
      {:error, %Ecto.Changeset{}}

  """
  def delete_device_type(%DeviceType{} = device_type) do
    Repo.delete(device_type)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking device type changes.

  ## Examples

      iex> change_device_type(device_type)
      %Ecto.Changeset{data: %DeviceType{}}

  """
  def change_device_type(%DeviceType{} = device_type, attrs \\ %{}) do
    DeviceType.changeset(device_type, attrs)
  end

  @doc """
  Returns the list of valid categories.
  """
  def categories do
    DeviceType.categories()
  end
end

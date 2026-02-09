defmodule PouCon.Equipment.Schemas.DataPoint do
  @moduledoc """
  Schema for data points (Modbus RTU/TCP, S7, etc.).

  Each data point represents a single readable/writable value at a specific address.
  The data point is self-describing with its own conversion parameters.

  ## Logging Configuration

  The `log_interval` field controls how this data point's values are logged:

  - `nil` (default): Log on value change - whenever the value differs from the last logged value
  - `0`: No logging - this data point is not logged
  - `> 0`: Interval logging - log every N seconds regardless of value change

  ## Configuration

  For digital and analog I/O, specify `read_fn` and `write_fn` strings that map
  to functions in the unified device modules (`DigitalIO`, `AnalogIO`).
  These work across all protocols (Modbus RTU, Modbus TCP, S7).

  ### Digital I/O Example

      %DataPoint{
        name: "relay_1",
        type: "DO",
        slave_id: 1,
        register: 0,
        channel: 1,
        read_fn: "read_digital_output",
        write_fn: "write_digital_output"
      }

  ### Analog Input Example (with conversion)

      %DataPoint{
        name: "temp_sensor_1",
        type: "AI",
        slave_id: 2,
        register: 0,
        read_fn: "read_analog_input",
        value_type: "int16",
        scale_factor: 0.1,
        offset: 0.0,
        unit: "°C",
        min_valid: -40.0,
        max_valid: 80.0
      }

  The conversion formula is: `converted = (raw * scale_factor) + offset`
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "data_points" do
    field :name, :string
    field :type, :string
    field :slave_id, :integer
    field :register, :integer
    field :channel, :integer
    field :read_fn, :string
    field :write_fn, :string
    field :description, :string

    # Conversion fields - protocol agnostic
    # Formula: converted = (raw * scale_factor) + offset
    field :scale_factor, :float, default: 1.0
    field :offset, :float, default: 0.0

    # Metadata for display and validation
    field :unit, :string
    field :value_type, :string

    # Byte order for 32-bit values (uint32, int32, float32)
    # "high_low" = standard Modbus (high word first, most common)
    # "low_high" = DIJIANG/some Chinese meters (low word first)
    field :byte_order, :string, default: "high_low"

    # Validation range (optional)
    field :min_valid, :float
    field :max_valid, :float

    # Zone-based color system
    # JSON array of zones: [{"from": 0, "to": 25, "color": "green"}, ...]
    # Max 5 zones, colors: red, green, yellow, blue, purple
    # Values outside all zones show as gray
    # Use min_valid/max_valid as the overall valid range for UI guidance
    field :color_zones, :string

    # Logging configuration
    # nil = log on change, 0 = no logging, > 0 = interval in seconds
    field :log_interval, :integer

    # Digital output inversion for NC (normally closed) relay wiring
    # When true: coil OFF (0) = equipment ON, coil ON (1) = equipment OFF
    field :inverted, :boolean, default: false

    belongs_to :port, PouCon.Hardware.Ports.Port,
      foreign_key: :port_path,
      references: :device_path,
      type: :string

    timestamps()
  end

  @doc false
  def changeset(data_point, attrs) do
    data_point
    |> cast(attrs, [
      :name,
      :type,
      :slave_id,
      :register,
      :channel,
      :read_fn,
      :write_fn,
      :description,
      :port_path,
      # Conversion fields
      :scale_factor,
      :offset,
      :unit,
      :value_type,
      :byte_order,
      :min_valid,
      :max_valid,
      # Zone-based color system
      :color_zones,
      # Logging
      :log_interval,
      # Digital output inversion
      :inverted
    ])
    |> validate_number(:log_interval, greater_than_or_equal_to: 0)
    |> validate_color_zones()
    |> validate_required([:name, :type, :slave_id, :port_path])
    |> unique_constraint(:name)
  end

  @valid_zone_colors ~w(red green yellow blue purple)

  defp validate_color_zones(changeset) do
    case get_change(changeset, :color_zones) do
      nil ->
        changeset

      "" ->
        changeset

      json when is_binary(json) ->
        case Jason.decode(json) do
          {:ok, zones} when is_list(zones) ->
            if valid_zones?(zones) do
              changeset
            else
              add_error(
                changeset,
                :color_zones,
                "must be a list of zones with 'from', 'to' (numbers) and 'color' (#{Enum.join(@valid_zone_colors, ", ")})"
              )
            end

          {:ok, _} ->
            add_error(changeset, :color_zones, "must be a JSON array of zones")

          {:error, _} ->
            add_error(changeset, :color_zones, "must be valid JSON")
        end

      _ ->
        changeset
    end
  end

  defp valid_zones?(zones) when is_list(zones) do
    length(zones) <= 5 and Enum.all?(zones, &valid_zone?/1)
  end

  defp valid_zone?(%{"from" => from, "to" => to, "color" => color})
       when is_number(from) and is_number(to) and is_binary(color) do
    color in @valid_zone_colors and from < to
  end

  defp valid_zone?(_), do: false

  @doc """
  Parses color_zones JSON string into a list of zone maps.
  Returns empty list if nil or invalid.
  """
  def parse_color_zones(nil), do: []
  def parse_color_zones(""), do: []

  def parse_color_zones(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, zones} when is_list(zones) -> zones
      _ -> []
    end
  end

  def parse_color_zones(_), do: []

  @doc """
  Determines the color for a value based on color_zones.
  Returns the color string or "gray" if no zone matches.
  """
  def color_for_value(value, zones) when is_number(value) and is_list(zones) do
    Enum.find_value(zones, "gray", fn zone ->
      from = zone["from"]
      to = zone["to"]

      if is_number(from) and is_number(to) and value >= from and value < to do
        zone["color"]
      end
    end)
  end

  def color_for_value(_, _), do: "gray"
end

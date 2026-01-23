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

    # Logging configuration
    # nil = log on change, 0 = no logging, > 0 = interval in seconds
    field :log_interval, :integer

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
      # Logging
      :log_interval
    ])
    |> validate_number(:log_interval, greater_than_or_equal_to: 0)
    |> validate_required([:name, :type, :slave_id, :port_path])
    |> unique_constraint(:name)
  end
end

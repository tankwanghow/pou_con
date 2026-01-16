defmodule PouCon.Equipment.Schemas.DataPoint do
  @moduledoc """
  Schema for data points (Modbus RTU/TCP, S7, etc.).

  Each data point represents a single readable/writable value at a specific address.
  The data point is self-describing with its own conversion parameters.

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

    # Validation range (optional)
    field :min_valid, :float
    field :max_valid, :float

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
      :min_valid,
      :max_valid
    ])
    |> validate_required([:name, :type, :slave_id, :port_path])
    |> unique_constraint(:name)
  end
end

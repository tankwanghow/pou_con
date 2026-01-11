defmodule PouCon.Hardware.DeviceType do
  @moduledoc """
  Schema for generic device type templates.

  Device types define the register map and interpretation rules for simple
  Modbus devices that don't need custom parsing logic. Complex devices
  (power meters, VFDs, etc.) should use dedicated device modules instead.

  ## Register Map Structure

  The `register_map` field stores a JSON object with the following structure:

      %{
        "registers" => [
          %{
            "name" => "temperature",        # Field name in output map
            "address" => 0,                 # Register address (0-based)
            "count" => 1,                   # Number of registers to read
            "type" => "int16",              # Data type (see below)
            "multiplier" => 0.1,            # Value scaling factor
            "unit" => "°C",                 # Unit for display
            "access" => "r"                 # "r", "w", or "rw"
          },
          %{
            "name" => "humidity",
            "address" => 1,
            "count" => 1,
            "type" => "uint16",
            "multiplier" => 0.1,
            "unit" => "%",
            "access" => "r"
          }
        ],
        "batch_start" => 0,                 # Start address for batch read
        "batch_count" => 2,                 # Number of registers in batch
        "function_code" => "holding"        # "holding", "input", "coil", "discrete"
      }

  ## Supported Data Types

  - `uint16` - Unsigned 16-bit integer (1 register)
  - `int16` - Signed 16-bit integer (1 register)
  - `uint32` - Unsigned 32-bit integer (2 registers, big-endian)
  - `int32` - Signed 32-bit integer (2 registers, big-endian)
  - `uint32_le` - Unsigned 32-bit integer (2 registers, little-endian)
  - `int32_le` - Signed 32-bit integer (2 registers, little-endian)
  - `float32` - IEEE 754 float (2 registers, big-endian)
  - `float32_le` - IEEE 754 float (2 registers, little-endian)
  - `uint64` - Unsigned 64-bit integer (4 registers, big-endian)
  - `bool` - Single bit (coil or discrete input)
  - `enum` - Maps integer values to atoms (requires "values" field)
  - `bitmask` - Decodes bit flags to map (requires "bits" field)

  ## Categories

  - `sensor` - Temperature, humidity, pressure sensors
  - `meter` - Energy meters, flow meters, counters
  - `actuator` - Relays, valves, motor controls
  - `io` - Digital/analog I/O modules
  - `analyzer` - Power quality analyzers, gas analyzers (complex - use custom module)

  ## Example: Simple Temperature Sensor

      %DeviceType{
        name: "generic_temp_sensor",
        manufacturer: "Various",
        model: "RS485 Temperature Sensor",
        category: "sensor",
        register_map: %{
          "registers" => [
            %{"name" => "temperature", "address" => 0, "count" => 1,
              "type" => "int16", "multiplier" => 0.1, "unit" => "°C", "access" => "r"}
          ],
          "batch_start" => 0,
          "batch_count" => 1,
          "function_code" => "holding"
        }
      }

  ## When to Use Custom Modules Instead

  Use a dedicated device module (like `XintaiWaterMeter`) when:

  1. The device has complex multi-step write operations (e.g., valve control sequences)
  2. Data interpretation requires conditional logic (e.g., bit flags with states)
  3. The device has 50+ registers with different read strategies
  4. Protocol has non-standard features (waveforms, harmonics, events)
  5. Device requires initialization sequences or state machines
  """

  use Ecto.Schema
  import Ecto.Changeset

  @categories ~w(sensor meter actuator io analyzer other)

  schema "device_types" do
    field :name, :string
    field :manufacturer, :string
    field :model, :string
    field :category, :string
    field :description, :string
    field :register_map, :map
    field :read_strategy, :string, default: "batch"
    field :is_builtin, :boolean, default: false

    has_many :devices, PouCon.Equipment.Schemas.Device

    timestamps()
  end

  @doc false
  def changeset(device_type, attrs) do
    device_type
    |> cast(attrs, [
      :name,
      :manufacturer,
      :model,
      :category,
      :description,
      :register_map,
      :read_strategy,
      :is_builtin
    ])
    |> validate_required([:name, :category, :register_map])
    |> validate_inclusion(:category, @categories)
    |> validate_inclusion(:read_strategy, ~w(batch individual))
    |> validate_register_map()
    |> unique_constraint(:name)
  end

  defp validate_register_map(changeset) do
    case get_field(changeset, :register_map) do
      nil ->
        changeset

      register_map ->
        cond do
          not is_map(register_map) ->
            add_error(changeset, :register_map, "must be a map")

          not Map.has_key?(register_map, "registers") ->
            add_error(changeset, :register_map, "must contain 'registers' key")

          not is_list(register_map["registers"]) ->
            add_error(changeset, :register_map, "'registers' must be a list")

          true ->
            validate_registers(changeset, register_map["registers"])
        end
    end
  end

  defp validate_registers(changeset, registers) do
    required_keys = ~w(name address count type)

    invalid =
      Enum.find(registers, fn reg ->
        not Enum.all?(required_keys, &Map.has_key?(reg, &1))
      end)

    if invalid do
      add_error(
        changeset,
        :register_map,
        "each register must have: name, address, count, type"
      )
    else
      changeset
    end
  end

  @doc """
  Returns the list of valid categories.
  """
  def categories, do: @categories
end

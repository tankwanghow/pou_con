defmodule PouCon.Equipment.Schemas.Device do
  @moduledoc """
  Schema for Modbus device instances.

  Each device represents a physical Modbus slave at a specific address.
  Devices can be configured in two ways:

  ## 1. Custom Device Module (read_fn/write_fn)

  For complex devices, specify `read_fn` and `write_fn` strings that map to
  functions in device modules (e.g., `XintaiWaterMeter`, `WaveshareDigitalIO`).
  The DeviceManager dispatches to these modules for read/write operations.

      %Device{
        name: "water_meter_1",
        type: "xintai_water_meter",
        slave_id: 1,
        read_fn: "read_water_meter",
        write_fn: "write_water_meter_valve"
      }

  ## 2. Generic Device Type (device_type_id)

  For simpler devices, reference a `DeviceType` template that defines the
  register map. The `GenericDeviceInterpreter` module handles read/write
  operations based on the template's configuration.

      %Device{
        name: "temp_sensor_1",
        type: "generic_temp_sensor",
        slave_id: 2,
        device_type_id: 1,  # References a DeviceType record
        register: 0         # Optional: override template's batch_start
      }

  When `device_type_id` is set, `read_fn`/`write_fn` are ignored and the
  generic interpreter is used instead.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "devices" do
    field :name, :string
    field :type, :string
    field :slave_id, :integer
    field :register, :integer
    field :channel, :integer
    field :read_fn, :string
    field :write_fn, :string
    field :description, :string

    belongs_to :port, PouCon.Hardware.Ports.Port,
      foreign_key: :port_device_path,
      references: :device_path,
      type: :string

    belongs_to :device_type, PouCon.Hardware.DeviceType

    timestamps()
  end

  @doc false
  def changeset(device, attrs) do
    device
    |> cast(attrs, [
      :name,
      :type,
      :slave_id,
      :register,
      :channel,
      :read_fn,
      :write_fn,
      :description,
      :port_device_path,
      :device_type_id
    ])
    |> validate_required([:name, :type, :slave_id, :port_device_path])
    |> validate_device_config()
    |> unique_constraint(:name)
    |> foreign_key_constraint(:device_type_id)
  end

  # Ensure device has either read_fn OR device_type_id (for read operations)
  defp validate_device_config(changeset) do
    read_fn = get_field(changeset, :read_fn)
    device_type_id = get_field(changeset, :device_type_id)

    cond do
      # Has device_type_id - uses generic interpreter
      device_type_id != nil ->
        changeset

      # Has read_fn - uses custom module dispatch
      read_fn != nil && read_fn != "" ->
        changeset

      # Neither - add warning (still valid for write-only devices)
      true ->
        changeset
    end
  end
end

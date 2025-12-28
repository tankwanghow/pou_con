defmodule PouCon.Logging.Schemas.WaterMeterSnapshot do
  @moduledoc """
  Schema for water meter periodic snapshots.
  Records flow data, temperature, and pressure readings every 30 minutes.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "water_meter_snapshots" do
    field :equipment_name, :string

    # Flow data
    field :positive_flow, :float
    field :negative_flow, :float
    field :flow_rate, :float

    # Optional sensor data (customized equipment)
    field :temperature, :float
    field :pressure, :float

    # Battery status
    field :battery_voltage, :float

    field :inserted_at, :utc_datetime_usec
  end

  @doc false
  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [
      :equipment_name,
      :positive_flow,
      :negative_flow,
      :flow_rate,
      :temperature,
      :pressure,
      :battery_voltage,
      :inserted_at
    ])
    |> validate_required([:equipment_name])
  end
end

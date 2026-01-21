defmodule PouCon.Logging.Schemas.DataPointLog do
  @moduledoc """
  Schema for data point value logs.

  Stores periodic or change-based snapshots of data point values.
  This is a unified logging table that replaces the old equipment-specific
  snapshot tables (sensor_snapshots, water_meter_snapshots, power_meter_snapshots).

  ## Fields

  - `data_point_name` - The name of the data point being logged
  - `value` - The converted value (after applying scale_factor and offset)
  - `raw_value` - The raw value before conversion (optional)
  - `unit` - The unit of measurement (copied from data point config)
  - `triggered_by` - What triggered this log entry:
    - "self" - Value change detected or interval elapsed (default)
    - Equipment name - If write was triggered by an equipment controller
    - Username - If write was triggered by manual user action

  ## Logging Modes

  Logging behavior is controlled by the data point's `log_interval` field:

  - `nil`: Log on value change (when value differs from last logged value)
  - `0`: No logging
  - `> 0`: Log every N seconds regardless of value change

  ## Retention

  Logs are automatically cleaned up after 30 days by CleanupTask.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "data_point_logs" do
    field :house_id, :string
    field :data_point_name, :string
    field :value, :float
    field :raw_value, :float
    field :unit, :string
    field :triggered_by, :string, default: "self"

    field :inserted_at, :utc_datetime_usec
  end

  @doc false
  def changeset(log, attrs) do
    log
    |> cast(attrs, [:house_id, :data_point_name, :value, :raw_value, :unit, :triggered_by, :inserted_at])
    |> validate_required([:house_id, :data_point_name, :inserted_at])
  end
end

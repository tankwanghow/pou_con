defmodule PouCon.Logging.Schemas.PowerMeterSnapshot do
  @moduledoc """
  Schema for power meter periodic snapshots.
  Records voltage, current, power, energy, and power quality data every 30 minutes.

  ## Key Fields for Generator Sizing

  - `power_total` - Instantaneous total power at snapshot time
  - `power_max` - Maximum power draw since last snapshot (for peak demand)
  - `power_min` - Minimum power draw since last snapshot (for base load)
  - `energy_import` - Cumulative imported energy (for consumption calculation)

  ## Consumption Calculation

  To calculate energy consumed over a period, subtract the `energy_import` of the
  first snapshot from the last snapshot in the range.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "power_meter_snapshots" do
    field :equipment_name, :string

    # Voltage readings (V)
    field :voltage_l1, :float
    field :voltage_l2, :float
    field :voltage_l3, :float

    # Current readings (A)
    field :current_l1, :float
    field :current_l2, :float
    field :current_l3, :float

    # Power readings (W) - instantaneous at snapshot time
    field :power_l1, :float
    field :power_l2, :float
    field :power_l3, :float
    field :power_total, :float

    # Power factor
    field :pf_avg, :float

    # Frequency (Hz)
    field :frequency, :float

    # Energy totals (kWh) - cumulative, for consumption by subtraction
    field :energy_import, :float
    field :energy_export, :float

    # Max/Min power (W) - for generator sizing
    field :power_max, :float
    field :power_min, :float

    # THD averages (%)
    field :thd_v_avg, :float
    field :thd_i_avg, :float

    field :inserted_at, :utc_datetime
  end

  @doc false
  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [
      :equipment_name,
      :voltage_l1,
      :voltage_l2,
      :voltage_l3,
      :current_l1,
      :current_l2,
      :current_l3,
      :power_l1,
      :power_l2,
      :power_l3,
      :power_total,
      :pf_avg,
      :frequency,
      :energy_import,
      :energy_export,
      :power_max,
      :power_min,
      :thd_v_avg,
      :thd_i_avg,
      :inserted_at
    ])
    |> validate_required([:equipment_name])
  end
end

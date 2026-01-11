defmodule PouCon.Repo.Migrations.CreatePowerMeterSnapshots do
  use Ecto.Migration

  def change do
    create table(:power_meter_snapshots) do
      add :equipment_name, :string, null: false

      # Voltage readings (V)
      add :voltage_l1, :float
      add :voltage_l2, :float
      add :voltage_l3, :float

      # Current readings (A)
      add :current_l1, :float
      add :current_l2, :float
      add :current_l3, :float

      # Power readings (W) - instantaneous at snapshot time
      add :power_l1, :float
      add :power_l2, :float
      add :power_l3, :float
      add :power_total, :float

      # Power factor
      add :pf_avg, :float

      # Frequency (Hz)
      add :frequency, :float

      # Energy totals (kWh) - cumulative, for consumption calculation by subtraction
      add :energy_import, :float
      add :energy_export, :float

      # Max/Min power since last snapshot (W) - for generator sizing
      # These track the peak and trough between snapshots
      add :power_max, :float
      add :power_min, :float

      # THD averages (%)
      add :thd_v_avg, :float
      add :thd_i_avg, :float

      add :inserted_at, :utc_datetime, null: false
    end

    create index(:power_meter_snapshots, [:equipment_name])
    create index(:power_meter_snapshots, [:inserted_at])
    create index(:power_meter_snapshots, [:equipment_name, :inserted_at])
  end
end

defmodule PouCon.Repo.Migrations.CreateWaterMeterSnapshots do
  use Ecto.Migration

  def change do
    create table(:water_meter_snapshots) do
      add :equipment_name, :string, null: false

      # Flow data
      add :positive_flow, :float
      add :negative_flow, :float
      add :flow_rate, :float

      # Optional sensor data (customized equipment)
      add :temperature, :float
      add :pressure, :float

      # Battery status
      add :battery_voltage, :float

      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:water_meter_snapshots, [:equipment_name, :inserted_at])
    create index(:water_meter_snapshots, [:inserted_at])
  end
end

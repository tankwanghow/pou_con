defmodule PouCon.Repo.Migrations.CreateLoggingTables do
  use Ecto.Migration

  def change do
    # Table 1: Equipment Events - Track all start/stop/error events
    create table(:equipment_events) do
      add :equipment_name, :string, null: false
      add :event_type, :string, null: false
      add :from_value, :string
      add :to_value, :string, null: false
      add :mode, :string, null: false
      add :triggered_by, :string, null: false
      add :metadata, :text

      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:equipment_events, [:equipment_name, :inserted_at])
    create index(:equipment_events, [:event_type, :inserted_at])
    create index(:equipment_events, [:inserted_at])
    create index(:equipment_events, [:mode])

    # Table 2: Sensor Snapshots - Temperature/humidity every 30 minutes
    create table(:sensor_snapshots) do
      add :equipment_name, :string, null: false
      add :temperature, :float
      add :humidity, :float
      add :dew_point, :float

      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:sensor_snapshots, [:equipment_name, :inserted_at])
    create index(:sensor_snapshots, [:inserted_at])

    # Table 3: Daily Summaries - Aggregated daily statistics
    create table(:daily_summaries) do
      add :date, :date, null: false
      add :equipment_name, :string, null: false
      add :equipment_type, :string, null: false

      # For sensors
      add :avg_temperature, :float
      add :min_temperature, :float
      add :max_temperature, :float
      add :avg_humidity, :float
      add :min_humidity, :float
      add :max_humidity, :float

      # For all equipment
      add :total_runtime_minutes, :integer
      add :total_cycles, :integer
      add :error_count, :integer
      add :state_change_count, :integer

      timestamps()
    end

    create unique_index(:daily_summaries, [:date, :equipment_name])
    create index(:daily_summaries, [:date])
    create index(:daily_summaries, [:equipment_type])
  end
end

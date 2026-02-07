defmodule PouCon.Repo.Migrations.DropDailySummariesTable do
  use Ecto.Migration

  def up do
    drop_if_exists table(:daily_summaries)
  end

  def down do
    create table(:daily_summaries) do
      add :house_id, :string, null: false, default: "unknown"
      add :date, :date, null: false
      add :equipment_name, :string, null: false
      add :equipment_type, :string
      add :avg_temperature, :float
      add :min_temperature, :float
      add :max_temperature, :float
      add :avg_humidity, :float
      add :min_humidity, :float
      add :max_humidity, :float
      add :total_runtime_minutes, :integer, default: 0
      add :total_cycles, :integer, default: 0
      add :error_count, :integer, default: 0
      add :state_change_count, :integer, default: 0

      timestamps()
    end

    create unique_index(:daily_summaries, [:date, :equipment_name])
    create index(:daily_summaries, [:house_id, :date])
  end
end

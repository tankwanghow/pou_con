defmodule PouCon.Repo.Migrations.CreateAlarmTables do
  use Ecto.Migration

  def change do
    # Alarm rules - groups conditions that trigger a siren
    create table(:alarm_rules) do
      add :name, :string, null: false
      # siren_names stored as JSON array in SQLite TEXT field
      add :siren_names, :text, default: "[]"
      add :logic, :string, null: false, default: "any"
      add :auto_clear, :boolean, null: false, default: true
      add :enabled, :boolean, null: false, default: true
      # Default 30 minutes max mute time
      add :max_mute_minutes, :integer, null: false, default: 30

      timestamps()
    end

    create index(:alarm_rules, [:enabled])

    # Alarm conditions - individual conditions within a rule
    create table(:alarm_conditions) do
      add :alarm_rule_id, references(:alarm_rules, on_delete: :delete_all), null: false
      add :source_type, :string, null: false
      add :source_name, :string, null: false
      add :condition, :string, null: false
      add :threshold, :float
      add :enabled, :boolean, null: false, default: true

      timestamps()
    end

    create index(:alarm_conditions, [:alarm_rule_id])
    create index(:alarm_conditions, [:source_name])
  end
end

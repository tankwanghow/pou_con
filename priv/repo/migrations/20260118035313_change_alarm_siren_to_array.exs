defmodule PouCon.Repo.Migrations.ChangeAlarmSirenToArray do
  use Ecto.Migration

  def change do
    # SQLite stores JSON as text, so we rename and change type
    # First, add the new column
    alter table(:alarm_rules) do
      add :siren_names, :text, default: "[]"
    end

    # Copy data from old column to new (as JSON array)
    execute(
      "UPDATE alarm_rules SET siren_names = '[\"' || siren_name || '\"]' WHERE siren_name IS NOT NULL",
      "UPDATE alarm_rules SET siren_name = json_extract(siren_names, '$[0]')"
    )

    # Drop the old index and column
    drop index(:alarm_rules, [:siren_name])

    alter table(:alarm_rules) do
      remove :siren_name
    end
  end
end

defmodule PouCon.Repo.Migrations.AddMaxMuteMinutesToAlarmRules do
  use Ecto.Migration

  def change do
    alter table(:alarm_rules) do
      # Default 30 minutes max mute time
      add :max_mute_minutes, :integer, null: false, default: 30
    end
  end
end

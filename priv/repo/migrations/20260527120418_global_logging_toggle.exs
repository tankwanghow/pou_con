defmodule PouCon.Repo.Migrations.GlobalLoggingToggle do
  use Ecto.Migration

  def up do
    alter table(:data_points) do
      remove :logging_enabled
    end

    execute(
      """
      INSERT INTO app_config (key, value, inserted_at, updated_at)
      VALUES ('data_point_logging_enabled', 'true', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      ON CONFLICT(key) DO NOTHING
      """,
      "DELETE FROM app_config WHERE key = 'data_point_logging_enabled'"
    )
  end

  def down do
    alter table(:data_points) do
      add :logging_enabled, :boolean, default: true, null: false
    end

    execute("DELETE FROM app_config WHERE key = 'data_point_logging_enabled'")
  end
end

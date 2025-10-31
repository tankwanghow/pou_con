defmodule PouCon.Repo.Migrations.CreateAppConfig do
  use Ecto.Migration

  def change do
    create table(:app_config) do
      add :key, :string, null: false
      # Optional for non-password keys
      add :password_hash, :string
      # For non-password keys like house_id
      add :value, :string

      timestamps()
    end

    create unique_index(:app_config, [:key])

    # Seed initial data
    execute """
    INSERT INTO app_config (key, password_hash, value, inserted_at, updated_at)
    VALUES
      ('admin_password', NULL, NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
      ('user_password', NULL, NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
      ('house_id', NULL, NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    ON CONFLICT DO NOTHING
    """
  end
end

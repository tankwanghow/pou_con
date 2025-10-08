defmodule PouCon.Repo.Migrations.CreateAppConfig do
  use Ecto.Migration

  def change do
    create table(:app_config) do
      add :password_hash, :string, null: false
      add :key, :string, null: false

      timestamps()
    end

    create unique_index(:app_config, [:key])
  end
end

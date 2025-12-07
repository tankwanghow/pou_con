defmodule PouCon.Repo.Migrations.CreateEggCollectionSchedules do
  use Ecto.Migration

  def change do
    create table(:egg_collection_schedules) do
      add :equipment_id, references(:equipment, on_delete: :delete_all), null: false
      add :name, :string
      add :start_time, :time, null: false
      add :stop_time, :time, null: false
      add :enabled, :boolean, default: true, null: false

      timestamps()
    end

    create index(:egg_collection_schedules, [:equipment_id])
  end
end

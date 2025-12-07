defmodule PouCon.Repo.Migrations.CreateLightSchedules do
  use Ecto.Migration

  def change do
    create table(:light_schedules) do
      add :equipment_id, references(:equipment, on_delete: :delete_all), null: false
      add :name, :string
      add :on_time, :time, null: false
      add :off_time, :time, null: false
      add :enabled, :boolean, default: true, null: false

      timestamps()
    end

    create index(:light_schedules, [:equipment_id])
  end
end

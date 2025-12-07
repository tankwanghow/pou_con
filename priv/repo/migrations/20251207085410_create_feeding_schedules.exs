defmodule PouCon.Repo.Migrations.CreateFeedingSchedules do
  use Ecto.Migration

  def change do
    create table(:feeding_schedules) do
      add :move_to_back_limit_time, :time
      add :move_to_front_limit_time, :time
      add :feedin_front_limit_bucket_id, references(:equipment, on_delete: :nilify_all)
      add :enabled, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:feeding_schedules, [:feedin_front_limit_bucket_id])
    create index(:feeding_schedules, [:enabled])
  end
end

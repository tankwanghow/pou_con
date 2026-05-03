defmodule PouCon.Repo.Migrations.ReplaceFeedinBucketWithTriggerAndMaxFill do
  use Ecto.Migration

  def up do
    alter table(:feeding_schedules) do
      add :trigger_fill, :boolean, default: false, null: false
      add :max_fill_minutes, :integer, default: 30, null: false
    end

    flush()

    execute("UPDATE feeding_schedules SET trigger_fill = 1 WHERE feedin_front_limit_bucket_id IS NOT NULL")

    drop index(:feeding_schedules, [:feedin_front_limit_bucket_id])

    alter table(:feeding_schedules) do
      remove :feedin_front_limit_bucket_id
    end
  end

  def down do
    alter table(:feeding_schedules) do
      add :feedin_front_limit_bucket_id, references(:equipment, on_delete: :nilify_all)
    end

    create index(:feeding_schedules, [:feedin_front_limit_bucket_id])

    alter table(:feeding_schedules) do
      remove :max_fill_minutes
      remove :trigger_fill
    end
  end
end

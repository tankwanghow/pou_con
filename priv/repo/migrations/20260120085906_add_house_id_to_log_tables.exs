defmodule PouCon.Repo.Migrations.AddHouseIdToLogTables do
  use Ecto.Migration

  @moduledoc """
  Adds house_id column to all logging tables for multi-house central aggregation.

  This enables:
  - Identifying which house each log record came from
  - Efficient queries by house on the central server
  - Safe merging of data from multiple houses
  """

  def change do
    # Add house_id to equipment_events
    alter table(:equipment_events) do
      add :house_id, :string, null: false, default: "unknown"
    end

    create index(:equipment_events, [:house_id, :inserted_at])

    # Add house_id to data_point_logs
    alter table(:data_point_logs) do
      add :house_id, :string, null: false, default: "unknown"
    end

    create index(:data_point_logs, [:house_id, :inserted_at])

    # Add house_id to daily_summaries
    alter table(:daily_summaries) do
      add :house_id, :string, null: false, default: "unknown"
    end

    create index(:daily_summaries, [:house_id, :date])

    # Update unique constraint to include house_id
    # First drop the old unique index, then create new one
    drop_if_exists index(:daily_summaries, [:date, :equipment_name])
    create unique_index(:daily_summaries, [:house_id, :date, :equipment_name])

    # Add house_id to flock_logs
    alter table(:flock_logs) do
      add :house_id, :string, null: false, default: "unknown"
    end

    create index(:flock_logs, [:house_id, :log_date])

    # Add house_id to task_completions
    alter table(:task_completions) do
      add :house_id, :string, null: false, default: "unknown"
    end

    create index(:task_completions, [:house_id, :completed_at])
  end
end

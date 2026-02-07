defmodule PouCon.Repo.Migrations.AddFeedUsageKgToFlockLogs do
  use Ecto.Migration

  def change do
    alter table(:flock_logs) do
      add :feed_usage_kg, :decimal, default: 0
    end
  end
end

defmodule PouCon.Repo.Migrations.AllowMultipleFlockLogsPerDay do
  use Ecto.Migration

  def change do
    drop unique_index(:flock_logs, [:flock_id, :log_date])
  end
end

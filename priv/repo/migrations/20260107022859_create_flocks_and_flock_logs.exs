defmodule PouCon.Repo.Migrations.CreateFlocksAndFlockLogs do
  use Ecto.Migration

  def change do
    create table(:flocks) do
      add :name, :string, null: false
      add :date_of_birth, :date, null: false
      add :quantity, :integer, null: false
      add :breed, :string
      add :notes, :text

      timestamps()
    end

    create unique_index(:flocks, [:name])

    create table(:flock_logs) do
      add :flock_id, references(:flocks, on_delete: :delete_all), null: false
      add :log_date, :date, null: false
      add :deaths, :integer, null: false, default: 0
      add :eggs, :integer, null: false, default: 0
      add :notes, :text

      timestamps()
    end

    create index(:flock_logs, [:flock_id])
    create unique_index(:flock_logs, [:flock_id, :log_date])
  end
end

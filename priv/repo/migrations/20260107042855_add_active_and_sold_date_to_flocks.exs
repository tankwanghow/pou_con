defmodule PouCon.Repo.Migrations.AddActiveAndSoldDateToFlocks do
  use Ecto.Migration

  def change do
    alter table(:flocks) do
      add :active, :boolean, default: false, null: false
      add :sold_date, :date
    end

    # Create a partial unique index to ensure only one active flock
    create unique_index(:flocks, [:active],
             where: "active = true",
             name: :flocks_single_active_index
           )
  end
end

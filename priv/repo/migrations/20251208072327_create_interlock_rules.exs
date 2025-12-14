defmodule PouCon.Repo.Migrations.CreateInterlockRules do
  use Ecto.Migration

  def change do
    create table(:interlock_rules) do
      add :upstream_equipment_id, references(:equipment, on_delete: :delete_all), null: false
      add :downstream_equipment_id, references(:equipment, on_delete: :delete_all), null: false
      add :enabled, :boolean, default: true, null: false

      timestamps()
    end

    create index(:interlock_rules, [:upstream_equipment_id])
    create index(:interlock_rules, [:downstream_equipment_id])

    create unique_index(:interlock_rules, [:upstream_equipment_id, :downstream_equipment_id],
             name: :interlock_rules_unique_pair
           )
  end
end

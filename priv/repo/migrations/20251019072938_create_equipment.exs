defmodule PouCon.Repo.Migrations.CreateEquipment do
  use Ecto.Migration

  def change do
    create table(:equipment) do
      add :name, :string, null: false
      add :title, :string
      add :type, :string, null: false
      add :device_tree, :text, null: false

      timestamps()
    end

    create unique_index(:equipment, [:name])
  end
end

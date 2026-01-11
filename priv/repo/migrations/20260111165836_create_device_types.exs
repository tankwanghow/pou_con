defmodule PouCon.Repo.Migrations.CreateDeviceTypes do
  use Ecto.Migration

  def change do
    create table(:device_types) do
      add :name, :string, null: false
      add :manufacturer, :string
      add :model, :string
      add :category, :string, null: false
      add :description, :text
      add :register_map, :map, null: false
      add :read_strategy, :string, default: "batch"
      add :is_builtin, :boolean, default: false

      timestamps()
    end

    create unique_index(:device_types, [:name])
    create index(:device_types, [:category])

    # Add optional reference from devices to device_types
    # When device_type_id is set, the device uses generic interpreter
    # When device_type_id is NULL, it uses the read_fn/write_fn dispatch
    alter table(:devices) do
      add :device_type_id, references(:device_types, on_delete: :nilify_all)
    end

    create index(:devices, [:device_type_id])
  end
end

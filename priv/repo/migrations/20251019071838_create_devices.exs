defmodule PouCon.Repo.Migrations.CreateDevices do
  use Ecto.Migration

  def change do
    create table(:devices) do
      add :name, :string, null: false
      add :type, :string, null: false
      add :slave_id, :integer, null: false
      add :read_fn, :string
      add :write_fn, :string
      add :register, :integer
      add :channel, :integer
      add :description, :string
      add :port_device_path, references(:ports, column: :device_path, type: :string), null: false

      timestamps()
    end

    create unique_index(:devices, [:name])
  end
end

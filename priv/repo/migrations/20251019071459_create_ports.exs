defmodule PouCon.Repo.Migrations.CreatePorts do
  use Ecto.Migration

  def change do
    create table(:ports) do
      add :device_path, :string, null: false
      add :speed, :integer, default: 9600
      add :parity, :string, default: "even"
      add :data_bits, :integer, default: 8
      add :stop_bits, :integer, default: 1
      add :description, :string

      timestamps()
    end

    create unique_index(:ports, [:device_path])
  end
end

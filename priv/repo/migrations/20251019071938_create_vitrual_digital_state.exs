defmodule PouCon.Repo.Migrations.CreateVirtualDigitalStates do
  use Ecto.Migration

  def change do
    create table(:virtual_digital_states) do
      add :slave_id, :integer
      add :channel, :integer
      add :state, :integer

      timestamps()
    end

    create unique_index(:virtual_digital_states, [:slave_id, :channel])
  end
end

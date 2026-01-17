defmodule PouCon.Repo.Migrations.AddPollIntervalToEquipment do
  use Ecto.Migration

  def change do
    alter table(:equipment) do
      add :poll_interval_ms, :integer
    end
  end
end

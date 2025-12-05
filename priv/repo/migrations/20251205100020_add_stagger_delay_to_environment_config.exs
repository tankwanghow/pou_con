defmodule PouCon.Repo.Migrations.AddStaggerDelayToEnvironmentConfig do
  use Ecto.Migration

  def change do
    alter table(:environment_control_config) do
      add :stagger_delay_seconds, :integer, default: 5
    end
  end
end

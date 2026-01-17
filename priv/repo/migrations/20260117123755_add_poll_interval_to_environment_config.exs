defmodule PouCon.Repo.Migrations.AddPollIntervalToEnvironmentConfig do
  use Ecto.Migration

  def change do
    alter table(:environment_control_config) do
      add :environment_poll_interval_ms, :integer, default: 5000
    end
  end
end

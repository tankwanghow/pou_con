defmodule PouCon.Repo.Migrations.AddNcFansToEnvironmentConfig do
  use Ecto.Migration

  def change do
    alter table(:environment_control_config) do
      add :nc_fans, :text, default: ""
    end
  end
end

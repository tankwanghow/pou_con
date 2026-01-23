defmodule PouCon.Repo.Migrations.AddThresholdModeToDataPoints do
  use Ecto.Migration

  def change do
    alter table(:data_points) do
      add :threshold_mode, :string, default: "upper"
    end
  end
end

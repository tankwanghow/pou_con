defmodule PouCon.Repo.Migrations.AddInvertedToDataPoints do
  use Ecto.Migration

  def change do
    alter table(:data_points) do
      add :inverted, :boolean, default: false
    end
  end
end

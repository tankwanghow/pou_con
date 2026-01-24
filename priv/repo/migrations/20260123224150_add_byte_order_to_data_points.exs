defmodule PouCon.Repo.Migrations.AddByteOrderToDataPoints do
  use Ecto.Migration

  def change do
    alter table(:data_points) do
      add :byte_order, :string, default: "high_low"
    end
  end
end

defmodule PouCon.Repo.Migrations.AddColorZonesToDataPoints do
  use Ecto.Migration

  @moduledoc """
  Adds zone-based color system to data points.

  color_zones is a JSON array of zones:
  [{"from": 0, "to": 25, "color": "green"}, {"from": 25, "to": 35, "color": "yellow"}, ...]

  Max 5 zones. Colors: red, green, yellow, blue, purple
  Values outside all zones display as gray.
  """

  def change do
    alter table(:data_points) do
      add :color_zones, :string
    end
  end
end

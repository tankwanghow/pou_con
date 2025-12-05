defmodule PouCon.Repo.Migrations.CreateEnvironmentControlConfig do
  use Ecto.Migration

  def change do
    create table(:environment_control_config) do
      add :temp_min, :float, default: 25.0
      add :temp_max, :float, default: 32.0
      add :hum_min, :float, default: 50.0
      add :hum_max, :float, default: 80.0
      add :min_fans, :integer, default: 1
      add :max_fans, :integer, default: 4
      add :min_pumps, :integer, default: 0
      add :max_pumps, :integer, default: 2
      add :fan_order, :text, default: ""
      add :pump_order, :text, default: ""
      add :hysteresis, :float, default: 2.0
      add :enabled, :boolean, default: false

      timestamps()
    end
  end
end

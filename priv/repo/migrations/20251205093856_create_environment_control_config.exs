defmodule PouCon.Repo.Migrations.CreateEnvironmentControlConfig do
  use Ecto.Migration

  def change do
    create table(:environment_control_config) do
      add :stagger_delay_seconds, :integer, default: 5
      add :delay_between_step_seconds, :integer, default: 120

      # Humidity overrides for pump control
      # hum_max: If humidity >= hum_max, all pumps stop until humidity < hum_max
      # hum_min: If humidity <= hum_min, all pumps run until humidity > hum_min
      add :hum_min, :float, default: 40.0
      add :hum_max, :float, default: 80.0

      add :step_1_temp, :float, default: 24.0
      add :step_1_fans, :string, default: "fan_1, fan_2"
      add :step_1_pumps, :string, default: ""

      add :step_2_temp, :float, default: 26.0
      add :step_2_fans, :string, default: "fan_1, fan_2, fan_3, fan_4"
      add :step_2_pumps, :string, default: ""

      add :step_3_temp, :float, default: 28.0
      add :step_3_fans, :string, default: "fan_1, fan_2, fan_3, fan_4, fan_5, fan_6"
      add :step_3_pumps, :string, default: ""

      add :step_4_temp, :float, default: 30.0
      add :step_4_fans, :string, default: "fan_1, fan_2, fan_3, fan_4, fan_5, fan_6, fan_7, fan_8"
      add :step_4_pumps, :string, default: "pump_1"

      add :step_5_temp, :float, default: 32.0
      add :step_5_fans, :string, default: ""
      add :step_5_pumps, :string, default: "pump_1, pump_2"

      add :step_6_temp, :float, default: 34.0
      add :step_6_fans, :string, default: ""
      add :step_6_pumps, :string, default: "pump_1, pump_2, pump_3"

      add :step_7_temp, :float, default: 0.0
      add :step_7_fans, :string, default: ""
      add :step_7_pumps, :string, default: ""

      add :step_8_temp, :float, default: 0.0
      add :step_8_fans, :string, default: ""
      add :step_8_pumps, :string, default: ""

      add :step_9_temp, :float, default: 0.0
      add :step_9_fans, :string, default: ""
      add :step_9_pumps, :string, default: ""

      add :step_10_temp, :float, default: 0.0
      add :step_10_fans, :string, default: ""
      add :step_10_pumps, :string, default: ""

      add :enabled, :boolean, default: false

      timestamps()
    end
  end
end

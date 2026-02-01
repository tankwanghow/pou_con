defmodule PouCon.Repo.Migrations.AddTempDeltaConfig do
  @moduledoc """
  Add temperature delta configuration fields for front-to-back uniformity control.

  - temp_sensor_order: Comma-separated list of sensor data point names in airflow order (front to back)
  - max_temp_delta: Maximum acceptable temperature difference between front and back

  When delta exceeds max, the controller jumps to the highest step for maximum cooling.
  """
  use Ecto.Migration

  def change do
    alter table(:environment_control_config) do
      # Comma-separated list of temp sensor data point names in order (front to back)
      add :temp_sensor_order, :string, default: ""
      # Maximum acceptable temperature delta (front to back)
      add :max_temp_delta, :float, default: 5.0
    end
  end
end

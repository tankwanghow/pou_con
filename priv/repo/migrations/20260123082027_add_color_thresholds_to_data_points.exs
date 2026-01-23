defmodule PouCon.Repo.Migrations.AddColorThresholdsToDataPoints do
  use Ecto.Migration

  def change do
    alter table(:data_points) do
      # Display color thresholds for UI
      # green_low: below this is yellow (green zone lower bound)
      # yellow_low: below this is red (yellow zone lower bound)
      # red_low: critical low threshold
      # High thresholds are implied by mirroring around min_valid/max_valid
      add :green_low, :float
      add :yellow_low, :float
      add :red_low, :float
    end
  end
end

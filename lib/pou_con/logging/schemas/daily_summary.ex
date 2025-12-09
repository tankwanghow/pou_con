defmodule PouCon.Logging.Schemas.DailySummary do
  use Ecto.Schema
  import Ecto.Changeset

  schema "daily_summaries" do
    field :date, :date
    field :equipment_name, :string
    field :equipment_type, :string

    # For sensors
    field :avg_temperature, :float
    field :min_temperature, :float
    field :max_temperature, :float
    field :avg_humidity, :float
    field :min_humidity, :float
    field :max_humidity, :float

    # For all equipment
    field :total_runtime_minutes, :integer
    field :total_cycles, :integer
    field :error_count, :integer
    field :state_change_count, :integer

    timestamps()
  end

  @doc false
  def changeset(summary, attrs) do
    summary
    |> cast(attrs, [
      :date,
      :equipment_name,
      :equipment_type,
      :avg_temperature,
      :min_temperature,
      :max_temperature,
      :avg_humidity,
      :min_humidity,
      :max_humidity,
      :total_runtime_minutes,
      :total_cycles,
      :error_count,
      :state_change_count
    ])
    |> validate_required([:date, :equipment_name, :equipment_type])
    |> unique_constraint([:date, :equipment_name])
  end
end

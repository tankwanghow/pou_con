defmodule PouCon.Automation.Alarm.Schemas.AlarmCondition do
  use Ecto.Schema
  import Ecto.Changeset

  alias PouCon.Automation.Alarm.Schemas.AlarmRule

  schema "alarm_conditions" do
    field :source_type, :string
    field :source_name, :string
    field :condition, :string
    field :threshold, :float
    field :enabled, :boolean, default: true

    belongs_to :alarm_rule, AlarmRule

    timestamps()
  end

  @valid_source_types ["sensor", "equipment"]
  @valid_conditions ["above", "below", "equals", "off", "not_running", "error"]

  def changeset(condition, attrs) do
    condition
    |> cast(attrs, [:source_type, :source_name, :condition, :threshold, :enabled, :alarm_rule_id])
    |> validate_required([:source_type, :source_name, :condition])
    |> validate_inclusion(:source_type, @valid_source_types,
      message: "must be 'sensor' or 'equipment'"
    )
    |> validate_inclusion(:condition, @valid_conditions)
    |> validate_threshold_for_sensor()
  end

  defp validate_threshold_for_sensor(changeset) do
    source_type = get_field(changeset, :source_type)
    condition = get_field(changeset, :condition)

    if source_type == "sensor" and condition in ["above", "below", "equals"] do
      validate_required(changeset, [:threshold], message: "is required for sensor conditions")
    else
      changeset
    end
  end
end

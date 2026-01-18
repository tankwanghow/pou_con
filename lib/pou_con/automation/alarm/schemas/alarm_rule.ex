defmodule PouCon.Automation.Alarm.Schemas.AlarmRule do
  use Ecto.Schema
  import Ecto.Changeset

  alias PouCon.Automation.Alarm.Schemas.AlarmCondition

  schema "alarm_rules" do
    field :name, :string
    field :siren_names, {:array, :string}, default: []
    field :logic, :string, default: "any"
    field :auto_clear, :boolean, default: true
    field :enabled, :boolean, default: true
    field :max_mute_minutes, :integer, default: 30

    has_many :conditions, AlarmCondition, on_replace: :delete

    timestamps()
  end

  @valid_logic ["any", "all"]

  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [:name, :siren_names, :logic, :auto_clear, :enabled, :max_mute_minutes])
    |> validate_required([:name, :logic])
    |> validate_siren_names()
    |> validate_inclusion(:logic, @valid_logic, message: "must be 'any' or 'all'")
    |> validate_number(:max_mute_minutes, greater_than: 0, less_than_or_equal_to: 120)
    |> cast_assoc(:conditions, with: &AlarmCondition.changeset/2)
  end

  defp validate_siren_names(changeset) do
    case get_field(changeset, :siren_names) do
      nil -> add_error(changeset, :siren_names, "at least one siren must be selected")
      [] -> add_error(changeset, :siren_names, "at least one siren must be selected")
      _ -> changeset
    end
  end
end

defmodule PouCon.Logging.Schemas.EquipmentEvent do
  use Ecto.Schema
  import Ecto.Changeset

  schema "equipment_events" do
    field :equipment_name, :string
    field :event_type, :string
    field :from_value, :string
    field :to_value, :string
    field :mode, :string
    field :triggered_by, :string
    field :metadata, :string

    field :inserted_at, :utc_datetime_usec
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :equipment_name,
      :event_type,
      :from_value,
      :to_value,
      :mode,
      :triggered_by,
      :metadata,
      :inserted_at
    ])
    |> validate_required([:equipment_name, :event_type, :to_value, :mode, :triggered_by])
    |> validate_inclusion(:event_type, [
      "start",
      "stop",
      "error",
      "alarm_triggered",
      "alarm_cleared",
      "alarm_muted"
    ])
    |> validate_inclusion(:mode, ["auto", "manual"])
    |> validate_inclusion(:triggered_by, [
      "user",
      "schedule",
      "auto_control",
      "interlock",
      "system",
      "alarm_controller"
    ])
  end
end

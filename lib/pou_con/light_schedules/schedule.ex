defmodule PouCon.LightSchedules.Schedule do
  use Ecto.Schema
  import Ecto.Changeset

  schema "light_schedules" do
    field :name, :string
    field :on_time, :time
    field :off_time, :time
    field :enabled, :boolean, default: true

    belongs_to :equipment, PouCon.Devices.Equipment

    timestamps()
  end

  @doc false
  def changeset(schedule, attrs) do
    schedule
    |> cast(attrs, [:equipment_id, :name, :on_time, :off_time, :enabled])
    |> validate_required([:equipment_id, :on_time, :off_time])
    |> validate_times()
    |> foreign_key_constraint(:equipment_id)
  end

  defp validate_times(changeset) do
    on_time = get_field(changeset, :on_time)
    off_time = get_field(changeset, :off_time)

    if on_time && off_time && Time.compare(on_time, off_time) == :gt do
      add_error(changeset, :off_time, "must be after on_time")
    else
      changeset
    end
  end
end

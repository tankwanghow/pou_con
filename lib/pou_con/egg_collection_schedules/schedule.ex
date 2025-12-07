defmodule PouCon.EggCollectionSchedules.Schedule do
  use Ecto.Schema
  import Ecto.Changeset

  schema "egg_collection_schedules" do
    field :name, :string
    field :start_time, :time
    field :stop_time, :time
    field :enabled, :boolean, default: true

    belongs_to :equipment, PouCon.Devices.Equipment

    timestamps()
  end

  @doc false
  def changeset(schedule, attrs) do
    schedule
    |> cast(attrs, [:equipment_id, :name, :start_time, :stop_time, :enabled])
    |> validate_required([:equipment_id, :start_time, :stop_time])
    |> validate_times()
    |> foreign_key_constraint(:equipment_id)
  end

  defp validate_times(changeset) do
    start_time = get_field(changeset, :start_time)
    stop_time = get_field(changeset, :stop_time)

    if start_time && stop_time && Time.compare(start_time, stop_time) == :gt do
      add_error(changeset, :stop_time, "must be after start_time")
    else
      changeset
    end
  end
end

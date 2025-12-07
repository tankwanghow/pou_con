defmodule PouCon.FeedingSchedules.Schedule do
  use Ecto.Schema
  import Ecto.Changeset

  schema "feeding_schedules" do
    field :move_to_back_limit_time, :time
    field :move_to_front_limit_time, :time
    field :enabled, :boolean, default: true

    belongs_to :feedin_front_limit_bucket, PouCon.Devices.Equipment

    timestamps()
  end

  @doc false
  def changeset(schedule, attrs) do
    schedule
    |> cast(attrs, [:move_to_back_limit_time, :move_to_front_limit_time, :feedin_front_limit_bucket_id, :enabled])
    |> validate_at_least_one_time()
    |> foreign_key_constraint(:feedin_front_limit_bucket_id)
  end

  defp validate_at_least_one_time(changeset) do
    back_time = get_field(changeset, :move_to_back_limit_time)
    front_time = get_field(changeset, :move_to_front_limit_time)

    if is_nil(back_time) and is_nil(front_time) do
      add_error(
        changeset,
        :move_to_back_limit_time,
        "at least one of move_to_back_limit_time or move_to_front_limit_time must be set"
      )
    else
      changeset
    end
  end
end

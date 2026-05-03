defmodule PouCon.Automation.Feeding.Schemas.Schedule do
  use Ecto.Schema
  import Ecto.Changeset

  schema "feeding_schedules" do
    field :move_to_back_limit_time, :time
    field :move_to_front_limit_time, :time
    field :trigger_fill, :boolean, default: false
    field :max_fill_minutes, :integer, default: 30
    field :enabled, :boolean, default: true

    timestamps()
  end

  @doc false
  def changeset(schedule, attrs) do
    schedule
    |> cast(attrs, [
      :move_to_back_limit_time,
      :move_to_front_limit_time,
      :trigger_fill,
      :max_fill_minutes,
      :enabled
    ])
    |> validate_at_least_one_time()
    |> validate_number(:max_fill_minutes, greater_than: 0, less_than_or_equal_to: 120)
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

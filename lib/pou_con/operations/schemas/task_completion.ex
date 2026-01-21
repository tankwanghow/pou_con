defmodule PouCon.Operations.Schemas.TaskCompletion do
  use Ecto.Schema
  import Ecto.Changeset

  schema "task_completions" do
    field :house_id, :string
    field :completed_at, :utc_datetime
    field :completed_by, :string
    field :notes, :string
    field :duration_minutes, :integer

    belongs_to :task_template, PouCon.Operations.Schemas.TaskTemplate

    timestamps()
  end

  @doc false
  def changeset(completion, attrs) do
    completion
    |> cast(attrs, [
      :house_id,
      :task_template_id,
      :completed_at,
      :completed_by,
      :notes,
      :duration_minutes
    ])
    |> validate_required([:house_id, :task_template_id, :completed_at])
    |> validate_number(:duration_minutes, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:task_template_id)
  end
end

defmodule PouCon.Flock.Schemas.FlockLog do
  use Ecto.Schema
  import Ecto.Changeset

  alias PouCon.Flock.Schemas.Flock

  schema "flock_logs" do
    field :house_id, :string
    field :log_date, :date
    field :deaths, :integer, default: 0
    field :eggs, :integer, default: 0
    field :notes, :string

    belongs_to :flock, Flock

    timestamps()
  end

  def changeset(log, attrs) do
    log
    |> cast(attrs, [:house_id, :flock_id, :log_date, :deaths, :eggs, :notes])
    |> validate_required([:house_id, :flock_id, :log_date])
    |> validate_number(:deaths, greater_than_or_equal_to: 0)
    |> validate_number(:eggs, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:flock_id)
  end
end

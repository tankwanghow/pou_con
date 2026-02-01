defmodule PouCon.Flock.Schemas.FlockLog do
  use Ecto.Schema
  import Ecto.Changeset

  alias PouCon.Flock.Schemas.Flock

  @eggs_per_tray 30

  schema "flock_logs" do
    field :house_id, :string
    field :log_date, :date
    field :deaths, :integer, default: 0
    field :egg_trays, :integer, default: 0
    field :egg_pcs, :integer, default: 0
    field :notes, :string

    belongs_to :flock, Flock

    timestamps()
  end

  def changeset(log, attrs) do
    log
    |> cast(attrs, [:house_id, :flock_id, :log_date, :deaths, :egg_trays, :notes])
    |> validate_required([:house_id, :flock_id, :log_date])
    |> validate_number(:deaths, greater_than_or_equal_to: 0)
    |> validate_number(:egg_trays, greater_than_or_equal_to: 0)
    |> calculate_egg_pcs()
    |> foreign_key_constraint(:flock_id)
  end

  defp calculate_egg_pcs(changeset) do
    case get_change(changeset, :egg_trays) do
      nil -> changeset
      trays -> put_change(changeset, :egg_pcs, trays * @eggs_per_tray)
    end
  end
end

defmodule PouCon.Equipment.Schemas.VirtualDigitalState do
  use Ecto.Schema
  import Ecto.Changeset

  schema "virtual_digital_states" do
    field :slave_id, :integer
    field :channel, :integer
    field :state, :integer, default: 0

    timestamps()
  end

  def changeset(virtual_state, attrs) do
    virtual_state
    |> cast(attrs, [:slave_id, :channel, :state])
    |> validate_required([:slave_id, :channel, :state])
    |> validate_inclusion(:state, [0, 1])
    |> unique_constraint([:slave_id, :channel])
  end
end

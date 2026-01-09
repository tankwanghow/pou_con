defmodule PouCon.Flock.Schemas.Flock do
  use Ecto.Schema
  import Ecto.Changeset

  alias PouCon.Flock.Schemas.FlockLog

  schema "flocks" do
    field :name, :string
    field :date_of_birth, :date
    field :quantity, :integer
    field :breed, :string
    field :notes, :string
    field :active, :boolean, default: false
    field :sold_date, :date

    has_many :logs, FlockLog

    timestamps()
  end

  def changeset(flock, attrs) do
    flock
    |> cast(attrs, [:name, :date_of_birth, :quantity, :breed, :notes, :active, :sold_date])
    |> validate_required([:name, :date_of_birth, :quantity])
    |> validate_number(:quantity, greater_than: 0)
    |> unique_constraint(:name)
    |> unique_constraint(:active,
      name: :flocks_single_active_index,
      message: "another flock is already active"
    )
    |> validate_sold_date()
  end

  defp validate_sold_date(changeset) do
    active = get_field(changeset, :active)
    sold_date = get_field(changeset, :sold_date)

    cond do
      active == true && sold_date != nil ->
        add_error(changeset, :sold_date, "cannot have sold date when flock is active")

      active == false && sold_date == nil && not is_nil(get_field(changeset, :id)) ->
        # Existing inactive flock should have sold_date (optional warning, not enforced)
        changeset

      true ->
        changeset
    end
  end
end

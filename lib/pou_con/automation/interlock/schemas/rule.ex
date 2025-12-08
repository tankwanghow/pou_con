defmodule PouCon.Automation.Interlock.Schemas.Rule do
  use Ecto.Schema
  import Ecto.Changeset

  alias PouCon.Equipment.Schemas.Equipment

  schema "interlock_rules" do
    belongs_to :upstream_equipment, Equipment
    belongs_to :downstream_equipment, Equipment
    field :enabled, :boolean, default: true

    timestamps()
  end

  @doc false
  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [:upstream_equipment_id, :downstream_equipment_id, :enabled])
    |> validate_required([:upstream_equipment_id, :downstream_equipment_id])
    |> foreign_key_constraint(:upstream_equipment_id)
    |> foreign_key_constraint(:downstream_equipment_id)
    |> unique_constraint([:upstream_equipment_id, :downstream_equipment_id],
         name: :interlock_rules_upstream_equipment_id_downstream_equipment_id_index,
         message: "This interlock rule already exists"
       )
    |> validate_not_self_referencing()
  end

  defp validate_not_self_referencing(changeset) do
    upstream_id = get_field(changeset, :upstream_equipment_id)
    downstream_id = get_field(changeset, :downstream_equipment_id)

    if upstream_id && downstream_id && upstream_id == downstream_id do
      add_error(changeset, :downstream_equipment_id,
        "Equipment cannot be interlocked with itself")
    else
      changeset
    end
  end
end

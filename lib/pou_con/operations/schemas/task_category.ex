defmodule PouCon.Operations.Schemas.TaskCategory do
  use Ecto.Schema
  import Ecto.Changeset

  schema "task_categories" do
    field :name, :string
    field :color, :string, default: "gray"
    field :icon, :string
    field :sort_order, :integer, default: 0

    has_many :task_templates, PouCon.Operations.Schemas.TaskTemplate, foreign_key: :category_id

    timestamps()
  end

  @doc false
  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :color, :icon, :sort_order])
    |> validate_required([:name])
    |> unique_constraint(:name)
    |> validate_inclusion(
      :color,
      ~w(gray cyan amber emerald rose blue purple green yellow red orange)
    )
  end
end

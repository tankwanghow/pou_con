defmodule PouCon.Operations.Schemas.TaskTemplate do
  use Ecto.Schema
  import Ecto.Changeset

  @frequency_types ~w(daily weekly biweekly monthly every_n_days)
  @priorities ~w(low normal high urgent)
  @time_windows ~w(morning afternoon evening anytime)

  schema "task_templates" do
    field :name, :string
    field :description, :string
    field :frequency_type, :string, default: "daily"
    field :frequency_value, :integer, default: 1
    field :time_window, :string, default: "anytime"
    field :priority, :string, default: "normal"
    field :enabled, :boolean, default: true
    field :requires_notes, :boolean, default: false

    belongs_to :category, PouCon.Operations.Schemas.TaskCategory

    has_many :completions, PouCon.Operations.Schemas.TaskCompletion,
      foreign_key: :task_template_id

    timestamps()
  end

  def frequency_types, do: @frequency_types
  def priorities, do: @priorities
  def time_windows, do: @time_windows

  @doc false
  def changeset(template, attrs) do
    template
    |> cast(attrs, [
      :name,
      :description,
      :category_id,
      :frequency_type,
      :frequency_value,
      :time_window,
      :priority,
      :enabled,
      :requires_notes
    ])
    |> validate_required([:name, :frequency_type])
    |> validate_inclusion(:frequency_type, @frequency_types)
    |> validate_inclusion(:priority, @priorities)
    |> validate_inclusion(:time_window, @time_windows ++ [nil])
    |> validate_number(:frequency_value, greater_than: 0)
    |> validate_frequency_value()
  end

  defp validate_frequency_value(changeset) do
    frequency_type = get_field(changeset, :frequency_type)

    if frequency_type == "every_n_days" do
      validate_required(changeset, [:frequency_value])
    else
      changeset
    end
  end

  @doc """
  Returns the number of days between task occurrences.
  """
  def days_between(%__MODULE__{frequency_type: "daily"}), do: 1
  def days_between(%__MODULE__{frequency_type: "weekly"}), do: 7
  def days_between(%__MODULE__{frequency_type: "biweekly"}), do: 14
  def days_between(%__MODULE__{frequency_type: "monthly"}), do: 30
  def days_between(%__MODULE__{frequency_type: "every_n_days", frequency_value: n}), do: n

  @doc """
  Returns human-readable frequency description.
  """
  def frequency_label(%__MODULE__{frequency_type: "daily"}), do: "Daily"
  def frequency_label(%__MODULE__{frequency_type: "weekly"}), do: "Weekly"
  def frequency_label(%__MODULE__{frequency_type: "biweekly"}), do: "Every 2 Weeks"
  def frequency_label(%__MODULE__{frequency_type: "monthly"}), do: "Monthly"

  def frequency_label(%__MODULE__{frequency_type: "every_n_days", frequency_value: n}),
    do: "Every #{n} Days"
end

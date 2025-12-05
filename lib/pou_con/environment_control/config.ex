defmodule PouCon.EnvironmentControl.Config do
  use Ecto.Schema
  import Ecto.Changeset

  schema "environment_control_config" do
    field :temp_min, :float, default: 25.0
    field :temp_max, :float, default: 32.0
    field :hum_min, :float, default: 50.0
    field :hum_max, :float, default: 80.0
    field :min_fans, :integer, default: 1
    field :max_fans, :integer, default: 4
    field :min_pumps, :integer, default: 0
    field :max_pumps, :integer, default: 2
    field :fan_order, :string, default: ""
    field :pump_order, :string, default: ""
    field :hysteresis, :float, default: 2.0
    field :stagger_delay_seconds, :integer, default: 5
    field :nc_fans, :string, default: ""
    field :enabled, :boolean, default: false

    timestamps()
  end

  def changeset(config, attrs) do
    config
    |> cast(attrs, [
      :temp_min,
      :temp_max,
      :hum_min,
      :hum_max,
      :min_fans,
      :max_fans,
      :min_pumps,
      :max_pumps,
      :fan_order,
      :pump_order,
      :hysteresis,
      :stagger_delay_seconds,
      :nc_fans,
      :enabled
    ])
    |> validate_required([:temp_min, :temp_max, :hum_min, :hum_max])
    |> validate_number(:temp_min, less_than_or_equal_to: 50, greater_than_or_equal_to: 0)
    |> validate_number(:temp_max, less_than_or_equal_to: 50, greater_than_or_equal_to: 0)
    |> validate_number(:hum_min, less_than_or_equal_to: 100, greater_than_or_equal_to: 0)
    |> validate_number(:hum_max, less_than_or_equal_to: 100, greater_than_or_equal_to: 0)
    |> validate_number(:min_fans, greater_than_or_equal_to: 0)
    |> validate_number(:max_fans, greater_than_or_equal_to: 0)
    |> validate_number(:min_pumps, greater_than_or_equal_to: 0)
    |> validate_number(:max_pumps, greater_than_or_equal_to: 0)
    |> validate_number(:hysteresis, greater_than_or_equal_to: 0)
  end

  @doc """
  Parse fan_order string into list of equipment names.
  """
  def parse_order(nil), do: []
  def parse_order(""), do: []

  def parse_order(order_string) do
    order_string
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end
end

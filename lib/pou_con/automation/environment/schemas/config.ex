defmodule PouCon.Automation.Environment.Schemas.Config do
  use Ecto.Schema
  import Ecto.Changeset

  schema "environment_control_config" do
    field :stagger_delay_seconds, :integer, default: 5
    field :delay_between_step_seconds, :integer, default: 120

    # Humidity overrides for pump control
    field :hum_min, :float, default: 40.0
    field :hum_max, :float, default: 80.0

    field :enabled, :boolean, default: false

    # 10-step control configuration
    # Each step has: temp threshold, fan names (comma-separated), pump names (comma-separated)
    field :step_1_temp, :float, default: 24.0
    field :step_1_fans, :string, default: "fan_1, fan_2"
    field :step_1_pumps, :string, default: ""

    field :step_2_temp, :float, default: 26.0
    field :step_2_fans, :string, default: "fan_1, fan_2, fan_3, fan_4"
    field :step_2_pumps, :string, default: ""

    field :step_3_temp, :float, default: 28.0
    field :step_3_fans, :string, default: "fan_1, fan_2, fan_3, fan_4, fan_5, fan_6"
    field :step_3_pumps, :string, default: ""

    field :step_4_temp, :float, default: 30.0
    field :step_4_fans, :string, default: "fan_1, fan_2, fan_3, fan_4, fan_5, fan_6, fan_7, fan_8"
    field :step_4_pumps, :string, default: "pump_1"

    field :step_5_temp, :float, default: 32.0
    field :step_5_fans, :string, default: ""
    field :step_5_pumps, :string, default: "pump_1, pump_2"

    field :step_6_temp, :float, default: 34.0
    field :step_6_fans, :string, default: ""
    field :step_6_pumps, :string, default: "pump_1, pump_2, pump_3"

    field :step_7_temp, :float, default: 0.0
    field :step_7_fans, :string, default: ""
    field :step_7_pumps, :string, default: ""

    field :step_8_temp, :float, default: 0.0
    field :step_8_fans, :string, default: ""
    field :step_8_pumps, :string, default: ""

    field :step_9_temp, :float, default: 0.0
    field :step_9_fans, :string, default: ""
    field :step_9_pumps, :string, default: ""

    field :step_10_temp, :float, default: 0.0
    field :step_10_fans, :string, default: ""
    field :step_10_pumps, :string, default: ""

    timestamps()
  end

  @step_fields (for n <- 1..10, field <- [:temp, :fans, :pumps] do
                  String.to_atom("step_#{n}_#{field}")
                end)

  def changeset(config, attrs) do
    config
    |> cast(
      attrs,
      [:stagger_delay_seconds, :delay_between_step_seconds, :hum_min, :hum_max, :enabled] ++
        @step_fields
    )
    |> validate_number(:stagger_delay_seconds, greater_than_or_equal_to: 2)
    |> validate_number(:delay_between_step_seconds, greater_than_or_equal_to: 30)
    |> validate_number(:hum_min, greater_than_or_equal_to: 20, less_than_or_equal_to: 90)
    |> validate_number(:hum_max, greater_than_or_equal_to: 20, less_than_or_equal_to: 95)
    |> validate_step_temps()
  end

  defp validate_step_temps(changeset) do
    Enum.reduce(1..10, changeset, fn n, cs ->
      validate_number(cs, String.to_atom("step_#{n}_temp"),
        greater_than_or_equal_to: 0,
        less_than_or_equal_to: 50
      )
    end)
  end

  @doc """
  Parse comma-separated string into list of equipment names.
  """
  def parse_order(nil), do: []
  def parse_order(""), do: []

  def parse_order(order_string) do
    order_string
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  @doc """
  Extract steps as a sorted list of maps for the control algorithm.
  Only includes steps with temp > 0 (active steps).

  Returns: [%{temp: 24.0, fans: ["fan_1", "fan_2"], pumps: ["pump_1"]}, ...]
  """
  def get_active_steps(config) do
    1..10
    |> Enum.map(fn n ->
      %{
        step: n,
        temp: Map.get(config, String.to_atom("step_#{n}_temp")),
        fans: parse_order(Map.get(config, String.to_atom("step_#{n}_fans"))),
        pumps: parse_order(Map.get(config, String.to_atom("step_#{n}_pumps")))
      }
    end)
    |> Enum.filter(fn step -> step.temp > 0 end)
    |> Enum.sort_by(& &1.temp)
  end

  @doc """
  Find the appropriate step for a given temperature.
  Returns the highest step whose temp threshold is <= current_temp.
  If current_temp is below all thresholds, returns nil (no action needed).
  """
  def find_step_for_temp(config, current_temp) do
    config
    |> get_active_steps()
    |> Enum.filter(fn step -> current_temp >= step.temp end)
    |> List.last()
  end
end

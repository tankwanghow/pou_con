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

    # Polling interval for EnvironmentController
    field :environment_poll_interval_ms, :integer, default: 5000

    # Failsafe fans: number of fans user keeps in MANUAL mode + ON
    # System validates this matches actual manual+on fan count
    field :failsafe_fans_count, :integer, default: 1

    # 5-step control configuration
    # Each step has: temp threshold, extra_fans (integer count), pump names (comma-separated)
    # Total fans at step = failsafe_fans_count (manual) + extra_fans (auto)
    field :step_1_temp, :float, default: 0.0
    field :step_1_extra_fans, :integer, default: 0
    field :step_1_pumps, :string, default: ""

    field :step_2_temp, :float, default: 0.0
    field :step_2_extra_fans, :integer, default: 0
    field :step_2_pumps, :string, default: ""

    field :step_3_temp, :float, default: 0.0
    field :step_3_extra_fans, :integer, default: 0
    field :step_3_pumps, :string, default: ""

    field :step_4_temp, :float, default: 0.0
    field :step_4_extra_fans, :integer, default: 0
    field :step_4_pumps, :string, default: ""

    field :step_5_temp, :float, default: 0.0
    field :step_5_extra_fans, :integer, default: 0
    field :step_5_pumps, :string, default: ""

    timestamps()
  end

  @step_fields (for n <- 1..5, field <- [:temp, :extra_fans, :pumps] do
                  String.to_atom("step_#{n}_#{field}")
                end)

  def changeset(config, attrs) do
    config
    |> cast(
      attrs,
      [
        :stagger_delay_seconds,
        :delay_between_step_seconds,
        :hum_min,
        :hum_max,
        :enabled,
        :environment_poll_interval_ms,
        :failsafe_fans_count
      ] ++
        @step_fields
    )
    |> validate_number(:stagger_delay_seconds, greater_than_or_equal_to: 2)
    |> validate_number(:delay_between_step_seconds, greater_than_or_equal_to: 30)
    |> validate_number(:hum_min, greater_than_or_equal_to: 20, less_than_or_equal_to: 90)
    |> validate_number(:hum_max, greater_than_or_equal_to: 20, less_than_or_equal_to: 95)
    |> validate_number(:environment_poll_interval_ms,
      greater_than_or_equal_to: 1000,
      less_than_or_equal_to: 60000
    )
    |> validate_number(:failsafe_fans_count, greater_than_or_equal_to: 1)
    |> validate_step_temps()
    |> validate_step_extra_fans()
    |> validate_active_steps()
  end

  defp validate_step_temps(changeset) do
    Enum.reduce(1..5, changeset, fn n, cs ->
      validate_number(cs, String.to_atom("step_#{n}_temp"),
        greater_than_or_equal_to: 0,
        less_than_or_equal_to: 50
      )
    end)
  end

  defp validate_step_extra_fans(changeset) do
    Enum.reduce(1..5, changeset, fn n, cs ->
      validate_number(cs, String.to_atom("step_#{n}_extra_fans"), greater_than_or_equal_to: 0)
    end)
  end

  # Validates active steps:
  # 1. Active steps must be consecutive starting from step 1 (no gaps)
  # 2. Extra fans count does not decrease as steps increase (by temperature)
  # 3. Step temperatures must be in strictly ascending order by step number
  defp validate_active_steps(changeset) do
    # Build list of active steps from the changeset
    active_steps_by_step_num =
      1..5
      |> Enum.map(fn n ->
        temp = get_field(changeset, String.to_atom("step_#{n}_temp"))
        extra_fans = get_field(changeset, String.to_atom("step_#{n}_extra_fans")) || 0
        %{step: n, temp: temp, extra_fans: extra_fans}
      end)
      |> Enum.filter(fn step -> step.temp != nil and step.temp > 0 end)

    # Sort by temperature for extra_fans count validation
    active_steps_by_temp = Enum.sort_by(active_steps_by_step_num, & &1.temp)

    changeset
    |> validate_consecutive_steps(active_steps_by_step_num)
    |> validate_extra_fans_progression(active_steps_by_temp)
    |> validate_temp_ascending(active_steps_by_step_num)
  end

  # Validate active steps are consecutive starting from step 1 (no gaps)
  defp validate_consecutive_steps(changeset, []), do: changeset

  defp validate_consecutive_steps(changeset, active_steps) do
    step_numbers = Enum.map(active_steps, & &1.step) |> Enum.sort()
    expected_steps = Enum.to_list(1..length(step_numbers))

    if step_numbers == expected_steps do
      changeset
    else
      cond do
        # First active step is not step 1
        hd(step_numbers) != 1 ->
          first_step = hd(step_numbers)

          add_error(
            changeset,
            String.to_atom("step_#{first_step}_temp"),
            "step 1 must be configured first (no skipping steps)"
          )

        # There's a gap in the sequence
        true ->
          missing_step =
            Enum.find(expected_steps, fn n -> n not in step_numbers end) ||
              length(step_numbers) + 1

          step_after_gap = Enum.find(step_numbers, fn n -> n > missing_step end)

          if step_after_gap do
            add_error(
              changeset,
              String.to_atom("step_#{step_after_gap}_temp"),
              "cannot skip step #{missing_step} - steps must be consecutive"
            )
          else
            changeset
          end
      end
    end
  end

  # Validate extra_fans count doesn't decrease between consecutive steps (by temperature order)
  defp validate_extra_fans_progression(changeset, active_steps) when length(active_steps) < 2 do
    changeset
  end

  defp validate_extra_fans_progression(changeset, active_steps) do
    active_steps
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(changeset, fn [lower, higher], cs ->
      if higher.extra_fans < lower.extra_fans do
        add_error(
          cs,
          String.to_atom("step_#{higher.step}_extra_fans"),
          "must be at least #{lower.extra_fans} (same as step #{lower.step} at #{lower.temp}C)"
        )
      else
        cs
      end
    end)
  end

  # Validate temperatures are strictly ascending (no duplicates)
  defp validate_temp_ascending(changeset, active_steps) when length(active_steps) < 2 do
    changeset
  end

  defp validate_temp_ascending(changeset, active_steps) do
    active_steps
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(changeset, fn [lower, higher], cs ->
      if higher.temp <= lower.temp do
        add_error(
          cs,
          String.to_atom("step_#{higher.step}_temp"),
          "must be greater than #{lower.temp}C (step #{lower.step})"
        )
      else
        cs
      end
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

  Returns: [%{step: 1, temp: 24.0, extra_fans: 2, pumps: ["pump_1"]}, ...]
  """
  def get_active_steps(config) do
    1..5
    |> Enum.map(fn n ->
      %{
        step: n,
        temp: Map.get(config, String.to_atom("step_#{n}_temp")),
        extra_fans: Map.get(config, String.to_atom("step_#{n}_extra_fans")) || 0,
        pumps: parse_order(Map.get(config, String.to_atom("step_#{n}_pumps")))
      }
    end)
    |> Enum.filter(fn step -> step.temp > 0 end)
    |> Enum.sort_by(& &1.temp)
  end

  @doc """
  Find the appropriate step for a given temperature.
  Returns the highest step whose temp threshold is <= current_temp.
  If current_temp is below all thresholds, returns nil.
  """
  def find_step_for_temp(config, current_temp) do
    config
    |> get_active_steps()
    |> Enum.filter(fn step -> current_temp >= step.temp end)
    |> List.last()
  end
end

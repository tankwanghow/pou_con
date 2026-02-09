defmodule PouCon.Equipment.Schemas.Equipment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "equipment" do
    field :name, :string
    field :title, :string
    field :type, :string
    field :data_point_tree, :string
    field :active, :boolean, default: true
    field :poll_interval_ms, :integer

    timestamps()
  end

  # Types that use the generic Sensor controller (any data point keys allowed)
  @generic_sensor_types ~w(temp_sensor humidity_sensor co2_sensor nh3_sensor water_meter power_meter)

  # Types with slower polling defaults
  @sensor_meter_types ~w(temp_sensor humidity_sensor co2_sensor nh3_sensor water_meter power_meter average_sensor power_indicator)

  def changeset(equipment, attrs) do
    equipment
    |> cast(attrs, [:name, :title, :type, :data_point_tree, :active, :poll_interval_ms])
    |> validate_required([:name, :type, :data_point_tree])
    |> unique_constraint(:name)
    |> validate_inclusion(
      :type,
      [
        "fan",
        "pump",
        "temp_sensor",
        "humidity_sensor",
        "co2_sensor",
        "nh3_sensor",
        "water_meter",
        "power_meter",
        "feeding",
        "egg",
        "dung",
        "dung_horz",
        "dung_exit",
        "feed_in",
        "light",
        "siren",
        "average_sensor",
        "power_indicator"
      ],
      message: "unsupported type"
    )
    |> validate_data_point_tree()
    |> set_default_poll_interval()
    |> validate_number(:poll_interval_ms,
      greater_than_or_equal_to: 100,
      less_than_or_equal_to: 60000
    )
  end

  defp set_default_poll_interval(changeset) do
    if get_field(changeset, :poll_interval_ms) == nil do
      type = get_field(changeset, :type)
      default = default_poll_interval_for_type(type)
      put_change(changeset, :poll_interval_ms, default)
    else
      changeset
    end
  end

  defp default_poll_interval_for_type(type) when type in @sensor_meter_types, do: 5000
  defp default_poll_interval_for_type(_), do: 500

  defp validate_data_point_tree(changeset) do
    type = get_field(changeset, :type)
    data_point_tree_str = get_field(changeset, :data_point_tree)

    if is_nil(data_point_tree_str) || String.trim(data_point_tree_str) == "" do
      # Skip validation if nil or empty; required check handles it
      changeset
    else
      try do
        opts = PouCon.Hardware.DataPointTreeParser.parse(data_point_tree_str)

        cond do
          # Average sensor uses lists, special validation
          type == "average_sensor" ->
            validate_average_sensor_tree(changeset, opts)

          # Generic sensor types - just need at least one data point
          type in @generic_sensor_types ->
            validate_generic_sensor_tree(changeset, opts)

          # Standard equipment with specific required keys
          true ->
            validate_standard_tree(changeset, type, opts)
        end
      rescue
        e -> add_error(changeset, :data_point_tree, "parse error: #{inspect(e)}")
      end
    end
  end

  # Average sensor requires temp_sensors list (minimum for environment control)
  # humidity_sensors is optional
  defp validate_average_sensor_tree(changeset, opts) do
    temp_sensors = Keyword.get(opts, :temp_sensors)

    cond do
      is_nil(temp_sensors) ->
        add_error(changeset, :data_point_tree, "missing required key: temp_sensors")

      not is_list(temp_sensors) ->
        add_error(
          changeset,
          :data_point_tree,
          "temp_sensors must be a comma-separated list of sensor names"
        )

      Enum.empty?(temp_sensors) ->
        add_error(changeset, :data_point_tree, "temp_sensors list cannot be empty")

      true ->
        changeset
    end
  end

  # Generic sensor/meter types - any keys allowed, just need at least one data point
  defp validate_generic_sensor_tree(changeset, opts) do
    if Enum.empty?(opts) do
      add_error(changeset, :data_point_tree, "at least one data point must be configured")
    else
      # Validate all values are non-empty strings (data point names)
      invalid =
        Enum.filter(opts, fn {_k, v} ->
          !is_binary(v) || String.trim(v) == ""
        end)

      if invalid != [] do
        keys = Enum.map(invalid, fn {k, _v} -> k end)

        add_error(
          changeset,
          :data_point_tree,
          "invalid (non-string or empty) values for keys: #{inspect(keys)}"
        )
      else
        changeset
      end
    end
  end

  defp validate_standard_tree(changeset, type, opts) do
    required = required_keys_for_type(type)
    missing = required -- Keyword.keys(opts)

    if missing != [] do
      add_error(changeset, :data_point_tree, "missing required keys: #{inspect(missing)}")
    else
      invalid =
        Enum.filter(required, fn k ->
          v = Keyword.fetch!(opts, k)
          !is_binary(v) || String.trim(v) == ""
        end)

      if invalid != [] do
        add_error(
          changeset,
          :data_point_tree,
          "invalid (non-string or empty) values for keys: #{inspect(invalid)}"
        )
      else
        changeset
      end
    end
  end

  defp required_keys_for_type("fan"), do: [:on_off_coil, :running_feedback, :auto_manual]
  defp required_keys_for_type("pump"), do: [:on_off_coil, :running_feedback, :auto_manual]

  defp required_keys_for_type("egg"),
    do: [:on_off_coil, :running_feedback, :auto_manual, :manual_switch]

  defp required_keys_for_type("light"), do: [:on_off_coil, :auto_manual]
  defp required_keys_for_type("siren"), do: [:on_off_coil, :auto_manual, :running_feedback]
  defp required_keys_for_type("dung"), do: [:on_off_coil, :running_feedback]
  defp required_keys_for_type("dung_horz"), do: [:on_off_coil, :running_feedback]
  defp required_keys_for_type("dung_exit"), do: [:on_off_coil, :running_feedback]

  defp required_keys_for_type("feeding"),
    do: [
      :to_back_limit,
      :to_front_limit,
      :fwd_feedback,
      :rev_feedback,
      :front_limit,
      :back_limit,
      :pulse_sensor,
      :auto_manual
    ]

  defp required_keys_for_type("feed_in"),
    do: [
      :filling_coil,
      :running_feedback,
      :auto_manual,
      :full_switch,
      :trip
    ]

  # Average sensor uses list values, validation handled separately
  defp required_keys_for_type("average_sensor"), do: []

  # Generic sensor/meter types - validation handled by validate_generic_sensor_tree
  defp required_keys_for_type(type) when type in @generic_sensor_types, do: []

  # Power indicator - simple digital input for status monitoring
  defp required_keys_for_type("power_indicator"), do: [:indicator]

  defp required_keys_for_type(_), do: []
end

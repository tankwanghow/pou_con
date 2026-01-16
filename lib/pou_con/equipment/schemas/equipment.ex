defmodule PouCon.Equipment.Schemas.Equipment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "equipment" do
    field :name, :string
    field :title, :string
    field :type, :string
    field :data_point_tree, :string
    field :active, :boolean, default: true

    timestamps()
  end

  def changeset(equipment, attrs) do
    equipment
    |> cast(attrs, [:name, :title, :type, :data_point_tree, :active])
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
        "flowmeter",
        "feeding",
        "egg",
        "dung",
        "dung_horz",
        "dung_exit",
        "feed_in",
        "light"
      ],
      message: "unsupported type"
    )
    |> validate_data_point_tree()
  end

  defp validate_data_point_tree(changeset) do
    type = get_field(changeset, :type)
    data_point_tree_str = get_field(changeset, :data_point_tree)

    if is_nil(data_point_tree_str) || String.trim(data_point_tree_str) == "" do
      # Skip validation if nil or empty; required check handles it
      changeset
    else
      try do
        opts = PouCon.Hardware.DataPointTreeParser.parse(data_point_tree_str)
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
      rescue
        e -> add_error(changeset, :data_point_tree, "parse error: #{inspect(e)}")
      end
    end
  end

  defp required_keys_for_type("fan"), do: [:on_off_coil, :running_feedback, :auto_manual]
  defp required_keys_for_type("pump"), do: [:on_off_coil, :running_feedback, :auto_manual]

  defp required_keys_for_type("egg"),
    do: [:on_off_coil, :running_feedback, :auto_manual, :manual_switch]

  defp required_keys_for_type("light"), do: [:on_off_coil, :running_feedback, :auto_manual]
  defp required_keys_for_type("dung"), do: [:on_off_coil, :running_feedback]
  defp required_keys_for_type("dung_horz"), do: [:on_off_coil, :running_feedback]
  defp required_keys_for_type("dung_exit"), do: [:on_off_coil, :running_feedback]

  defp required_keys_for_type("feeding"),
    do: [
      :device_to_back_limit,
      :device_to_front_limit,
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

  # Sensor types - all use :sensor key
  defp required_keys_for_type("temp_sensor"), do: [:sensor]
  defp required_keys_for_type("humidity_sensor"), do: [:sensor]
  defp required_keys_for_type("co2_sensor"), do: [:sensor]
  defp required_keys_for_type("nh3_sensor"), do: [:sensor]

  # Meter types
  defp required_keys_for_type("water_meter"), do: [:meter]
  defp required_keys_for_type("power_meter"), do: [:meter]
  defp required_keys_for_type("flowmeter"), do: [:meter]

  defp required_keys_for_type(_), do: []
end

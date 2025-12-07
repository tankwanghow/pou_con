defmodule PouCon.Devices.Equipment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "equipment" do
    field :name, :string
    field :title, :string
    field :type, :string
    field :device_tree, :string

    timestamps()
  end

  def changeset(equipment, attrs) do
    equipment
    |> cast(attrs, [:name, :title, :type, :device_tree])
    |> validate_required([:name, :type, :device_tree])
    |> unique_constraint(:name)
    |> validate_inclusion(
      :type,
      [
        "fan",
        "pump",
        "temp_sensor",
        "hum_sensor",
        "temp_hum_sensor",
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
    |> validate_device_tree()
  end

  defp validate_device_tree(changeset) do
    type = get_field(changeset, :type)
    device_tree_str = get_field(changeset, :device_tree)

    if is_nil(device_tree_str) || String.trim(device_tree_str) == "" do
      # Skip validation if nil or empty; required check handles it
      changeset
    else
      try do
        opts = PouCon.DeviceTreeParser.parse(device_tree_str)
        required = required_keys_for_type(type)
        missing = required -- Keyword.keys(opts)

        if missing != [] do
          add_error(changeset, :device_tree, "missing required keys: #{inspect(missing)}")
        else
          invalid =
            Enum.filter(required, fn k ->
              v = Keyword.fetch!(opts, k)
              !is_binary(v) || String.trim(v) == ""
            end)

          if invalid != [] do
            add_error(
              changeset,
              :device_tree,
              "invalid (non-string or empty) values for keys: #{inspect(invalid)}"
            )
          else
            changeset
          end
        end
      rescue
        e -> add_error(changeset, :device_tree, "parse error: #{inspect(e)}")
      end
    end
  end

  defp required_keys_for_type("fan"), do: [:on_off_coil, :running_feedback, :auto_manual]
  defp required_keys_for_type("pump"), do: [:on_off_coil, :running_feedback, :auto_manual]
  defp required_keys_for_type("egg"), do: [:on_off_coil, :running_feedback, :auto_manual]
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
      :full_switch
    ]

  # Define as needed
  defp required_keys_for_type("temp_hum_sensor"), do: [:sensor]
  defp required_keys_for_type(_), do: []
end

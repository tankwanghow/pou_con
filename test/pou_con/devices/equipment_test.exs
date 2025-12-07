defmodule PouCon.Equipment.Devices.EquipmentTest do
  use PouCon.DataCase, async: true

  alias PouCon.Equipment.Schemas.Equipment

  describe "changeset/2" do
    test "valid changeset for fan type" do
      changeset =
        %Equipment{}
        |> Equipment.changeset(%{
          name: "fan1",
          title: "Exhaust Fan 1",
          type: "fan",
          device_tree: "on_off_coil: coil1\nrunning_feedback: fb1\nauto_manual: am1"
        })

      assert changeset.valid?
    end

    test "valid changeset for pump type" do
      changeset =
        %Equipment{}
        |> Equipment.changeset(%{
          name: "pump1",
          type: "pump",
          device_tree: "on_off_coil: p_coil\nrunning_feedback: p_fb\nauto_manual: p_am"
        })

      assert changeset.valid?
    end

    test "valid changeset for temp_hum_sensor type" do
      changeset =
        %Equipment{}
        |> Equipment.changeset(%{
          name: "temp_sensor1",
          type: "temp_hum_sensor",
          device_tree: "sensor: temp1"
        })

      assert changeset.valid?
    end

    test "requires name field" do
      changeset =
        %Equipment{}
        |> Equipment.changeset(%{
          type: "fan",
          device_tree: "on_off_coil: c\nrunning_feedback: f\nauto_manual: a"
        })

      refute changeset.valid?
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires type field" do
      changeset =
        %Equipment{}
        |> Equipment.changeset(%{name: "test", device_tree: "key: value"})

      refute changeset.valid?
      assert %{type: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires device_tree field" do
      changeset =
        %Equipment{}
        |> Equipment.changeset(%{name: "test", type: "fan"})

      refute changeset.valid?
      assert %{device_tree: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates type is in allowed list" do
      changeset =
        %Equipment{}
        |> Equipment.changeset(%{
          name: "bad_type",
          type: "invalid_type",
          device_tree: "key: value"
        })

      refute changeset.valid?
      assert %{type: ["unsupported type"]} = errors_on(changeset)
    end

    test "validates all allowed equipment types" do
      allowed_types = [
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
      ]

      for type <- allowed_types do
        device_tree =
          case type do
            t when t in ["fan", "pump", "egg", "light"] ->
              "on_off_coil: c\nrunning_feedback: f\nauto_manual: a"

            t when t in ["dung", "dung_horz", "dung_exit"] ->
              "on_off_coil: c\nrunning_feedback: f"

            "feeding" ->
              "device_to_back_limit: d1\ndevice_to_front_limit: d2\nfront_limit: f\nback_limit: b\npulse_sensor: p\nauto_manual: a"

            "feed_in" ->
              "filling_coil: fc\nrunning_feedback: rf\nposition_1: p1\nposition_2: p2\nposition_3: p3\nposition_4: p4\nauto_manual: am\nfull_switch: fs"

            _ ->
              "sensor: s1"
          end

        changeset =
          %Equipment{}
          |> Equipment.changeset(%{name: "test_#{type}", type: type, device_tree: device_tree})

        assert changeset.valid?, "Type #{type} should be valid"
      end
    end

    test "validates required keys for fan type" do
      # Missing auto_manual
      changeset =
        %Equipment{}
        |> Equipment.changeset(%{
          name: "bad_fan",
          type: "fan",
          device_tree: "on_off_coil: coil1\nrunning_feedback: fb1"
        })

      refute changeset.valid?
      assert changeset.errors[:device_tree] != nil
    end

    test "validates required keys for feeding type" do
      # Missing pulse_sensor
      changeset =
        %Equipment{}
        |> Equipment.changeset(%{
          name: "bad_feeding",
          type: "feeding",
          device_tree:
            "device_to_back_limit: d1\ndevice_to_front_limit: d2\nfront_limit: f\nback_limit: b\nauto_manual: a"
        })

      refute changeset.valid?
      assert changeset.errors[:device_tree] != nil
    end

    test "validates empty values are not allowed" do
      changeset =
        %Equipment{}
        |> Equipment.changeset(%{
          name: "empty_value",
          type: "fan",
          device_tree: "on_off_coil: \nrunning_feedback: fb\nauto_manual: am"
        })

      refute changeset.valid?
      assert changeset.errors[:device_tree] != nil
    end

    test "validates device_tree parsing errors" do
      changeset =
        %Equipment{}
        |> Equipment.changeset(%{
          name: "bad_parse",
          type: "fan",
          device_tree: "invalid format without colon"
        })

      refute changeset.valid?
      assert changeset.errors[:device_tree] != nil
    end

    test "validates unique name constraint" do
      # Insert first equipment
      %Equipment{}
      |> Equipment.changeset(%{
        name: "unique_equip",
        type: "fan",
        device_tree: "on_off_coil: c\nrunning_feedback: f\nauto_manual: a"
      })
      |> Repo.insert!()

      # Try to insert duplicate name
      changeset =
        %Equipment{}
        |> Equipment.changeset(%{
          name: "unique_equip",
          type: "pump",
          device_tree: "on_off_coil: c2\nrunning_feedback: f2\nauto_manual: a2"
        })

      assert {:error, changeset} = Repo.insert(changeset)
      assert %{name: ["has already been taken"]} = errors_on(changeset)
    end

    test "allows title to be optional" do
      changeset =
        %Equipment{}
        |> Equipment.changeset(%{
          name: "no_title",
          type: "fan",
          device_tree: "on_off_coil: c\nrunning_feedback: f\nauto_manual: a"
        })

      assert changeset.valid?
      assert get_change(changeset, :title) == nil
    end
  end
end

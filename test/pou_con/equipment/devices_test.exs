defmodule PouCon.DevicesTest do
  use PouCon.DataCase, async: false

  alias PouCon.Equipment.Devices
  alias PouCon.Equipment.Schemas.Equipment

  # Note: Device tests were removed since Device schema was replaced by DataPoint.
  # DataPoint tests are in data_points_test.exs

  describe "equipment" do
    test "list_equipment/1 returns all equipment" do
      {:ok, equip1} =
        Devices.create_equipment(%{
          name: "equip1",
          type: "fan",
          data_point_tree: "on_off_coil: coil1\nrunning_feedback: fb1\nauto_manual: am1"
        })

      {:ok, equip2} =
        Devices.create_equipment(%{
          name: "equip2",
          type: "pump",
          data_point_tree: "on_off_coil: coil2\nrunning_feedback: fb2\nauto_manual: am2"
        })

      equipment = Devices.list_equipment()
      assert length(equipment) == 2
      assert Enum.any?(equipment, &(&1.id == equip1.id))
      assert Enum.any?(equipment, &(&1.id == equip2.id))
    end

    test "list_equipment/1 with sort options" do
      {:ok, _} =
        Devices.create_equipment(%{
          name: "z_equip",
          type: "fan",
          data_point_tree: "on_off_coil: c1\nrunning_feedback: f1\nauto_manual: a1"
        })

      {:ok, _} =
        Devices.create_equipment(%{
          name: "a_equip",
          type: "pump",
          data_point_tree: "on_off_coil: c2\nrunning_feedback: f2\nauto_manual: a2"
        })

      equipment = Devices.list_equipment(sort_field: :name, sort_order: :asc)
      assert List.first(equipment).name == "a_equip"
      assert List.last(equipment).name == "z_equip"
    end

    test "get_equipment!/1 returns the equipment with given id" do
      {:ok, equip} =
        Devices.create_equipment(%{
          name: "test",
          type: "fan",
          data_point_tree: "on_off_coil: coil\nrunning_feedback: fb\nauto_manual: am"
        })

      assert Devices.get_equipment!(equip.id).id == equip.id
    end

    test "get_equipment!/1 raises when equipment not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Devices.get_equipment!(999_999)
      end
    end

    test "create_equipment/1 with valid data creates equipment" do
      attrs = %{
        name: "test_fan",
        title: "Test Fan",
        type: "fan",
        data_point_tree: "on_off_coil: coil1\nrunning_feedback: fb1\nauto_manual: am1"
      }

      assert {:ok, %Equipment{} = equip} = Devices.create_equipment(attrs)
      assert equip.name == "test_fan"
      assert equip.type == "fan"
    end

    test "create_equipment/1 validates required data_point_tree keys for fan type" do
      # Missing auto_manual
      attrs = %{
        name: "bad_fan",
        type: "fan",
        data_point_tree: "on_off_coil: coil1\nrunning_feedback: fb1"
      }

      assert {:error, changeset} = Devices.create_equipment(attrs)
      assert changeset.errors[:data_point_tree] != nil
    end

    test "create_equipment/1 validates type is in allowed list" do
      attrs = %{name: "bad_type", type: "invalid_type", data_point_tree: "key: value"}
      assert {:error, changeset} = Devices.create_equipment(attrs)
      assert %{type: ["unsupported type"]} = errors_on(changeset)
    end

    test "create_equipment/1 enforces unique name constraint" do
      attrs = %{
        name: "unique_equip",
        type: "fan",
        data_point_tree: "on_off_coil: c\nrunning_feedback: f\nauto_manual: a"
      }

      {:ok, _} = Devices.create_equipment(attrs)
      assert {:error, changeset} = Devices.create_equipment(attrs)
      assert %{name: ["has already been taken"]} = errors_on(changeset)
    end

    test "update_equipment/2 with valid data updates the equipment" do
      {:ok, equip} =
        Devices.create_equipment(%{
          name: "original",
          type: "fan",
          data_point_tree: "on_off_coil: c\nrunning_feedback: f\nauto_manual: a"
        })

      assert {:ok, %Equipment{} = updated} =
               Devices.update_equipment(equip, %{title: "Updated Title"})

      assert updated.title == "Updated Title"
    end

    test "update_equipment/2 with invalid data returns error changeset" do
      {:ok, equip} =
        Devices.create_equipment(%{
          name: "test",
          type: "fan",
          data_point_tree: "on_off_coil: c\nrunning_feedback: f\nauto_manual: a"
        })

      assert {:error, %Ecto.Changeset{}} = Devices.update_equipment(equip, %{name: nil})
    end

    test "delete_equipment/1 deletes the equipment" do
      {:ok, equip} =
        Devices.create_equipment(%{
          name: "to_delete",
          type: "fan",
          data_point_tree: "on_off_coil: c\nrunning_feedback: f\nauto_manual: a"
        })

      assert {:ok, %Equipment{}} = Devices.delete_equipment(equip)
      assert_raise Ecto.NoResultsError, fn -> Devices.get_equipment!(equip.id) end
    end

    test "change_equipment/2 returns an equipment changeset" do
      {:ok, equip} =
        Devices.create_equipment(%{
          name: "test",
          type: "fan",
          data_point_tree: "on_off_coil: c\nrunning_feedback: f\nauto_manual: a"
        })

      assert %Ecto.Changeset{} = Devices.change_equipment(equip)
    end
  end
end

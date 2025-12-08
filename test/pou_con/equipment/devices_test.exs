defmodule PouCon.DevicesTest do
  use PouCon.DataCase, async: false

  alias PouCon.Equipment.Devices
  alias PouCon.Equipment.Schemas.{Device, Equipment}
  alias PouCon.Hardware.Ports.Ports

  describe "devices" do
    setup do
      # Create a port for devices to reference
      {:ok, port} = Ports.create_port(%{device_path: "test_port"})
      %{port: port}
    end

    test "list_devices/1 returns all devices", %{port: port} do
      {:ok, device1} =
        Devices.create_device(%{
          name: "device1",
          type: "sensor",
          slave_id: 1,
          port_device_path: port.device_path
        })

      {:ok, device2} =
        Devices.create_device(%{
          name: "device2",
          type: "actuator",
          slave_id: 2,
          port_device_path: port.device_path
        })

      devices = Devices.list_devices()
      assert length(devices) == 2
      assert Enum.any?(devices, &(&1.id == device1.id))
      assert Enum.any?(devices, &(&1.id == device2.id))
    end

    test "list_devices/1 with sort options", %{port: port} do
      {:ok, _} =
        Devices.create_device(%{
          name: "b_device",
          type: "sensor",
          slave_id: 1,
          port_device_path: port.device_path
        })

      {:ok, _} =
        Devices.create_device(%{
          name: "a_device",
          type: "actuator",
          slave_id: 2,
          port_device_path: port.device_path
        })

      devices = Devices.list_devices(sort_field: :name, sort_order: :asc)
      assert List.first(devices).name == "a_device"
      assert List.last(devices).name == "b_device"
    end

    test "get_device!/1 returns the device with given id", %{port: port} do
      {:ok, device} =
        Devices.create_device(%{
          name: "test",
          type: "sensor",
          slave_id: 1,
          port_device_path: port.device_path
        })

      assert Devices.get_device!(device.id).id == device.id
    end

    test "get_device!/1 raises when device not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Devices.get_device!(999_999)
      end
    end

    test "create_device/1 with valid data creates a device", %{port: port} do
      attrs = %{
        name: "new_device",
        type: "sensor",
        slave_id: 10,
        register: 100,
        channel: 1,
        description: "Test device",
        port_device_path: port.device_path
      }

      assert {:ok, %Device{} = device} = Devices.create_device(attrs)
      assert device.name == "new_device"
      assert device.type == "sensor"
      assert device.slave_id == 10
    end

    test "create_device/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Devices.create_device(%{})
    end

    test "create_device/1 enforces unique name constraint", %{port: port} do
      attrs = %{name: "unique", type: "sensor", slave_id: 1, port_device_path: port.device_path}
      {:ok, _} = Devices.create_device(attrs)
      assert {:error, changeset} = Devices.create_device(attrs)
      assert %{name: ["has already been taken"]} = errors_on(changeset)
    end

    test "update_device/2 with valid data updates the device", %{port: port} do
      {:ok, device} =
        Devices.create_device(%{
          name: "original",
          type: "sensor",
          slave_id: 1,
          port_device_path: port.device_path
        })

      assert {:ok, %Device{} = updated} =
               Devices.update_device(device, %{description: "Updated description"})

      assert updated.description == "Updated description"
    end

    test "update_device/2 with invalid data returns error changeset", %{port: port} do
      {:ok, device} =
        Devices.create_device(%{
          name: "test",
          type: "sensor",
          slave_id: 1,
          port_device_path: port.device_path
        })

      assert {:error, %Ecto.Changeset{}} = Devices.update_device(device, %{name: nil})
    end

    test "delete_device/1 deletes the device", %{port: port} do
      {:ok, device} =
        Devices.create_device(%{
          name: "to_delete",
          type: "sensor",
          slave_id: 1,
          port_device_path: port.device_path
        })

      assert {:ok, %Device{}} = Devices.delete_device(device)
      assert_raise Ecto.NoResultsError, fn -> Devices.get_device!(device.id) end
    end

    test "change_device/2 returns a device changeset", %{port: port} do
      {:ok, device} =
        Devices.create_device(%{
          name: "test",
          type: "sensor",
          slave_id: 1,
          port_device_path: port.device_path
        })

      assert %Ecto.Changeset{} = Devices.change_device(device)
    end
  end

  describe "equipment" do
    test "list_equipment/1 returns all equipment" do
      {:ok, equip1} =
        Devices.create_equipment(%{
          name: "equip1",
          type: "fan",
          device_tree: "on_off_coil: coil1\nrunning_feedback: fb1\nauto_manual: am1"
        })

      {:ok, equip2} =
        Devices.create_equipment(%{
          name: "equip2",
          type: "pump",
          device_tree: "on_off_coil: coil2\nrunning_feedback: fb2\nauto_manual: am2"
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
          device_tree: "on_off_coil: c1\nrunning_feedback: f1\nauto_manual: a1"
        })

      {:ok, _} =
        Devices.create_equipment(%{
          name: "a_equip",
          type: "pump",
          device_tree: "on_off_coil: c2\nrunning_feedback: f2\nauto_manual: a2"
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
          device_tree: "on_off_coil: coil\nrunning_feedback: fb\nauto_manual: am"
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
        device_tree: "on_off_coil: coil1\nrunning_feedback: fb1\nauto_manual: am1"
      }

      assert {:ok, %Equipment{} = equip} = Devices.create_equipment(attrs)
      assert equip.name == "test_fan"
      assert equip.type == "fan"
    end

    test "create_equipment/1 validates required device_tree keys for fan type" do
      # Missing auto_manual
      attrs = %{
        name: "bad_fan",
        type: "fan",
        device_tree: "on_off_coil: coil1\nrunning_feedback: fb1"
      }

      assert {:error, changeset} = Devices.create_equipment(attrs)
      assert changeset.errors[:device_tree] != nil
    end

    test "create_equipment/1 validates type is in allowed list" do
      attrs = %{name: "bad_type", type: "invalid_type", device_tree: "key: value"}
      assert {:error, changeset} = Devices.create_equipment(attrs)
      assert %{type: ["unsupported type"]} = errors_on(changeset)
    end

    test "create_equipment/1 enforces unique name constraint" do
      attrs = %{
        name: "unique_equip",
        type: "fan",
        device_tree: "on_off_coil: c\nrunning_feedback: f\nauto_manual: a"
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
          device_tree: "on_off_coil: c\nrunning_feedback: f\nauto_manual: a"
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
          device_tree: "on_off_coil: c\nrunning_feedback: f\nauto_manual: a"
        })

      assert {:error, %Ecto.Changeset{}} = Devices.update_equipment(equip, %{name: nil})
    end

    test "delete_equipment/1 deletes the equipment" do
      {:ok, equip} =
        Devices.create_equipment(%{
          name: "to_delete",
          type: "fan",
          device_tree: "on_off_coil: c\nrunning_feedback: f\nauto_manual: a"
        })

      assert {:ok, %Equipment{}} = Devices.delete_equipment(equip)
      assert_raise Ecto.NoResultsError, fn -> Devices.get_equipment!(equip.id) end
    end

    test "change_equipment/2 returns an equipment changeset" do
      {:ok, equip} =
        Devices.create_equipment(%{
          name: "test",
          type: "fan",
          device_tree: "on_off_coil: c\nrunning_feedback: f\nauto_manual: a"
        })

      assert %Ecto.Changeset{} = Devices.change_equipment(equip)
    end
  end
end

defmodule PouCon.Equipment.Schemas.DeviceTest do
  use PouCon.DataCase, async: true

  alias PouCon.Equipment.Schemas.Device
  alias PouCon.Hardware.Ports.Ports

  describe "changeset/2" do
    setup do
      # Create a port for devices to reference
      {:ok, port} = Ports.create_port(%{device_path: "test_port"})
      %{port: port}
    end

    test "valid changeset with required fields", %{port: port} do
      changeset =
        %Device{}
        |> Device.changeset(%{
          name: "test_device",
          type: "sensor",
          slave_id: 1,
          port_device_path: port.device_path
        })

      assert changeset.valid?
    end

    test "valid changeset with all fields", %{port: port} do
      changeset =
        %Device{}
        |> Device.changeset(%{
          name: "full_device",
          type: "actuator",
          slave_id: 5,
          register: 100,
          channel: 3,
          read_fn: "read_digital_input",
          write_fn: "write_digital_output",
          description: "Test device",
          port_device_path: port.device_path
        })

      assert changeset.valid?
    end

    test "requires name field" do
      changeset =
        %Device{}
        |> Device.changeset(%{type: "sensor", slave_id: 1, port_device_path: "test"})

      refute changeset.valid?
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires type field" do
      changeset =
        %Device{}
        |> Device.changeset(%{name: "test", slave_id: 1, port_device_path: "test"})

      refute changeset.valid?
      assert %{type: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires slave_id field" do
      changeset =
        %Device{}
        |> Device.changeset(%{name: "test", type: "sensor", port_device_path: "test"})

      refute changeset.valid?
      assert %{slave_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires port_device_path field" do
      changeset =
        %Device{}
        |> Device.changeset(%{name: "test", type: "sensor", slave_id: 1})

      refute changeset.valid?
      assert %{port_device_path: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates unique name constraint", %{port: port} do
      # Insert first device
      %Device{}
      |> Device.changeset(%{
        name: "unique_device",
        type: "sensor",
        slave_id: 1,
        port_device_path: port.device_path
      })
      |> Repo.insert!()

      # Try to insert duplicate name
      changeset =
        %Device{}
        |> Device.changeset(%{
          name: "unique_device",
          type: "actuator",
          slave_id: 2,
          port_device_path: port.device_path
        })

      assert {:error, changeset} = Repo.insert(changeset)
      assert %{name: ["has already been taken"]} = errors_on(changeset)
    end

    test "allows optional fields to be nil", %{port: port} do
      changeset =
        %Device{}
        |> Device.changeset(%{
          name: "minimal",
          type: "sensor",
          slave_id: 1,
          port_device_path: port.device_path
        })

      assert changeset.valid?
      assert get_change(changeset, :register) == nil
      assert get_change(changeset, :channel) == nil
      assert get_change(changeset, :read_fn) == nil
      assert get_change(changeset, :write_fn) == nil
      assert get_change(changeset, :description) == nil
    end
  end
end

defmodule PouCon.PortsTest do
  use PouCon.DataCase, async: false

  alias PouCon.Hardware.Ports.Ports
  alias PouCon.Hardware.Ports.Port

  describe "ports" do
    test "list_ports/0 returns all ports" do
      {:ok, port1} = Ports.create_port(%{device_path: "/dev/ttyUSB0"})
      {:ok, port2} = Ports.create_port(%{device_path: "/dev/ttyUSB1"})

      ports = Ports.list_ports()
      assert length(ports) == 2
      assert Enum.any?(ports, &(&1.id == port1.id))
      assert Enum.any?(ports, &(&1.id == port2.id))
    end

    test "get_port!/1 returns the port with given id" do
      {:ok, port} = Ports.create_port(%{device_path: "/dev/ttyUSB0"})
      assert Ports.get_port!(port.id).id == port.id
    end

    test "get_port!/1 raises when port not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Ports.get_port!(999_999)
      end
    end

    test "create_port/1 with valid data creates a port" do
      attrs = %{
        device_path: "/dev/ttyUSB0",
        speed: 9600,
        parity: "none",
        data_bits: 8,
        stop_bits: 1,
        description: "Test port"
      }

      assert {:ok, %Port{} = port} = Ports.create_port(attrs)
      assert port.device_path == "/dev/ttyUSB0"
      assert port.speed == 9600
      assert port.parity == "none"
      assert port.data_bits == 8
      assert port.stop_bits == 1
      assert port.description == "Test port"
    end

    test "create_port/1 with minimal valid data creates a port" do
      attrs = %{device_path: "/dev/ttyUSB2"}

      assert {:ok, %Port{} = port} = Ports.create_port(attrs)
      assert port.device_path == "/dev/ttyUSB2"
      assert port.speed == nil
      assert port.parity == nil
    end

    test "create_port/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Ports.create_port(%{})
    end

    test "create_port/1 enforces unique device_path constraint" do
      attrs = %{device_path: "/dev/ttyUSB0"}
      {:ok, _} = Ports.create_port(attrs)
      assert {:error, changeset} = Ports.create_port(attrs)
      assert %{device_path: ["has already been taken"]} = errors_on(changeset)
    end

    test "update_port/2 with valid data updates the port" do
      {:ok, port} = Ports.create_port(%{device_path: "/dev/ttyUSB0"})

      assert {:ok, %Port{} = updated} =
               Ports.update_port(port, %{
                 speed: 19200,
                 description: "Updated description"
               })

      assert updated.speed == 19200
      assert updated.description == "Updated description"
    end

    test "update_port/2 with invalid data returns error changeset" do
      {:ok, port} = Ports.create_port(%{device_path: "/dev/ttyUSB0"})
      assert {:error, %Ecto.Changeset{}} = Ports.update_port(port, %{device_path: nil})
    end

    test "delete_port/1 deletes the port" do
      {:ok, port} = Ports.create_port(%{device_path: "/dev/ttyUSB0"})
      assert {:ok, %Port{}} = Ports.delete_port(port)
      assert_raise Ecto.NoResultsError, fn -> Ports.get_port!(port.id) end
    end

    test "change_port/2 returns a port changeset" do
      {:ok, port} = Ports.create_port(%{device_path: "/dev/ttyUSB0"})
      assert %Ecto.Changeset{} = Ports.change_port(port)
    end

    test "change_port/2 with attributes returns a changeset with changes" do
      {:ok, port} = Ports.create_port(%{device_path: "/dev/ttyUSB0"})
      changeset = Ports.change_port(port, %{speed: 115_200})
      assert changeset.changes.speed == 115_200
    end
  end
end

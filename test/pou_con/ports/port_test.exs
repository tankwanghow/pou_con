defmodule PouCon.Ports.PortTest do
  use PouCon.DataCase, async: true

  alias PouCon.Ports.Port

  describe "changeset/2" do
    test "valid changeset with required field only" do
      changeset =
        %Port{}
        |> Port.changeset(%{device_path: "/dev/ttyUSB0"})

      assert changeset.valid?
    end

    test "valid changeset with all fields" do
      changeset =
        %Port{}
        |> Port.changeset(%{
          device_path: "/dev/ttyUSB0",
          speed: 9600,
          parity: "none",
          data_bits: 8,
          stop_bits: 1,
          description: "Test port"
        })

      assert changeset.valid?
    end

    test "requires device_path field" do
      changeset = Port.changeset(%Port{}, %{})

      refute changeset.valid?
      assert %{device_path: ["can't be blank"]} = errors_on(changeset)
    end

    test "allows optional fields to be nil" do
      changeset =
        %Port{}
        |> Port.changeset(%{device_path: "/dev/ttyUSB1"})

      assert changeset.valid?
      assert get_change(changeset, :speed) == nil
      assert get_change(changeset, :parity) == nil
      assert get_change(changeset, :data_bits) == nil
      assert get_change(changeset, :stop_bits) == nil
      assert get_change(changeset, :description) == nil
    end

    test "accepts common serial port speeds" do
      speeds = [9600, 19200, 38400, 57600, 115_200]

      for speed <- speeds do
        changeset =
          %Port{}
          |> Port.changeset(%{device_path: "/dev/ttyUSB0", speed: speed})

        assert changeset.valid?, "Speed #{speed} should be valid"
      end
    end

    test "accepts common parity values" do
      parities = ["none", "even", "odd"]

      for parity <- parities do
        changeset =
          %Port{}
          |> Port.changeset(%{device_path: "/dev/ttyUSB0", parity: parity})

        assert changeset.valid?, "Parity #{parity} should be valid"
      end
    end

    test "accepts common data_bits values" do
      data_bits_values = [7, 8]

      for bits <- data_bits_values do
        changeset =
          %Port{}
          |> Port.changeset(%{device_path: "/dev/ttyUSB0", data_bits: bits})

        assert changeset.valid?, "Data bits #{bits} should be valid"
      end
    end

    test "accepts common stop_bits values" do
      stop_bits_values = [1, 2]

      for bits <- stop_bits_values do
        changeset =
          %Port{}
          |> Port.changeset(%{device_path: "/dev/ttyUSB0", stop_bits: bits})

        assert changeset.valid?, "Stop bits #{bits} should be valid"
      end
    end

    test "validates unique device_path constraint" do
      # Insert first port
      %Port{}
      |> Port.changeset(%{device_path: "/dev/ttyUSB0"})
      |> Repo.insert!()

      # Try to insert duplicate device_path
      changeset =
        %Port{}
        |> Port.changeset(%{device_path: "/dev/ttyUSB0"})

      assert {:error, changeset} = Repo.insert(changeset)
      assert %{device_path: ["has already been taken"]} = errors_on(changeset)
    end

    test "accepts virtual port path" do
      changeset =
        %Port{}
        |> Port.changeset(%{device_path: "virtual"})

      assert changeset.valid?
    end
  end
end

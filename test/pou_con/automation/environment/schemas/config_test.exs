defmodule PouCon.Automation.Environment.Schemas.ConfigTest do
  use PouCon.DataCase, async: false

  alias PouCon.Automation.Environment.Schemas.Config

  describe "changeset/2" do
    test "valid changeset with all required fields" do
      changeset =
        %Config{}
        |> Config.changeset(%{
          temp_min: 25.0,
          temp_max: 32.0,
          hum_min: 50.0,
          hum_max: 80.0
        })

      assert changeset.valid?
    end

    test "valid changeset with defaults" do
      changeset = %Config{} |> Config.changeset(%{})
      assert changeset.valid?
      assert get_field(changeset, :temp_min) == 25.0
      assert get_field(changeset, :temp_max) == 32.0
      assert get_field(changeset, :hum_min) == 50.0
      assert get_field(changeset, :hum_max) == 80.0
      assert get_field(changeset, :min_fans) == 1
      assert get_field(changeset, :max_fans) == 4
      assert get_field(changeset, :min_pumps) == 0
      assert get_field(changeset, :max_pumps) == 2
      assert get_field(changeset, :enabled) == false
    end

    test "requires temp_min" do
      changeset =
        %Config{}
        |> Config.changeset(%{temp_min: nil, temp_max: 32.0, hum_min: 50.0, hum_max: 80.0})

      refute changeset.valid?
      assert %{temp_min: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires temp_max" do
      changeset =
        %Config{}
        |> Config.changeset(%{temp_min: 25.0, temp_max: nil, hum_min: 50.0, hum_max: 80.0})

      refute changeset.valid?
      assert %{temp_max: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires hum_min" do
      changeset =
        %Config{}
        |> Config.changeset(%{temp_min: 25.0, temp_max: 32.0, hum_min: nil, hum_max: 80.0})

      refute changeset.valid?
      assert %{hum_min: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires hum_max" do
      changeset =
        %Config{}
        |> Config.changeset(%{temp_min: 25.0, temp_max: 32.0, hum_min: 50.0, hum_max: nil})

      refute changeset.valid?
      assert %{hum_max: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates temp_min range" do
      changeset = %Config{} |> Config.changeset(%{temp_min: -1.0})
      refute changeset.valid?
      assert %{temp_min: ["must be greater than or equal to 0"]} = errors_on(changeset)

      changeset = %Config{} |> Config.changeset(%{temp_min: 51.0})
      refute changeset.valid?
      assert %{temp_min: ["must be less than or equal to 50"]} = errors_on(changeset)
    end

    test "validates temp_max range" do
      changeset = %Config{} |> Config.changeset(%{temp_max: -1.0})
      refute changeset.valid?
      assert %{temp_max: ["must be greater than or equal to 0"]} = errors_on(changeset)

      changeset = %Config{} |> Config.changeset(%{temp_max: 51.0})
      refute changeset.valid?
      assert %{temp_max: ["must be less than or equal to 50"]} = errors_on(changeset)
    end

    test "validates hum_min range" do
      changeset = %Config{} |> Config.changeset(%{hum_min: -1.0})
      refute changeset.valid?
      assert %{hum_min: ["must be greater than or equal to 0"]} = errors_on(changeset)

      changeset = %Config{} |> Config.changeset(%{hum_min: 101.0})
      refute changeset.valid?
      assert %{hum_min: ["must be less than or equal to 100"]} = errors_on(changeset)
    end

    test "validates hum_max range" do
      changeset = %Config{} |> Config.changeset(%{hum_max: -1.0})
      refute changeset.valid?
      assert %{hum_max: ["must be greater than or equal to 0"]} = errors_on(changeset)

      changeset = %Config{} |> Config.changeset(%{hum_max: 101.0})
      refute changeset.valid?
      assert %{hum_max: ["must be less than or equal to 100"]} = errors_on(changeset)
    end

    test "validates min_fans is non-negative" do
      changeset = %Config{} |> Config.changeset(%{min_fans: -1})
      refute changeset.valid?
      assert %{min_fans: ["must be greater than or equal to 0"]} = errors_on(changeset)
    end

    test "validates max_fans is non-negative" do
      changeset = %Config{} |> Config.changeset(%{max_fans: -1})
      refute changeset.valid?
      assert %{max_fans: ["must be greater than or equal to 0"]} = errors_on(changeset)
    end

    test "validates min_pumps is non-negative" do
      changeset = %Config{} |> Config.changeset(%{min_pumps: -1})
      refute changeset.valid?
      assert %{min_pumps: ["must be greater than or equal to 0"]} = errors_on(changeset)
    end

    test "validates max_pumps is non-negative" do
      changeset = %Config{} |> Config.changeset(%{max_pumps: -1})
      refute changeset.valid?
      assert %{max_pumps: ["must be greater than or equal to 0"]} = errors_on(changeset)
    end

    test "validates hysteresis is non-negative" do
      changeset = %Config{} |> Config.changeset(%{hysteresis: -1.0})
      refute changeset.valid?
      assert %{hysteresis: ["must be greater than or equal to 0"]} = errors_on(changeset)
    end

    test "accepts valid fan_order string" do
      changeset = %Config{} |> Config.changeset(%{fan_order: "fan1,fan2,fan3"})
      assert changeset.valid?
    end

    test "accepts valid pump_order string" do
      changeset = %Config{} |> Config.changeset(%{pump_order: "pump1,pump2"})
      assert changeset.valid?
    end

    test "accepts valid nc_fans string" do
      changeset = %Config{} |> Config.changeset(%{nc_fans: "fan1,fan3"})
      assert changeset.valid?
    end
  end

  describe "parse_order/1" do
    test "parses comma-separated string into list" do
      assert Config.parse_order("fan1,fan2,fan3") == ["fan1", "fan2", "fan3"]
    end

    test "trims whitespace from items" do
      assert Config.parse_order("fan1, fan2 , fan3") == ["fan1", "fan2", "fan3"]
    end

    test "handles empty string" do
      assert Config.parse_order("") == []
    end

    test "handles nil" do
      assert Config.parse_order(nil) == []
    end

    test "rejects empty items after split" do
      assert Config.parse_order("fan1,,fan2,") == ["fan1", "fan2"]
    end

    test "handles single item" do
      assert Config.parse_order("fan1") == ["fan1"]
    end

    test "handles items with spaces" do
      assert Config.parse_order("fan 1, fan 2") == ["fan 1", "fan 2"]
    end
  end
end

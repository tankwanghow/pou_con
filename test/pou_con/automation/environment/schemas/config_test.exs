defmodule PouCon.Automation.Environment.Schemas.ConfigTest do
  use PouCon.DataCase, async: false

  alias PouCon.Automation.Environment.Schemas.Config

  describe "changeset/2" do
    test "valid changeset with defaults" do
      changeset = %Config{} |> Config.changeset(%{})
      assert changeset.valid?
      assert get_field(changeset, :hum_min) == 40.0
      assert get_field(changeset, :hum_max) == 80.0
      assert get_field(changeset, :stagger_delay_seconds) == 5
      assert get_field(changeset, :delay_between_step_seconds) == 120
      assert get_field(changeset, :enabled) == false
    end

    test "valid changeset with step configuration" do
      changeset =
        %Config{}
        |> Config.changeset(%{
          step_1_temp: 25.0,
          step_1_fans: "fan_1, fan_2",
          step_1_pumps: "pump_1"
        })

      assert changeset.valid?
    end

    test "validates hum_min range" do
      # Below minimum
      changeset = %Config{} |> Config.changeset(%{hum_min: 15.0})
      refute changeset.valid?
      assert %{hum_min: ["must be greater than or equal to 20"]} = errors_on(changeset)

      # Above maximum
      changeset = %Config{} |> Config.changeset(%{hum_min: 95.0})
      refute changeset.valid?
      assert %{hum_min: ["must be less than or equal to 90"]} = errors_on(changeset)
    end

    test "validates hum_max range" do
      # Below minimum
      changeset = %Config{} |> Config.changeset(%{hum_max: 15.0})
      refute changeset.valid?
      assert %{hum_max: ["must be greater than or equal to 20"]} = errors_on(changeset)

      # Above maximum
      changeset = %Config{} |> Config.changeset(%{hum_max: 100.0})
      refute changeset.valid?
      assert %{hum_max: ["must be less than or equal to 95"]} = errors_on(changeset)
    end

    test "validates stagger_delay_seconds minimum" do
      changeset = %Config{} |> Config.changeset(%{stagger_delay_seconds: 1})
      refute changeset.valid?

      assert %{stagger_delay_seconds: ["must be greater than or equal to 2"]} =
               errors_on(changeset)
    end

    test "validates delay_between_step_seconds minimum" do
      changeset = %Config{} |> Config.changeset(%{delay_between_step_seconds: 10})
      refute changeset.valid?

      assert %{delay_between_step_seconds: ["must be greater than or equal to 30"]} =
               errors_on(changeset)
    end

    test "validates step temperature ranges" do
      # Below minimum
      changeset = %Config{} |> Config.changeset(%{step_1_temp: -5.0})
      refute changeset.valid?
      assert %{step_1_temp: ["must be greater than or equal to 0"]} = errors_on(changeset)

      # Above maximum
      changeset = %Config{} |> Config.changeset(%{step_1_temp: 55.0})
      refute changeset.valid?
      assert %{step_1_temp: ["must be less than or equal to 50"]} = errors_on(changeset)
    end

    test "accepts valid step configuration" do
      # Disable default steps and only configure two valid steps
      changeset =
        %Config{}
        |> Config.changeset(%{
          step_1_temp: 24.0,
          step_1_fans: "fan_1",
          step_1_pumps: "",
          step_2_temp: 28.0,
          step_2_fans: "fan_1, fan_2",
          step_2_pumps: "pump_1",
          step_3_temp: 0.0,
          step_4_temp: 0.0,
          step_5_temp: 0.0,
          step_6_temp: 0.0,
          step_7_temp: 0.0,
          step_8_temp: 0.0,
          step_9_temp: 0.0,
          step_10_temp: 0.0
        })

      assert changeset.valid?
    end

    test "rejects active step with no fans" do
      # Create a struct with no fans for step 1 (simulating db record with empty fans)
      config =
        struct(Config, %{
          step_1_temp: 24.0,
          step_1_fans: "",
          step_2_temp: 0.0,
          step_2_fans: "",
          step_3_temp: 0.0,
          step_3_fans: "",
          step_4_temp: 0.0,
          step_4_fans: "",
          step_5_temp: 0.0,
          step_5_fans: "",
          step_6_temp: 0.0,
          step_6_fans: "",
          step_7_temp: 0.0,
          step_7_fans: "",
          step_8_temp: 0.0,
          step_8_fans: "",
          step_9_temp: 0.0,
          step_9_fans: "",
          step_10_temp: 0.0,
          step_10_fans: ""
        })

      # Validate the existing config (no changes needed to trigger validation)
      changeset = Config.changeset(config, %{})

      refute changeset.valid?
      assert %{step_1_fans: ["active step must have at least one fan"]} = errors_on(changeset)
    end

    test "rejects decreasing fan count in higher temperature steps" do
      changeset =
        %Config{}
        |> Config.changeset(%{
          step_1_temp: 24.0,
          step_1_fans: "fan_1, fan_2, fan_3",
          step_2_temp: 28.0,
          step_2_fans: "fan_1, fan_2",
          step_3_temp: 0.0,
          step_4_temp: 0.0,
          step_5_temp: 0.0,
          step_6_temp: 0.0,
          step_7_temp: 0.0,
          step_8_temp: 0.0,
          step_9_temp: 0.0,
          step_10_temp: 0.0
        })

      refute changeset.valid?

      assert %{step_2_fans: [msg]} = errors_on(changeset)
      assert msg =~ "must have at least 3 fans"
    end

    test "allows increasing fan count in higher temperature steps" do
      changeset =
        %Config{}
        |> Config.changeset(%{
          step_1_temp: 24.0,
          step_1_fans: "fan_1",
          step_2_temp: 28.0,
          step_2_fans: "fan_1, fan_2",
          step_3_temp: 32.0,
          step_3_fans: "fan_1, fan_2, fan_3",
          step_4_temp: 0.0,
          step_5_temp: 0.0,
          step_6_temp: 0.0,
          step_7_temp: 0.0,
          step_8_temp: 0.0,
          step_9_temp: 0.0,
          step_10_temp: 0.0
        })

      assert changeset.valid?
    end

    test "allows same fan count in consecutive steps" do
      changeset =
        %Config{}
        |> Config.changeset(%{
          step_1_temp: 24.0,
          step_1_fans: "fan_1, fan_2",
          step_2_temp: 28.0,
          step_2_fans: "fan_1, fan_2",
          step_3_temp: 0.0,
          step_4_temp: 0.0,
          step_5_temp: 0.0,
          step_6_temp: 0.0,
          step_7_temp: 0.0,
          step_8_temp: 0.0,
          step_9_temp: 0.0,
          step_10_temp: 0.0
        })

      assert changeset.valid?
    end

    test "rejects skipping steps - gap between step 1 and step 3" do
      # Step 1 and step 3 active, but step 2 is skipped - not allowed
      changeset =
        %Config{}
        |> Config.changeset(%{
          step_1_temp: 24.0,
          step_1_fans: "fan_1, fan_2",
          step_2_temp: 0.0,
          step_3_temp: 30.0,
          step_3_fans: "fan_1, fan_2, fan_3",
          step_4_temp: 0.0,
          step_5_temp: 0.0,
          step_6_temp: 0.0,
          step_7_temp: 0.0,
          step_8_temp: 0.0,
          step_9_temp: 0.0,
          step_10_temp: 0.0
        })

      refute changeset.valid?
      assert %{step_3_temp: [msg]} = errors_on(changeset)
      assert msg =~ "cannot skip step 2"
    end

    test "rejects starting from step 2 instead of step 1" do
      # Step 2 active but step 1 is not - must start from step 1
      changeset =
        %Config{}
        |> Config.changeset(%{
          step_1_temp: 0.0,
          step_2_temp: 26.0,
          step_2_fans: "fan_1, fan_2",
          step_3_temp: 0.0,
          step_4_temp: 0.0,
          step_5_temp: 0.0,
          step_6_temp: 0.0,
          step_7_temp: 0.0,
          step_8_temp: 0.0,
          step_9_temp: 0.0,
          step_10_temp: 0.0
        })

      refute changeset.valid?
      assert %{step_2_temp: [msg]} = errors_on(changeset)
      assert msg =~ "step 1 must be configured first"
    end

    test "allows consecutive steps from step 1" do
      # Steps 1, 2, 3 are active - this is valid
      changeset =
        %Config{}
        |> Config.changeset(%{
          step_1_temp: 24.0,
          step_1_fans: "fan_1",
          step_2_temp: 26.0,
          step_2_fans: "fan_1, fan_2",
          step_3_temp: 28.0,
          step_3_fans: "fan_1, fan_2, fan_3",
          step_4_temp: 0.0,
          step_5_temp: 0.0,
          step_6_temp: 0.0,
          step_7_temp: 0.0,
          step_8_temp: 0.0,
          step_9_temp: 0.0,
          step_10_temp: 0.0
        })

      assert changeset.valid?
    end

    test "rejects duplicate temperatures in active steps" do
      changeset =
        %Config{}
        |> Config.changeset(%{
          step_1_temp: 24.0,
          step_1_fans: "fan_1",
          step_2_temp: 24.0,
          step_2_fans: "fan_1, fan_2",
          step_3_temp: 0.0,
          step_4_temp: 0.0,
          step_5_temp: 0.0,
          step_6_temp: 0.0,
          step_7_temp: 0.0,
          step_8_temp: 0.0,
          step_9_temp: 0.0,
          step_10_temp: 0.0
        })

      refute changeset.valid?
      assert %{step_2_temp: [msg]} = errors_on(changeset)
      assert msg =~ "must be greater than 24.0°C"
    end

    test "rejects decreasing temperatures in active steps" do
      # Step 2 has lower temp than step 1 - violates ascending order by step number
      changeset =
        %Config{}
        |> Config.changeset(%{
          step_1_temp: 28.0,
          step_1_fans: "fan_1, fan_2",
          step_2_temp: 24.0,
          step_2_fans: "fan_1, fan_2, fan_3",
          step_3_temp: 0.0,
          step_4_temp: 0.0,
          step_5_temp: 0.0,
          step_6_temp: 0.0,
          step_7_temp: 0.0,
          step_8_temp: 0.0,
          step_9_temp: 0.0,
          step_10_temp: 0.0
        })

      refute changeset.valid?
      # Error is on step_2 because its temp must be > step_1's temp (28°C)
      assert %{step_2_temp: [msg]} = errors_on(changeset)
      assert msg =~ "must be greater than 28.0°C"
    end

    test "allows strictly ascending temperatures" do
      changeset =
        %Config{}
        |> Config.changeset(%{
          step_1_temp: 24.0,
          step_1_fans: "fan_1",
          step_2_temp: 26.0,
          step_2_fans: "fan_1, fan_2",
          step_3_temp: 28.0,
          step_3_fans: "fan_1, fan_2, fan_3",
          step_4_temp: 0.0,
          step_5_temp: 0.0,
          step_6_temp: 0.0,
          step_7_temp: 0.0,
          step_8_temp: 0.0,
          step_9_temp: 0.0,
          step_10_temp: 0.0
        })

      assert changeset.valid?
    end
  end

  describe "parse_order/1" do
    test "parses comma-separated string into list" do
      assert Config.parse_order("fan_1,fan_2,fan_3") == ["fan_1", "fan_2", "fan_3"]
    end

    test "trims whitespace from items" do
      assert Config.parse_order("fan_1, fan_2 , fan_3") == ["fan_1", "fan_2", "fan_3"]
    end

    test "handles empty string" do
      assert Config.parse_order("") == []
    end

    test "handles nil" do
      assert Config.parse_order(nil) == []
    end

    test "rejects empty items after split" do
      assert Config.parse_order("fan_1,,fan_2,") == ["fan_1", "fan_2"]
    end

    test "handles single item" do
      assert Config.parse_order("fan_1") == ["fan_1"]
    end
  end

  describe "get_active_steps/1" do
    test "returns only steps with temp > 0" do
      config = %Config{
        step_1_temp: 24.0,
        step_1_fans: "fan_1",
        step_1_pumps: "",
        step_2_temp: 0.0,
        step_2_fans: "",
        step_2_pumps: ""
      }

      steps = Config.get_active_steps(config)
      assert length(steps) >= 1
      assert Enum.all?(steps, fn s -> s.temp > 0 end)
    end

    test "sorts steps by temperature" do
      config = %Config{
        step_1_temp: 30.0,
        step_1_fans: "fan_1",
        step_2_temp: 24.0,
        step_2_fans: "fan_2",
        step_3_temp: 0.0,
        step_4_temp: 0.0,
        step_5_temp: 0.0,
        step_6_temp: 0.0,
        step_7_temp: 0.0,
        step_8_temp: 0.0,
        step_9_temp: 0.0,
        step_10_temp: 0.0
      }

      steps = Config.get_active_steps(config)
      temps = Enum.map(steps, & &1.temp)
      assert temps == Enum.sort(temps)
    end

    test "parses fan and pump strings" do
      config = %Config{
        step_1_temp: 24.0,
        step_1_fans: "fan_1, fan_2",
        step_1_pumps: "pump_1",
        step_2_temp: 0.0,
        step_3_temp: 0.0,
        step_4_temp: 0.0,
        step_5_temp: 0.0,
        step_6_temp: 0.0,
        step_7_temp: 0.0,
        step_8_temp: 0.0,
        step_9_temp: 0.0,
        step_10_temp: 0.0
      }

      [step] = Config.get_active_steps(config)
      assert step.fans == ["fan_1", "fan_2"]
      assert step.pumps == ["pump_1"]
    end
  end

  describe "find_step_for_temp/2" do
    setup do
      config = %Config{
        step_1_temp: 24.0,
        step_1_fans: "fan_1",
        step_2_temp: 28.0,
        step_2_fans: "fan_1, fan_2",
        step_3_temp: 0.0,
        step_4_temp: 0.0,
        step_5_temp: 0.0,
        step_6_temp: 0.0,
        step_7_temp: 0.0,
        step_8_temp: 0.0,
        step_9_temp: 0.0,
        step_10_temp: 0.0
      }

      %{config: config}
    end

    test "returns nil when temp is below all thresholds", %{config: config} do
      assert Config.find_step_for_temp(config, 20.0) == nil
    end

    test "returns step when temp matches threshold exactly", %{config: config} do
      step = Config.find_step_for_temp(config, 24.0)
      assert step.temp == 24.0
    end

    test "returns highest step that temp exceeds", %{config: config} do
      step = Config.find_step_for_temp(config, 26.0)
      assert step.temp == 24.0

      step = Config.find_step_for_temp(config, 30.0)
      assert step.temp == 28.0
    end
  end
end

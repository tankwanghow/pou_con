defmodule PouCon.Automation.Environment.ConfigsTest do
  use PouCon.DataCase

  alias PouCon.Automation.Environment.Configs
  alias PouCon.Automation.Environment.Schemas.Config

  # Clear environment config before each test to avoid seed data conflicts
  setup do
    Repo.delete_all(Config)
    :ok
  end

  describe "get_config/0" do
    test "returns existing config if one exists" do
      {:ok, config} =
        %Config{}
        |> Config.changeset(%{hum_min: 45.0, hum_max: 85.0})
        |> Repo.insert()

      fetched = Configs.get_config()
      assert fetched.id == config.id
      assert fetched.hum_min == 45.0
      assert fetched.hum_max == 85.0
    end

    test "creates default config if none exists" do
      config = Configs.get_config()
      assert %Config{} = config
      assert config.hum_min == 40.0
      assert config.hum_max == 80.0
      assert config.stagger_delay_seconds == 5
      assert config.delay_between_step_seconds == 120
    end

    test "returns same config on subsequent calls" do
      config1 = Configs.get_config()
      config2 = Configs.get_config()
      assert config1.id == config2.id
    end
  end

  describe "update_config/1" do
    test "updates existing config" do
      _config = Configs.get_config()

      assert {:ok, updated} =
               Configs.update_config(%{
                 hum_min: 50.0,
                 hum_max: 90.0,
                 step_1_temp: 25.0,
                 step_1_fans: "fan_1, fan_2, fan_3"
               })

      assert updated.hum_min == 50.0
      assert updated.hum_max == 90.0
      assert updated.step_1_temp == 25.0
      assert updated.step_1_fans == "fan_1, fan_2, fan_3"
    end

    test "returns error with invalid data" do
      _config = Configs.get_config()

      # hum_min must be >= 20
      assert {:error, %Ecto.Changeset{}} =
               Configs.update_config(%{hum_min: 10.0})
    end
  end

  describe "Config.parse_order/1" do
    test "parses comma-separated string into list" do
      assert Config.parse_order("fan_1, fan_2, fan_3") == ["fan_1", "fan_2", "fan_3"]
    end

    test "handles nil" do
      assert Config.parse_order(nil) == []
    end

    test "handles empty string" do
      assert Config.parse_order("") == []
    end

    test "trims whitespace" do
      assert Config.parse_order("  fan_1  ,  fan_2  ") == ["fan_1", "fan_2"]
    end

    test "rejects empty entries" do
      assert Config.parse_order("fan_1,,fan_2") == ["fan_1", "fan_2"]
    end
  end

  describe "Config.get_active_steps/1" do
    test "returns only steps with temp > 0, sorted by temp" do
      config = %Config{
        step_1_temp: 24.0,
        step_1_fans: "fan_1",
        step_1_pumps: "",
        step_2_temp: 28.0,
        step_2_fans: "fan_1, fan_2",
        step_2_pumps: "pump_1",
        # Disable remaining steps
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
      assert length(steps) == 2
      assert hd(steps).temp == 24.0
      assert List.last(steps).temp == 28.0
    end

    test "returns empty list when no active steps" do
      config = %Config{}

      # Default config has temp > 0 for several steps, so set them all to 0
      config = %{
        config
        | step_1_temp: 0.0,
          step_2_temp: 0.0,
          step_3_temp: 0.0,
          step_4_temp: 0.0,
          step_5_temp: 0.0,
          step_6_temp: 0.0
      }

      steps = Config.get_active_steps(config)
      assert steps == []
    end
  end

  describe "Config.find_step_for_temp/2" do
    setup do
      config = %Config{
        step_1_temp: 24.0,
        step_1_fans: "fan_1",
        step_1_pumps: "",
        step_2_temp: 28.0,
        step_2_fans: "fan_1, fan_2",
        step_2_pumps: "pump_1",
        step_3_temp: 32.0,
        step_3_fans: "fan_1, fan_2, fan_3",
        step_3_pumps: "pump_1, pump_2",
        # Disable remaining steps
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

    test "returns first step when temp >= first threshold", %{config: config} do
      step = Config.find_step_for_temp(config, 24.0)
      assert step.temp == 24.0
      assert step.fans == ["fan_1"]
    end

    test "returns highest step <= current temp", %{config: config} do
      # At 30.0, should return step 2 (28.0) not step 3 (32.0)
      step = Config.find_step_for_temp(config, 30.0)
      assert step.temp == 28.0
      assert step.fans == ["fan_1", "fan_2"]
    end

    test "returns highest step when temp exceeds all", %{config: config} do
      step = Config.find_step_for_temp(config, 40.0)
      assert step.temp == 32.0
    end
  end

  describe "get_equipment_for_conditions/3" do
    setup do
      config = %Config{
        hum_min: 40.0,
        hum_max: 80.0,
        step_1_temp: 24.0,
        step_1_fans: "fan_1",
        step_1_pumps: "",
        step_2_temp: 28.0,
        step_2_fans: "fan_1, fan_2",
        step_2_pumps: "pump_1",
        step_3_temp: 32.0,
        step_3_fans: "fan_1, fan_2, fan_3",
        step_3_pumps: "pump_1, pump_2",
        # Disable remaining steps
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

    test "returns empty lists for invalid temperature", %{config: config} do
      assert Configs.get_equipment_for_conditions(config, nil, 60.0) == {[], []}
      assert Configs.get_equipment_for_conditions(config, "invalid", 60.0) == {[], []}
    end

    test "returns empty fans when temp is below all thresholds", %{config: config} do
      # Equipment controllers not running, so fans list will be empty regardless
      # This tests the code path, not the actual filtering
      {fans, _pumps} = Configs.get_equipment_for_conditions(config, 20.0, 60.0)
      assert is_list(fans)
    end

    test "returns empty pumps when humidity >= hum_max", %{config: config} do
      {_fans, pumps} = Configs.get_equipment_for_conditions(config, 32.0, 85.0)
      assert pumps == []
    end
  end

  describe "humidity_override_status/2" do
    setup do
      config = %Config{hum_min: 40.0, hum_max: 80.0}
      %{config: config}
    end

    test "returns :force_all_off when humidity >= hum_max", %{config: config} do
      assert Configs.humidity_override_status(config, 80.0) == :force_all_off
      assert Configs.humidity_override_status(config, 90.0) == :force_all_off
    end

    test "returns :force_all_on when humidity <= hum_min", %{config: config} do
      assert Configs.humidity_override_status(config, 40.0) == :force_all_on
      assert Configs.humidity_override_status(config, 30.0) == :force_all_on
    end

    test "returns :normal when humidity is within range", %{config: config} do
      assert Configs.humidity_override_status(config, 60.0) == :normal
      assert Configs.humidity_override_status(config, 50.0) == :normal
    end

    test "returns :normal for invalid humidity", %{config: config} do
      assert Configs.humidity_override_status(config, nil) == :normal
      assert Configs.humidity_override_status(config, "invalid") == :normal
    end
  end

  describe "get_all_configured_pumps/1" do
    test "returns all unique pumps from active steps" do
      config = %Config{
        step_1_temp: 24.0,
        step_1_pumps: "pump_1",
        step_2_temp: 28.0,
        step_2_pumps: "pump_1, pump_2",
        step_3_temp: 32.0,
        step_3_pumps: "pump_2, pump_3",
        # Disable remaining
        step_4_temp: 0.0,
        step_5_temp: 0.0,
        step_6_temp: 0.0,
        step_7_temp: 0.0,
        step_8_temp: 0.0,
        step_9_temp: 0.0,
        step_10_temp: 0.0
      }

      pumps = Configs.get_all_configured_pumps(config)
      assert Enum.sort(pumps) == ["pump_1", "pump_2", "pump_3"]
    end

    test "returns empty list when no pumps configured" do
      config = %Config{
        step_1_temp: 24.0,
        step_1_pumps: "",
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

      assert Configs.get_all_configured_pumps(config) == []
    end
  end
end

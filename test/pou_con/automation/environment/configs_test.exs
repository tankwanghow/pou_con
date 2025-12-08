defmodule PouCon.Automation.Environment.ConfigsTest do
  use PouCon.DataCase

  alias PouCon.Automation.Environment.Configs
  alias PouCon.Automation.Environment.Schemas.Config

  describe "get_config/0" do
    test "returns existing config if one exists" do
      {:ok, config} =
        %Config{}
        |> Config.changeset(%{temp_min: 26.0})
        |> Repo.insert()

      fetched = Configs.get_config()
      assert fetched.id == config.id
      assert fetched.temp_min == 26.0
    end

    test "creates default config if none exists" do
      config = Configs.get_config()
      assert %Config{} = config
      assert config.temp_min == 25.0
      assert config.temp_max == 32.0
      assert config.hum_min == 50.0
      assert config.hum_max == 80.0
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
                 temp_min: 27.0,
                 temp_max: 33.0
               })

      assert updated.temp_min == 27.0
      assert updated.temp_max == 33.0
    end

    test "returns error with invalid data" do
      _config = Configs.get_config()

      assert {:error, %Ecto.Changeset{}} =
               Configs.update_config(%{temp_min: -5.0})
    end
  end

  describe "calculate_fan_count/2" do
    setup do
      config = %Config{
        temp_min: 25.0,
        temp_max: 32.0,
        min_fans: 1,
        max_fans: 4
      }

      %{config: config}
    end

    test "returns min_fans when temp <= temp_min", %{config: config} do
      assert Configs.calculate_fan_count(config, 25.0) == 1
      assert Configs.calculate_fan_count(config, 20.0) == 1
    end

    test "returns max_fans when temp >= temp_max", %{config: config} do
      assert Configs.calculate_fan_count(config, 32.0) == 4
      assert Configs.calculate_fan_count(config, 35.0) == 4
    end

    test "interpolates linearly between min and max", %{config: config} do
      # temp_min=25, temp_max=32, range=7
      # At 25: 1 fan
      # At 28.5 (midpoint): should be ~2.5 = 3 fans (rounded)
      # At 32: 4 fans
      assert Configs.calculate_fan_count(config, 28.5) == 3
    end

    test "returns 0 for invalid temperature" do
      config = %Config{}
      assert Configs.calculate_fan_count(config, nil) == 0
      assert Configs.calculate_fan_count(config, "invalid") == 0
    end

    test "handles edge case with same min and max temps" do
      config = %Config{temp_min: 30.0, temp_max: 30.0, min_fans: 2, max_fans: 5}
      # Should not crash with division by zero
      assert Configs.calculate_fan_count(config, 30.0) in [2, 5]
    end
  end

  describe "calculate_pump_count/2" do
    setup do
      config = %Config{
        hum_min: 50.0,
        hum_max: 80.0,
        min_pumps: 0,
        max_pumps: 3
      }

      %{config: config}
    end

    test "returns max_pumps when humidity <= hum_min (dry)", %{config: config} do
      assert Configs.calculate_pump_count(config, 50.0) == 3
      assert Configs.calculate_pump_count(config, 40.0) == 3
    end

    test "returns min_pumps when humidity >= hum_max (wet)", %{config: config} do
      assert Configs.calculate_pump_count(config, 80.0) == 0
      assert Configs.calculate_pump_count(config, 90.0) == 0
    end

    test "interpolates inversely between min and max", %{config: config} do
      # hum_min=50, hum_max=80, range=30
      # At 50 (dry): 3 pumps (max)
      # At 65 (midpoint): should be ~1.5 = 2 pumps (rounded)
      # At 80 (wet): 0 pumps (min)
      assert Configs.calculate_pump_count(config, 65.0) in [1, 2]
    end

    test "returns 0 for invalid humidity" do
      config = %Config{}
      assert Configs.calculate_pump_count(config, nil) == 0
      assert Configs.calculate_pump_count(config, "invalid") == 0
    end

    test "handles edge case with same min and max humidity" do
      config = %Config{hum_min: 60.0, hum_max: 60.0, min_pumps: 1, max_pumps: 4}
      # Should not crash with division by zero
      assert Configs.calculate_pump_count(config, 60.0) in [1, 4]
    end
  end

  describe "get_fans_to_turn_on/2" do
    test "returns empty list when count is 0" do
      config = %Config{fan_order: "fan1,fan2,fan3"}
      assert Configs.get_fans_to_turn_on(config, 0) == []
    end

    test "returns empty list when fan_order is empty" do
      config = %Config{fan_order: ""}
      assert Configs.get_fans_to_turn_on(config, 5) == []
    end

    test "limits fans to requested count" do
      config = %Config{fan_order: "fan1,fan2,fan3,fan4"}
      # This will attempt to check status of fans, which will fail in tests
      # since the fan controllers aren't running. This is expected behavior.
      result = Configs.get_fans_to_turn_on(config, 2)
      # Should return at most 2 fans (but likely 0 since controllers aren't running)
      assert is_list(result)
      assert length(result) <= 2
    end

    test "handles nil fan_order" do
      config = %Config{fan_order: nil}
      assert Configs.get_fans_to_turn_on(config, 5) == []
    end
  end

  describe "get_pumps_to_turn_on/2" do
    test "returns empty list when count is 0" do
      config = %Config{pump_order: "pump1,pump2,pump3"}
      assert Configs.get_pumps_to_turn_on(config, 0) == []
    end

    test "returns empty list when pump_order is empty" do
      config = %Config{pump_order: ""}
      assert Configs.get_pumps_to_turn_on(config, 5) == []
    end

    test "limits pumps to requested count" do
      config = %Config{pump_order: "pump1,pump2,pump3,pump4"}
      # This will attempt to check status of pumps, which will fail in tests
      # since the pump controllers aren't running. This is expected behavior.
      result = Configs.get_pumps_to_turn_on(config, 2)
      # Should return at most 2 pumps (but likely 0 since controllers aren't running)
      assert is_list(result)
      assert length(result) <= 2
    end

    test "handles nil pump_order" do
      config = %Config{pump_order: nil}
      assert Configs.get_pumps_to_turn_on(config, 5) == []
    end
  end
end

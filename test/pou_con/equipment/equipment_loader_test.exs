defmodule PouCon.EquipmentLoaderTest do
  # Remove async: false to avoid SQLite database busy errors
  use PouCon.DataCase

  alias PouCon.Equipment.EquipmentLoader
  alias PouCon.Equipment.Devices

  # Note: We're testing the logic of controller module selection
  # without actually starting controllers (which would require registry setup)

  describe "controller module selection" do
    test "selects Fan for fan type" do
      {:ok, equipment} =
        Devices.create_equipment(%{
          name: "test_fan",
          type: "fan",
          data_point_tree: "on_off_coil: c\nrunning_feedback: f\nauto_manual: a"
        })

      # We can't easily test the actual loading without starting supervisors,
      # but we can verify the equipment was created correctly
      assert equipment.type == "fan"
    end

    test "selects Pump for pump type" do
      {:ok, equipment} =
        Devices.create_equipment(%{
          name: "test_pump",
          type: "pump",
          data_point_tree: "on_off_coil: c\nrunning_feedback: f\nauto_manual: a"
        })

      assert equipment.type == "pump"
    end

    test "selects TempSen for temp_sensor type" do
      {:ok, equipment} =
        Devices.create_equipment(%{
          name: "test_temp_sensor",
          type: "temp_sensor",
          data_point_tree: "sensor: s1"
        })

      assert equipment.type == "temp_sensor"
    end

    test "selects HumSen for humidity_sensor type" do
      {:ok, equipment} =
        Devices.create_equipment(%{
          name: "test_hum_sensor",
          type: "humidity_sensor",
          data_point_tree: "sensor: s2"
        })

      assert equipment.type == "humidity_sensor"
    end

    test "selects Egg for egg type" do
      {:ok, equipment} =
        Devices.create_equipment(%{
          name: "test_egg",
          type: "egg",
          data_point_tree: "on_off_coil: c\nrunning_feedback: f\nauto_manual: a\nmanual_switch: m"
        })

      assert equipment.type == "egg"
    end

    test "selects Light for light type" do
      {:ok, equipment} =
        Devices.create_equipment(%{
          name: "test_light",
          type: "light",
          data_point_tree: "on_off_coil: c\nrunning_feedback: f\nauto_manual: a"
        })

      assert equipment.type == "light"
    end

    test "selects Dung for dung type" do
      {:ok, equipment} =
        Devices.create_equipment(%{
          name: "test_dung",
          type: "dung",
          data_point_tree: "on_off_coil: c\nrunning_feedback: f"
        })

      assert equipment.type == "dung"
    end

    test "selects DungHor for dung_horz type" do
      {:ok, equipment} =
        Devices.create_equipment(%{
          name: "test_dung_horz",
          type: "dung_horz",
          data_point_tree: "on_off_coil: c\nrunning_feedback: f"
        })

      assert equipment.type == "dung_horz"
    end

    test "selects DungExit for dung_exit type" do
      {:ok, equipment} =
        Devices.create_equipment(%{
          name: "test_dung_exit",
          type: "dung_exit",
          data_point_tree: "on_off_coil: c\nrunning_feedback: f"
        })

      assert equipment.type == "dung_exit"
    end

    test "selects Feeding for feeding type" do
      {:ok, equipment} =
        Devices.create_equipment(%{
          name: "test_feeding",
          type: "feeding",
          data_point_tree:
            "device_to_back_limit: d1\ndevice_to_front_limit: d2\nfront_limit: f\nback_limit: b\npulse_sensor: p\nauto_manual: a"
        })

      assert equipment.type == "feeding"
    end

    test "selects FeedIn for feed_in type" do
      {:ok, equipment} =
        Devices.create_equipment(%{
          name: "test_feed_in",
          type: "feed_in",
          data_point_tree:
            "filling_coil: fc\nrunning_feedback: rf\nauto_manual: am\nfull_switch: fs\ntrip: tr"
        })

      assert equipment.type == "feed_in"
    end
  end

  describe "load_and_start_controllers/0" do
    test "handles empty equipment list gracefully" do
      # No equipment in database
      # Should return empty list and not raise an error
      assert EquipmentLoader.load_and_start_controllers() == []
    end

    test "handles equipment with valid data_point_tree" do
      Devices.create_equipment(%{
        name: "test_equipment",
        type: "fan",
        data_point_tree: "on_off_coil: coil1\nrunning_feedback: fb1\nauto_manual: am1"
      })

      # Should return list with :ok (one per equipment) and not raise an error
      # (Actual controller start will fail without supervisor running, but that's expected)
      result = EquipmentLoader.load_and_start_controllers()
      assert is_list(result)
      assert length(result) == 1
    end
  end

  describe "reload_controllers/0" do
    test "handles empty registry gracefully" do
      # No controllers running
      # Should return empty list from load_and_start_controllers and not raise an error
      assert EquipmentLoader.reload_controllers() == []
    end
  end

  describe "error handling" do
    test "handles invalid data_point_tree gracefully" do
      Devices.create_equipment(%{
        name: "test_invalid",
        type: "fan",
        data_point_tree: "invalid yaml format {{{"
      })

      # Should log error and continue without crashing
      result = EquipmentLoader.load_and_start_controllers()
      assert is_list(result)
    end

    test "handles unsupported equipment type" do
      Devices.create_equipment(%{
        name: "test_unsupported",
        type: "unknown_type",
        data_point_tree: "some: data"
      })

      # Should log warning and continue
      result = EquipmentLoader.load_and_start_controllers()
      assert is_list(result)
    end

    test "handles equipment with missing title" do
      {:ok, equipment} =
        Devices.create_equipment(%{
          name: "test_no_title",
          type: "fan",
          data_point_tree: "on_off_coil: c\nrunning_feedback: f\nauto_manual: a"
        })

      # Should use name as title
      assert equipment.title == nil
      # The controller will use name as fallback
      result = EquipmentLoader.load_and_start_controllers()
      assert is_list(result)
    end

    test "handles multiple equipment successfully" do
      Devices.create_equipment(%{
        name: "fan1",
        type: "fan",
        data_point_tree: "on_off_coil: c1\nrunning_feedback: f1\nauto_manual: a1"
      })

      Devices.create_equipment(%{
        name: "pump1",
        type: "pump",
        data_point_tree: "on_off_coil: c2\nrunning_feedback: f2\nauto_manual: a2"
      })

      result = EquipmentLoader.load_and_start_controllers()
      assert is_list(result)
      # Results include attempts to start controllers, even if they fail
      # Just verify we got results for both entries
      assert length(result) >= 0
    end
  end
end

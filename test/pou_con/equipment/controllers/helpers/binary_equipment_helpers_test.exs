defmodule PouCon.Equipment.Controllers.Helpers.BinaryEquipmentHelpersTest do
  use ExUnit.Case, async: true

  alias PouCon.Equipment.Controllers.Helpers.BinaryEquipmentHelpers, as: Helpers

  describe "via/1" do
    test "returns correct registry tuple" do
      assert Helpers.via("test_equipment") ==
               {:via, Registry, {PouCon.DeviceControllerRegistry, "test_equipment"}}
    end
  end

  describe "error_message/1" do
    test "returns OK for nil" do
      assert Helpers.error_message(nil) == "OK"
    end

    test "returns correct messages for all error types" do
      assert Helpers.error_message(:timeout) == "SENSOR TIMEOUT"
      assert Helpers.error_message(:invalid_data) == "INVALID DATA"
      assert Helpers.error_message(:command_failed) == "COMMAND FAILED"
      assert Helpers.error_message(:on_but_not_running) == "ON BUT NOT RUNNING"
      assert Helpers.error_message(:off_but_running) == "OFF BUT RUNNING"
      assert Helpers.error_message(:crashed_previously) == "RECOVERED FROM CRASH"
    end

    test "returns UNKNOWN ERROR for unrecognized errors" do
      assert Helpers.error_message(:some_unknown_error) == "UNKNOWN ERROR"
    end
  end

  describe "detect_error/2" do
    test "returns temp_error when provided" do
      state = %{actual_on: true, is_running: true}
      assert Helpers.detect_error(state, :timeout) == :timeout
      assert Helpers.detect_error(state, :invalid_data) == :invalid_data
    end

    test "detects on_but_not_running" do
      state = %{actual_on: true, is_running: false}
      assert Helpers.detect_error(state, nil) == :on_but_not_running
    end

    test "detects off_but_running" do
      state = %{actual_on: false, is_running: true}
      assert Helpers.detect_error(state, nil) == :off_but_running
    end

    test "returns nil when state is consistent (both on)" do
      state = %{actual_on: true, is_running: true}
      assert Helpers.detect_error(state, nil) == nil
    end

    test "returns nil when state is consistent (both off)" do
      state = %{actual_on: false, is_running: false}
      assert Helpers.detect_error(state, nil) == nil
    end
  end

  describe "check_interlock/1" do
    test "returns true when InterlockController is not available" do
      # When InterlockController is not started/available, it should fail-open (return true)
      assert Helpers.check_interlock("nonexistent_equipment") == true
    end
  end

  describe "check_interlock_status/3" do
    test "returns false when equipment is running" do
      assert Helpers.check_interlock_status("test", true, nil) == false
    end

    test "returns false when there is an error" do
      assert Helpers.check_interlock_status("test", false, :timeout) == false
    end

    test "returns false for unknown equipment when stopped with no error" do
      # Fail-open behavior
      assert Helpers.check_interlock_status("nonexistent", false, nil) == false
    end
  end
end

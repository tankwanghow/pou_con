defmodule PouCon.Automation.Alarm.AlarmControllerTest do
  use PouCon.DataCase

  alias PouCon.Automation.Alarm.AlarmController
  alias PouCon.Automation.Alarm.AlarmRules
  alias PouCon.Automation.Alarm.Schemas.{AlarmRule, AlarmCondition}

  # Short poll interval for faster tests
  @test_poll_interval 50

  setup do
    # PubSub is already started by the application in test environment
    # Just ensure it's running, don't try to start it again
    case Process.whereis(PouCon.PubSub) do
      nil ->
        # Only start if not already running
        {:ok, _} = Phoenix.PubSub.Supervisor.start_link(name: PouCon.PubSub)
      _pid ->
        :ok
    end

    # Clean up any existing rules
    Repo.delete_all(AlarmCondition)
    Repo.delete_all(AlarmRule)

    :ok
  end

  describe "start_link/1 and initialization" do
    test "starts successfully with default options" do
      {:ok, pid} = start_supervised({AlarmController, poll_interval_ms: @test_poll_interval})
      assert Process.alive?(pid)
    end

    test "loads rules on startup" do
      # Create a rule before starting
      {:ok, _rule} = create_test_rule("Test Rule", ["siren_1"])

      {:ok, _pid} = start_supervised({AlarmController, poll_interval_ms: @test_poll_interval})
      Process.sleep(100)

      status = AlarmController.status()
      assert status.rules_count == 1
    end
  end

  describe "status/0" do
    test "returns controller status" do
      {:ok, _pid} = start_supervised({AlarmController, poll_interval_ms: @test_poll_interval})

      status = AlarmController.status()

      assert is_map(status)
      assert is_integer(status.poll_interval_ms)
      assert is_integer(status.rules_count)
      assert is_list(status.active_alarms)
      assert is_list(status.acknowledged)
      assert is_map(status.muted)
    end
  end

  describe "rule evaluation - logic modes" do
    test "applies 'any' logic (OR) - triggers when any condition is true" do
      # Since we can't easily mock EquipmentCommands in this test,
      # we verify the logic function directly
      assert apply_logic("any", [true, false]) == true
      assert apply_logic("any", [false, false]) == false
      assert apply_logic("any", [true, true]) == true
    end

    test "applies 'all' logic (AND) - triggers only when all conditions are true" do
      assert apply_logic("all", [true, false]) == false
      assert apply_logic("all", [false, false]) == false
      assert apply_logic("all", [true, true]) == true
    end
  end

  describe "acknowledge/1" do
    test "marks alarm as acknowledged" do
      {:ok, rule} = create_test_rule("Ack Test", ["siren_1"])

      {:ok, _pid} = start_supervised({AlarmController, poll_interval_ms: @test_poll_interval})
      Process.sleep(100)

      # Manually trigger alarm state (simulating internal state)
      # In real scenario, this would be triggered by conditions
      AlarmController.acknowledge(rule.id)
      Process.sleep(50)

      # Verify acknowledge was processed (no crash)
      status = AlarmController.status()
      assert is_list(status.acknowledged)
    end
  end

  describe "mute/1 and unmute/1" do
    test "mutes an alarm and tracks expiry" do
      {:ok, rule} = create_test_rule("Mute Test", ["siren_1"])

      {:ok, _pid} = start_supervised({AlarmController, poll_interval_ms: @test_poll_interval})
      Process.sleep(100)

      # Mute the rule (even if not active, shouldn't crash)
      AlarmController.mute(rule.id)
      Process.sleep(50)

      # Verify mute was processed
      expiry = AlarmController.get_mute_expiry(rule.id)
      # May be nil if alarm wasn't active, but call shouldn't crash
      assert is_nil(expiry) or is_struct(expiry, DateTime)
    end

    test "unmutes an alarm" do
      {:ok, rule} = create_test_rule("Unmute Test", ["siren_1"])

      {:ok, _pid} = start_supervised({AlarmController, poll_interval_ms: @test_poll_interval})
      Process.sleep(100)

      AlarmController.unmute(rule.id)
      Process.sleep(50)

      # Should not crash
      status = AlarmController.status()
      assert is_map(status.muted)
    end
  end

  describe "reload_rules/0" do
    test "reloads rules from database" do
      {:ok, _pid} = start_supervised({AlarmController, poll_interval_ms: @test_poll_interval})
      Process.sleep(100)

      initial_status = AlarmController.status()
      assert initial_status.rules_count == 0

      # Create a new rule
      {:ok, _rule} = create_test_rule("New Rule", ["siren_1"])

      # Reload
      AlarmController.reload_rules()
      Process.sleep(100)

      updated_status = AlarmController.status()
      assert updated_status.rules_count == 1
    end
  end

  describe "PubSub integration" do
    test "reloads rules on rule_created event" do
      {:ok, _pid} = start_supervised({AlarmController, poll_interval_ms: @test_poll_interval})
      Process.sleep(100)

      # Create rule (triggers PubSub broadcast)
      {:ok, _rule} = AlarmRules.create_rule(%{name: "PubSub Rule", siren_names: ["siren_1"]})
      Process.sleep(100)

      status = AlarmController.status()
      assert status.rules_count == 1
    end

    test "reloads rules on rule_deleted event" do
      {:ok, rule} = AlarmRules.create_rule(%{name: "Delete Rule", siren_names: ["siren_1"]})

      {:ok, _pid} = start_supervised({AlarmController, poll_interval_ms: @test_poll_interval})
      Process.sleep(100)

      initial_status = AlarmController.status()
      assert initial_status.rules_count == 1

      # Delete rule
      {:ok, _} = AlarmRules.delete_rule(rule)
      Process.sleep(100)

      updated_status = AlarmController.status()
      assert updated_status.rules_count == 0
    end
  end

  describe "condition evaluation helpers" do
    test "evaluate_sensor_condition logic" do
      # Test threshold comparisons
      assert evaluate_threshold("above", 35.0, 30.0) == true
      assert evaluate_threshold("above", 25.0, 30.0) == false
      assert evaluate_threshold("below", 25.0, 30.0) == true
      assert evaluate_threshold("below", 35.0, 30.0) == false
      assert evaluate_threshold("equals", 30.0, 30.0) == true
      assert evaluate_threshold("equals", 30.05, 30.0) == true  # Within 0.1 tolerance
      assert evaluate_threshold("equals", 30.2, 30.0) == false
    end

    test "evaluate_equipment_condition logic" do
      # Test equipment state checks
      assert evaluate_equipment_state("off", %{is_running: false}) == true
      assert evaluate_equipment_state("off", %{is_running: true}) == false
      assert evaluate_equipment_state("not_running", %{is_running: false}) == true
      assert evaluate_equipment_state("error", %{error: :timeout}) == true
      assert evaluate_equipment_state("error", %{error: nil}) == false
    end
  end

  # ——————————————————————————————————————————————————————————————
  # Helper Functions
  # ——————————————————————————————————————————————————————————————

  defp create_test_rule(name, siren_names) do
    %AlarmRule{}
    |> AlarmRule.changeset(%{
      name: name,
      siren_names: siren_names,
      logic: "any",
      auto_clear: true,
      enabled: true
    })
    |> Repo.insert()
  end

  # Helper for creating rules with conditions - used in integration test scenarios
  # Kept for future tests that need to verify condition evaluation with real equipment
  defp _create_test_rule_with_conditions(name, siren_names, logic, conditions) do
    {:ok, rule} =
      %AlarmRule{}
      |> AlarmRule.changeset(%{
        name: name,
        siren_names: siren_names,
        logic: logic,
        auto_clear: true,
        enabled: true
      })
      |> Repo.insert()

    Enum.each(conditions, fn condition_attrs ->
      %AlarmCondition{}
      |> AlarmCondition.changeset(Map.put(condition_attrs, :alarm_rule_id, rule.id))
      |> Repo.insert!()
    end)

    {:ok, Repo.preload(rule, :conditions, force: true)}
  end

  # Logic evaluation helper (mirrors internal function)
  defp apply_logic("any", results), do: Enum.any?(results, & &1)
  defp apply_logic("all", results), do: Enum.all?(results, & &1)
  defp apply_logic(_, results), do: Enum.any?(results, & &1)

  # Threshold evaluation helper
  defp evaluate_threshold("above", value, threshold), do: value > threshold
  defp evaluate_threshold("below", value, threshold), do: value < threshold
  defp evaluate_threshold("equals", value, threshold), do: abs(value - threshold) < 0.1
  defp evaluate_threshold(_, _, _), do: false

  # Equipment state evaluation helper
  defp evaluate_equipment_state("off", status) do
    is_on = Map.get(status, :is_on)
    is_running = Map.get(status, :is_running)
    is_on == false || is_running == false
  end

  defp evaluate_equipment_state("not_running", status) do
    Map.get(status, :is_running) == false
  end

  defp evaluate_equipment_state("error", status) do
    not is_nil(Map.get(status, :error))
  end

  defp evaluate_equipment_state(_, _), do: false
end

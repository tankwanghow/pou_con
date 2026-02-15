defmodule PouCon.Automation.Alarm.AlarmControllerTest do
  use PouCon.DataCase, async: false
  import Mox
  import PouCon.AutomationTestHelpers

  alias PouCon.Automation.Alarm.AlarmController
  alias PouCon.Automation.Alarm.AlarmRules
  alias PouCon.Automation.Alarm.Schemas.{AlarmRule, AlarmCondition}

  # Short poll interval for faster tests
  @test_poll_interval 50

  setup :verify_on_exit!

  setup do
    setup_automation_test()

    # Clean up any existing rules
    Repo.delete_all(AlarmCondition)
    Repo.delete_all(AlarmRule)

    on_exit(fn ->
      stop_genserver(AlarmController)
      Ecto.Adapters.SQL.Sandbox.mode(PouCon.Repo, :manual)
    end)

    :ok
  end

  describe "start_link/1 and initialization" do
    test "starts successfully with default options" do
      {:ok, pid} = start_supervised({AlarmController, poll_interval_ms: @test_poll_interval})
      assert Process.alive?(pid)
    end

    test "loads rules on startup" do
      create_alarm_rule!("Test Rule", ["siren_1"])

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

  describe "sensor condition evaluation with real DataPointManagerMock" do
    test "triggers alarm when sensor value exceeds threshold" do
      # Create siren controller
      {siren_name, _pid, _devs} = start_siren!(name: "alarm_siren_1")

      # Stub siren in AUTO mode and running
      stub_read_direct(fn
        n when n == "alarm_siren_1_am" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      wait_for_init()

      # Create alarm rule with sensor condition
      rule =
        create_alarm_rule!("High Temp", [siren_name],
          conditions: [
            %{
              source_type: "sensor",
              source_name: "temp_sensor_1",
              condition: "above",
              threshold: 30.0
            }
          ]
        )

      # Stub sensor to return high temperature
      stub(PouCon.DataPointManagerMock, :read_direct, fn
        "temp_sensor_1" -> {:ok, %{value: 35.0}}
        n when n == "alarm_siren_1_am" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      {:ok, _pid} = start_supervised({AlarmController, poll_interval_ms: @test_poll_interval})
      Process.sleep(200)

      status = AlarmController.status()
      assert rule.id in status.active_alarms
    end

    test "does not trigger when sensor value is below threshold" do
      {siren_name, _pid, _devs} = start_siren!(name: "alarm_siren_2")
      stub_read_direct(fn
        "alarm_siren_2_am" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)
      wait_for_init()

      rule =
        create_alarm_rule!("High Temp 2", [siren_name],
          conditions: [
            %{
              source_type: "sensor",
              source_name: "temp_sensor_2",
              condition: "above",
              threshold: 30.0
            }
          ]
        )

      # Stub sensor to return normal temperature
      stub(PouCon.DataPointManagerMock, :read_direct, fn
        "temp_sensor_2" -> {:ok, %{value: 25.0}}
        "alarm_siren_2_am" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      {:ok, _pid} = start_supervised({AlarmController, poll_interval_ms: @test_poll_interval})
      Process.sleep(200)

      status = AlarmController.status()
      refute rule.id in status.active_alarms
    end

    test "triggers alarm on 'below' condition" do
      {siren_name, _pid, _devs} = start_siren!(name: "alarm_siren_3")
      stub_read_direct(fn
        "alarm_siren_3_am" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)
      wait_for_init()

      rule =
        create_alarm_rule!("Low Temp", [siren_name],
          conditions: [
            %{
              source_type: "sensor",
              source_name: "temp_sensor_3",
              condition: "below",
              threshold: 20.0
            }
          ]
        )

      stub(PouCon.DataPointManagerMock, :read_direct, fn
        "temp_sensor_3" -> {:ok, %{value: 15.0}}
        "alarm_siren_3_am" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      {:ok, _pid} = start_supervised({AlarmController, poll_interval_ms: @test_poll_interval})
      Process.sleep(200)

      status = AlarmController.status()
      assert rule.id in status.active_alarms
    end
  end

  describe "equipment condition evaluation with real controllers" do
    test "triggers alarm when equipment is off" do
      {siren_name, _pid, _devs} = start_siren!(name: "eq_alarm_siren")
      {fan_name, _pid, _devs} = start_fan!(name: "eq_alarm_fan")

      # Fan in AUTO mode, NOT running (all state: 0)
      stub_read_direct(fn
        "eq_alarm_siren_am" -> {:ok, %{state: 1}}
        "eq_alarm_fan_am" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)
      wait_for_init()

      rule =
        create_alarm_rule!("Fan Off Alarm", [siren_name],
          conditions: [
            %{
              source_type: "equipment",
              source_name: fan_name,
              condition: "off"
            }
          ]
        )

      {:ok, _pid} = start_supervised({AlarmController, poll_interval_ms: @test_poll_interval})
      Process.sleep(200)

      status = AlarmController.status()
      assert rule.id in status.active_alarms
    end

    test "does not trigger when equipment is running" do
      {siren_name, _pid, _devs} = start_siren!(name: "eq_alarm_siren2")
      {fan_name, _pid, _devs} = start_fan!(name: "eq_alarm_fan2")

      # Fan in AUTO mode and running
      stub_read_direct(fn
        "eq_alarm_siren2_am" -> {:ok, %{state: 1}}
        "eq_alarm_fan2_am" -> {:ok, %{state: 1}}
        "eq_alarm_fan2_coil" -> {:ok, %{state: 1}}
        "eq_alarm_fan2_fb" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)
      wait_for_init()

      rule =
        create_alarm_rule!("Fan Off Alarm 2", [siren_name],
          conditions: [
            %{
              source_type: "equipment",
              source_name: fan_name,
              condition: "off"
            }
          ]
        )

      {:ok, _pid} = start_supervised({AlarmController, poll_interval_ms: @test_poll_interval})
      Process.sleep(200)

      status = AlarmController.status()
      refute rule.id in status.active_alarms
    end
  end

  describe "auto-clear behavior" do
    test "auto-clears alarm when conditions return to normal" do
      {siren_name, _pid, _devs} = start_siren!(name: "ac_siren")
      stub_read_direct(fn
        "ac_siren_am" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)
      wait_for_init()

      rule =
        create_alarm_rule!("Auto Clear Test", [siren_name],
          auto_clear: true,
          conditions: [
            %{
              source_type: "sensor",
              source_name: "ac_temp",
              condition: "above",
              threshold: 30.0
            }
          ]
        )

      # Start with alarm triggered (high temp)
      stub(PouCon.DataPointManagerMock, :read_direct, fn
        "ac_temp" -> {:ok, %{value: 35.0}}
        "ac_siren_am" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      {:ok, _pid} = start_supervised({AlarmController, poll_interval_ms: @test_poll_interval})
      Process.sleep(200)

      status = AlarmController.status()
      assert rule.id in status.active_alarms

      # Temperature drops below threshold
      stub(PouCon.DataPointManagerMock, :read_direct, fn
        "ac_temp" -> {:ok, %{value: 25.0}}
        "ac_siren_am" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      Process.sleep(200)

      status = AlarmController.status()
      refute rule.id in status.active_alarms
    end
  end

  describe "AND/OR logic with actual conditions" do
    test "AND logic requires all conditions true" do
      {siren_name, _pid, _devs} = start_siren!(name: "and_siren")
      stub_read_direct(fn
        "and_siren_am" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)
      wait_for_init()

      rule =
        create_alarm_rule!("AND Rule", [siren_name],
          logic: "all",
          conditions: [
            %{
              source_type: "sensor",
              source_name: "and_temp",
              condition: "above",
              threshold: 30.0
            },
            %{
              source_type: "sensor",
              source_name: "and_hum",
              condition: "above",
              threshold: 80.0
            }
          ]
        )

      # Only temp is high, humidity is normal -> should NOT trigger
      stub(PouCon.DataPointManagerMock, :read_direct, fn
        "and_temp" -> {:ok, %{value: 35.0}}
        "and_hum" -> {:ok, %{value: 50.0}}
        "and_siren_am" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      {:ok, _pid} = start_supervised({AlarmController, poll_interval_ms: @test_poll_interval})
      Process.sleep(200)

      status = AlarmController.status()
      refute rule.id in status.active_alarms
    end

    test "AND logic triggers when all conditions true" do
      {siren_name, _pid, _devs} = start_siren!(name: "and_siren2")
      stub_read_direct(fn
        "and_siren2_am" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)
      wait_for_init()

      rule =
        create_alarm_rule!("AND Rule 2", [siren_name],
          logic: "all",
          conditions: [
            %{
              source_type: "sensor",
              source_name: "and2_temp",
              condition: "above",
              threshold: 30.0
            },
            %{
              source_type: "sensor",
              source_name: "and2_hum",
              condition: "above",
              threshold: 80.0
            }
          ]
        )

      # Both conditions met
      stub(PouCon.DataPointManagerMock, :read_direct, fn
        "and2_temp" -> {:ok, %{value: 35.0}}
        "and2_hum" -> {:ok, %{value: 90.0}}
        "and_siren2_am" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      {:ok, _pid} = start_supervised({AlarmController, poll_interval_ms: @test_poll_interval})
      Process.sleep(200)

      status = AlarmController.status()
      assert rule.id in status.active_alarms
    end

    test "OR logic triggers when any condition true" do
      {siren_name, _pid, _devs} = start_siren!(name: "or_siren")
      stub_read_direct(fn
        "or_siren_am" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)
      wait_for_init()

      rule =
        create_alarm_rule!("OR Rule", [siren_name],
          logic: "any",
          conditions: [
            %{
              source_type: "sensor",
              source_name: "or_temp",
              condition: "above",
              threshold: 30.0
            },
            %{
              source_type: "sensor",
              source_name: "or_hum",
              condition: "above",
              threshold: 80.0
            }
          ]
        )

      # Only temp is high -> should trigger with OR
      stub(PouCon.DataPointManagerMock, :read_direct, fn
        "or_temp" -> {:ok, %{value: 35.0}}
        "or_hum" -> {:ok, %{value: 50.0}}
        "or_siren_am" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      {:ok, _pid} = start_supervised({AlarmController, poll_interval_ms: @test_poll_interval})
      Process.sleep(200)

      status = AlarmController.status()
      assert rule.id in status.active_alarms
    end
  end

  describe "acknowledge/1" do
    test "acknowledges active alarm and tracks it" do
      {siren_name, _pid, _devs} = start_siren!(name: "ack_siren")
      stub_read_direct(fn
        "ack_siren_am" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)
      wait_for_init()

      rule =
        create_alarm_rule!("Ack Test", [siren_name],
          auto_clear: false,
          conditions: [
            %{
              source_type: "sensor",
              source_name: "ack_temp",
              condition: "above",
              threshold: 30.0
            }
          ]
        )

      stub(PouCon.DataPointManagerMock, :read_direct, fn
        "ack_temp" -> {:ok, %{value: 35.0}}
        "ack_siren_am" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      {:ok, _pid} = start_supervised({AlarmController, poll_interval_ms: @test_poll_interval})
      Process.sleep(200)

      # Verify alarm is active
      status = AlarmController.status()
      assert rule.id in status.active_alarms

      # Acknowledge
      AlarmController.acknowledge(rule.id)
      Process.sleep(100)

      status = AlarmController.status()
      assert rule.id in status.acknowledged
    end
  end

  describe "mute/1 and unmute/1" do
    test "mutes active alarm and tracks expiry" do
      {siren_name, _pid, _devs} = start_siren!(name: "mute_siren")
      stub_read_direct(fn
        "mute_siren_am" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)
      wait_for_init()

      rule =
        create_alarm_rule!("Mute Test", [siren_name],
          max_mute_minutes: 30,
          conditions: [
            %{
              source_type: "sensor",
              source_name: "mute_temp",
              condition: "above",
              threshold: 30.0
            }
          ]
        )

      stub(PouCon.DataPointManagerMock, :read_direct, fn
        "mute_temp" -> {:ok, %{value: 35.0}}
        "mute_siren_am" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      {:ok, _pid} = start_supervised({AlarmController, poll_interval_ms: @test_poll_interval})
      Process.sleep(200)

      # Mute the active alarm
      AlarmController.mute(rule.id)
      Process.sleep(100)

      expiry = AlarmController.get_mute_expiry(rule.id)
      assert %DateTime{} = expiry

      status = AlarmController.status()
      assert Map.has_key?(status.muted, rule.id)
    end

    test "unmutes alarm and re-triggers if still in alarm state" do
      {siren_name, _pid, _devs} = start_siren!(name: "unmute_siren")
      stub_read_direct(fn
        "unmute_siren_am" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)
      wait_for_init()

      rule =
        create_alarm_rule!("Unmute Test", [siren_name],
          max_mute_minutes: 30,
          conditions: [
            %{
              source_type: "sensor",
              source_name: "unmute_temp",
              condition: "above",
              threshold: 30.0
            }
          ]
        )

      stub(PouCon.DataPointManagerMock, :read_direct, fn
        "unmute_temp" -> {:ok, %{value: 35.0}}
        "unmute_siren_am" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      {:ok, _pid} = start_supervised({AlarmController, poll_interval_ms: @test_poll_interval})
      Process.sleep(200)

      # Mute then unmute
      AlarmController.mute(rule.id)
      Process.sleep(100)
      assert AlarmController.get_mute_expiry(rule.id) != nil

      AlarmController.unmute(rule.id)
      Process.sleep(100)

      assert AlarmController.get_mute_expiry(rule.id) == nil

      # Alarm should still be active
      status = AlarmController.status()
      assert rule.id in status.active_alarms
    end
  end

  describe "reload_rules/0" do
    test "reloads rules from database" do
      {:ok, _pid} = start_supervised({AlarmController, poll_interval_ms: @test_poll_interval})
      Process.sleep(100)

      initial_status = AlarmController.status()
      assert initial_status.rules_count == 0

      create_alarm_rule!("New Rule", ["siren_1"])

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

      {:ok, _} = AlarmRules.delete_rule(rule)
      Process.sleep(100)

      updated_status = AlarmController.status()
      assert updated_status.rules_count == 0
    end
  end

  describe "condition evaluation helpers" do
    test "threshold comparisons" do
      assert evaluate_threshold("above", 35.0, 30.0) == true
      assert evaluate_threshold("above", 25.0, 30.0) == false
      assert evaluate_threshold("below", 25.0, 30.0) == true
      assert evaluate_threshold("below", 35.0, 30.0) == false
      assert evaluate_threshold("equals", 30.0, 30.0) == true
      assert evaluate_threshold("equals", 30.05, 30.0) == true
      assert evaluate_threshold("equals", 30.2, 30.0) == false
    end

    test "equipment state checks" do
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

  defp apply_logic("any", results), do: Enum.any?(results, & &1)
  defp apply_logic("all", results), do: Enum.all?(results, & &1)
  defp apply_logic(_, results), do: Enum.any?(results, & &1)

  defp evaluate_threshold("above", value, threshold), do: value > threshold
  defp evaluate_threshold("below", value, threshold), do: value < threshold
  defp evaluate_threshold("equals", value, threshold), do: abs(value - threshold) < 0.1
  defp evaluate_threshold(_, _, _), do: false

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

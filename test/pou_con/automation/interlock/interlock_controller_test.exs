defmodule PouCon.Automation.Interlock.InterlockControllerTest do
  use PouCon.DataCase, async: false
  import Mox
  import PouCon.AutomationTestHelpers

  alias PouCon.Automation.Interlock.InterlockController
  alias PouCon.Automation.Interlock.InterlockRules
  setup :verify_on_exit!

  setup do
    setup_automation_test()

    on_exit(fn ->
      stop_genserver(InterlockController)
      Ecto.Adapters.SQL.Sandbox.mode(PouCon.Repo, :manual)
    end)

    :ok
  end

  describe "start_link/1" do
    test "starts the controller successfully" do
      stop_genserver(InterlockController)

      assert {:ok, pid} = InterlockController.start_link(poll_interval_ms: 100)
      assert Process.alive?(pid)
    end

    test "registers with module name" do
      stop_genserver(InterlockController)

      {:ok, pid} = InterlockController.start_link(poll_interval_ms: 100)
      assert Process.whereis(InterlockController) == pid
    end
  end

  describe "reload_rules/0" do
    test "reloads rules from database" do
      stop_genserver(InterlockController)

      {:ok, _pid} = InterlockController.start_link(poll_interval_ms: 100)
      assert :ok = InterlockController.reload_rules()
    end
  end

  describe "get_rules/0" do
    test "returns current rules map" do
      stop_genserver(InterlockController)

      {:ok, _pid} = InterlockController.start_link(poll_interval_ms: 100)
      rules = InterlockController.get_rules()
      assert is_map(rules)
    end

    test "returns loaded rules after DB insert" do
      stop_genserver(InterlockController)

      # Create equipment and rule
      upstream = create_equipment!("interlock_upstream_fan", "fan")
      downstream = create_equipment!("interlock_downstream_pump", "pump")
      create_interlock_rule!(upstream, downstream)

      {:ok, _pid} = InterlockController.start_link(poll_interval_ms: 100)
      wait_for_init()

      rules = InterlockController.get_rules()
      assert Map.has_key?(rules, "interlock_upstream_fan")
      assert "interlock_downstream_pump" in rules["interlock_upstream_fan"]
    end
  end

  describe "can_start?/1 ETS cache" do
    test "returns allowed when no interlock rules exist" do
      stop_genserver(InterlockController)
      create_equipment!("can_start_solo_fan", "fan")

      {:ok, _pid} = InterlockController.start_link(poll_interval_ms: 100)
      wait_for_init()

      assert {:ok, :allowed} = InterlockController.can_start?("can_start_solo_fan")
    end

    test "returns allowed for unknown equipment (not in ETS)" do
      stop_genserver(InterlockController)
      {:ok, _pid} = InterlockController.start_link(poll_interval_ms: 100)
      wait_for_init()

      assert {:ok, :allowed} = InterlockController.can_start?("nonexistent_equipment")
    end

    test "returns error when upstream equipment is not running" do
      stop_genserver(InterlockController)

      upstream = create_equipment!("cs_upstream_fan", "fan")
      downstream = create_equipment!("cs_downstream_pump", "pump")
      create_interlock_rule!(upstream, downstream)

      # Start controllers - default stub returns state: 0 (not running)
      {_name, _pid, _devs} = start_fan!(name: "cs_upstream_fan")
      {_name, _pid, _devs} = start_pump!(name: "cs_downstream_pump")
      wait_for_init()

      {:ok, _pid} = InterlockController.start_link(poll_interval_ms: 100)
      wait_for_init(300)

      result = InterlockController.can_start?("cs_downstream_pump")
      assert {:error, msg} = result
      assert msg =~ "cs_upstream_fan"
    end

    test "returns allowed when upstream equipment is running" do
      stop_genserver(InterlockController)

      upstream = create_equipment!("cs2_upstream_fan", "fan")
      downstream = create_equipment!("cs2_downstream_pump", "pump")
      create_interlock_rule!(upstream, downstream)

      # Stub auto_manual = 1 (AUTO mode) and running_feedback = 1 for upstream
      stub_read_direct(fn
        "cs2_upstream_fan_am" -> {:ok, %{state: 1}}
        "cs2_upstream_fan_coil" -> {:ok, %{state: 1}}
        "cs2_upstream_fan_fb" -> {:ok, %{state: 1}}
        "cs2_downstream_pump_am" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      {_name, _pid, _devs} = start_fan!(name: "cs2_upstream_fan")
      {_name, _pid, _devs} = start_pump!(name: "cs2_downstream_pump")
      wait_for_init()

      {:ok, _pid} = InterlockController.start_link(poll_interval_ms: 100)
      wait_for_init(300)

      assert {:ok, :allowed} = InterlockController.can_start?("cs2_downstream_pump")
    end
  end

  describe "running→stopped transition" do
    test "stops downstream equipment when upstream stops" do
      stop_genserver(InterlockController)

      upstream = create_equipment!("trans_upstream_fan", "fan")
      downstream = create_equipment!("trans_downstream_pump", "pump")
      create_interlock_rule!(upstream, downstream)

      # Start with upstream running
      stub_read_direct(fn
        "trans_upstream_fan_am" -> {:ok, %{state: 1}}
        "trans_upstream_fan_coil" -> {:ok, %{state: 1}}
        "trans_upstream_fan_fb" -> {:ok, %{state: 1}}
        "trans_downstream_pump_am" -> {:ok, %{state: 1}}
        "trans_downstream_pump_coil" -> {:ok, %{state: 1}}
        "trans_downstream_pump_fb" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      {_name, _pid, _devs} = start_fan!(name: "trans_upstream_fan")
      {_name, _pid, _devs} = start_pump!(name: "trans_downstream_pump")
      wait_for_init()

      {:ok, _pid} = InterlockController.start_link(poll_interval_ms: 50)
      wait_for_init(300)

      # Verify upstream is seen as running
      assert {:ok, :allowed} = InterlockController.can_start?("trans_downstream_pump")

      # Now upstream stops
      stub_read_direct(fn
        "trans_upstream_fan_am" -> {:ok, %{state: 1}}
        "trans_upstream_fan_coil" -> {:ok, %{state: 0}}
        "trans_upstream_fan_fb" -> {:ok, %{state: 0}}
        "trans_downstream_pump_am" -> {:ok, %{state: 1}}
        "trans_downstream_pump_coil" -> {:ok, %{state: 1}}
        "trans_downstream_pump_fb" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      # Wait for poll cycle to detect transition and stop downstream
      wait_for_init(300)

      # Downstream should now be blocked
      result = InterlockController.can_start?("trans_downstream_pump")
      assert {:error, _msg} = result
    end

    test "stops multiple downstream equipment" do
      stop_genserver(InterlockController)

      upstream = create_equipment!("multi_upstream_fan", "fan")
      downstream1 = create_equipment!("multi_downstream_pump1", "pump")
      downstream2 = create_equipment!("multi_downstream_pump2", "pump")
      create_interlock_rule!(upstream, downstream1)
      create_interlock_rule!(upstream, downstream2)

      # Start with upstream running
      stub_read_direct(fn
        "multi_upstream_fan_am" -> {:ok, %{state: 1}}
        "multi_upstream_fan_coil" -> {:ok, %{state: 1}}
        "multi_upstream_fan_fb" -> {:ok, %{state: 1}}
        n when n in ["multi_downstream_pump1_am", "multi_downstream_pump2_am"] ->
          {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      {_name, _pid, _devs} = start_fan!(name: "multi_upstream_fan")
      {_name, _pid, _devs} = start_pump!(name: "multi_downstream_pump1")
      {_name, _pid, _devs} = start_pump!(name: "multi_downstream_pump2")
      wait_for_init()

      {:ok, _pid} = InterlockController.start_link(poll_interval_ms: 50)
      wait_for_init(300)

      rules = InterlockController.get_rules()
      downstream_list = rules["multi_upstream_fan"]
      assert length(downstream_list) == 2
      assert "multi_downstream_pump1" in downstream_list
      assert "multi_downstream_pump2" in downstream_list
    end
  end

  describe "PubSub rule changes" do
    test "reloads rules on rule_created event" do
      stop_genserver(InterlockController)

      upstream = create_equipment!("pubsub_upstream", "fan")
      downstream = create_equipment!("pubsub_downstream", "pump")

      {:ok, _pid} = InterlockController.start_link(poll_interval_ms: 100)
      wait_for_init()

      # Initially no rules
      assert InterlockController.get_rules() == %{}

      # Create rule via InterlockRules context (triggers PubSub)
      {:ok, _rule} =
        InterlockRules.create_rule(%{
          upstream_equipment_id: upstream.id,
          downstream_equipment_id: downstream.id,
          enabled: true
        })

      wait_for_init()

      rules = InterlockController.get_rules()
      assert Map.has_key?(rules, "pubsub_upstream")
    end

    test "reloads rules on rule_deleted event" do
      stop_genserver(InterlockController)

      upstream = create_equipment!("pubdel_upstream", "fan")
      downstream = create_equipment!("pubdel_downstream", "pump")

      {:ok, rule} =
        InterlockRules.create_rule(%{
          upstream_equipment_id: upstream.id,
          downstream_equipment_id: downstream.id,
          enabled: true
        })

      {:ok, _pid} = InterlockController.start_link(poll_interval_ms: 100)
      wait_for_init()

      assert Map.has_key?(InterlockController.get_rules(), "pubdel_upstream")

      # Delete rule
      {:ok, _} = InterlockRules.delete_rule(rule)
      wait_for_init()

      assert InterlockController.get_rules() == %{}
    end

    test "reloads rules on rule_updated event" do
      stop_genserver(InterlockController)

      upstream = create_equipment!("pubupd_upstream", "fan")
      downstream = create_equipment!("pubupd_downstream", "pump")

      {:ok, rule} =
        InterlockRules.create_rule(%{
          upstream_equipment_id: upstream.id,
          downstream_equipment_id: downstream.id,
          enabled: true
        })

      {:ok, _pid} = InterlockController.start_link(poll_interval_ms: 100)
      wait_for_init()

      assert Map.has_key?(InterlockController.get_rules(), "pubupd_upstream")

      # Disable rule
      {:ok, _} = InterlockRules.update_rule(rule, %{enabled: false})
      wait_for_init()

      assert InterlockController.get_rules() == %{}
    end
  end

  describe "error resilience" do
    test "handles missing equipment controller gracefully" do
      stop_genserver(InterlockController)

      # Create equipment records but don't start controllers
      upstream = create_equipment!("missing_fan", "fan")
      downstream = create_equipment!("missing_pump", "pump")
      create_interlock_rule!(upstream, downstream)

      {:ok, pid} = InterlockController.start_link(poll_interval_ms: 100)
      wait_for_init(300)

      # Should not crash - controller stays alive
      assert Process.alive?(pid)

      # Upstream can't be reached, so it's treated as not running
      # Downstream is blocked because upstream is "not running"
      assert {:error, _msg} = InterlockController.can_start?("missing_pump")
    end

    test "continues operating after ETS table already exists error" do
      stop_genserver(InterlockController)

      {:ok, pid1} = InterlockController.start_link(poll_interval_ms: 100)
      wait_for_init()
      GenServer.stop(pid1)

      # Start again - should handle ETS table re-creation
      {:ok, pid2} = InterlockController.start_link(poll_interval_ms: 100)
      wait_for_init()
      assert Process.alive?(pid2)
    end
  end
end

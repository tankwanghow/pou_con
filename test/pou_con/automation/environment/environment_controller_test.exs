defmodule PouCon.Automation.Environment.EnvironmentControllerTest do
  use PouCon.DataCase, async: false
  import Mox
  import PouCon.AutomationTestHelpers

  alias PouCon.Automation.Environment.EnvironmentController
  alias PouCon.Automation.Environment.{Configs, FailsafeValidator}

  setup :verify_on_exit!

  setup do
    setup_automation_test()

    on_exit(fn ->
      stop_genserver(EnvironmentController)
      stop_genserver(FailsafeValidator)
      Ecto.Adapters.SQL.Sandbox.mode(PouCon.Repo, :manual)
    end)

    :ok
  end

  describe "start_link/1" do
    test "starts the controller successfully" do
      stop_genserver(EnvironmentController)
      stop_genserver(FailsafeValidator)

      {:ok, _fs_pid} = FailsafeValidator.start_link()
      assert {:ok, pid} = EnvironmentController.start_link()
      assert Process.alive?(pid)
    end

    test "registers with module name" do
      stop_genserver(EnvironmentController)
      stop_genserver(FailsafeValidator)

      {:ok, _fs_pid} = FailsafeValidator.start_link()
      {:ok, pid} = EnvironmentController.start_link()
      assert Process.whereis(EnvironmentController) == pid
    end
  end

  describe "status/0" do
    test "returns status map with expected keys" do
      stop_genserver(EnvironmentController)
      stop_genserver(FailsafeValidator)

      {:ok, _fs_pid} = FailsafeValidator.start_link()
      {:ok, _pid} = EnvironmentController.start_link()
      wait_for_init(300)

      status = EnvironmentController.status()
      assert is_map(status)
      assert Map.has_key?(status, :enabled)
      assert Map.has_key?(status, :avg_temp)
      assert Map.has_key?(status, :avg_humidity)
      assert Map.has_key?(status, :current_step)
      assert Map.has_key?(status, :pending_step)
      assert Map.has_key?(status, :humidity_override)
      assert Map.has_key?(status, :auto_fans_on)
      assert Map.has_key?(status, :target_pumps)
      assert Map.has_key?(status, :pumps_on)
      assert Map.has_key?(status, :failsafe_fans_count)
      assert Map.has_key?(status, :delta_boost_active)
    end
  end

  describe "get_averages/0" do
    test "returns tuple of avg_temp and avg_humidity" do
      stop_genserver(EnvironmentController)
      stop_genserver(FailsafeValidator)

      {:ok, _fs_pid} = FailsafeValidator.start_link()
      {:ok, _pid} = EnvironmentController.start_link()
      wait_for_init(300)

      {avg_temp, avg_humidity} = EnvironmentController.get_averages()
      # No sensors configured, so both should be nil
      assert avg_temp == nil
      assert avg_humidity == nil
    end
  end

  describe "disabled behavior" do
    test "does not control fans when disabled" do
      stop_genserver(EnvironmentController)
      stop_genserver(FailsafeValidator)

      # Config is disabled by default
      config = Configs.get_config()
      assert config.enabled == false

      create_equipment!("env_fan_1", "fan")
      {_name, _pid, _devs} = start_fan!(name: "env_fan_1")

      stub_read_direct(fn
        "env_fan_1_am" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      wait_for_init()

      {:ok, _fs_pid} = FailsafeValidator.start_link()
      {:ok, _pid} = EnvironmentController.start_link()
      wait_for_init(300)

      status = EnvironmentController.status()
      assert status.enabled == false
      assert status.auto_fans_on == []
    end
  end

  describe "enabled with temperature steps" do
    setup do
      # Enable environment control with 2 steps
      {:ok, _config} =
        Configs.update_config(%{
          enabled: true,
          step_1_temp: 25.0,
          step_1_extra_fans: 1,
          step_1_pumps: "",
          step_2_temp: 28.0,
          step_2_extra_fans: 2,
          step_2_pumps: "",
          failsafe_fans_count: 1,
          stagger_delay_seconds: 2,
          delay_between_step_seconds: 30,
          environment_poll_interval_ms: 5000
        })

      :ok
    end

    test "determines step based on temperature" do
      stop_genserver(EnvironmentController)
      stop_genserver(FailsafeValidator)

      # Create temp sensor equipment
      create_equipment!("avg_sensor", "average_sensor")

      # Create fans
      create_equipment!("step_fan_1", "fan")
      create_equipment!("step_fan_2", "fan")
      create_equipment!("step_fan_3", "fan")
      {_name, _pid, _devs} = start_fan!(name: "step_fan_1")
      {_name, _pid, _devs} = start_fan!(name: "step_fan_2")
      {_name, _pid, _devs} = start_fan!(name: "step_fan_3")

      # Set all fans to AUTO mode
      stub_read_direct(fn
        name when name in ["step_fan_1_am", "step_fan_2_am", "step_fan_3_am"] ->
          {:ok, %{state: 1}}

        _ ->
          {:ok, %{state: 0}}
      end)

      # Stub get_cached_data for average sensor
      stub(PouCon.DataPointManagerMock, :get_cached_data, fn _name ->
        {:ok, %{value: 26.0}}
      end)

      wait_for_init()

      # Create a failsafe fan (MANUAL + running)
      create_equipment!("failsafe_fan", "fan")
      {_name, _pid, _devs} = start_fan!(name: "failsafe_fan")

      # Override stub to include failsafe fan
      stub_read_direct(fn
        "failsafe_fan_am" -> {:ok, %{state: 0}}
        "failsafe_fan_fb" -> {:ok, %{state: 1}}
        name when name in ["step_fan_1_am", "step_fan_2_am", "step_fan_3_am"] ->
          {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      wait_for_init()

      {:ok, _fs_pid} = FailsafeValidator.start_link()
      {:ok, _pid} = EnvironmentController.start_link()
      wait_for_init(500)

      status = EnvironmentController.status()
      assert status.enabled == true
      # With temp 26.0, should be at step 1 (threshold 25.0)
      assert status.current_step == 1
    end
  end

  describe "humidity override" do
    test "humidity_override_status returns correct values" do
      config = Configs.get_config()

      assert Configs.humidity_override_status(config, 90.0) == :force_all_off
      assert Configs.humidity_override_status(config, 30.0) == :force_all_on
      assert Configs.humidity_override_status(config, 60.0) == :normal
    end

    test "humidity_override_status handles nil humidity" do
      config = Configs.get_config()
      assert Configs.humidity_override_status(config, nil) == :normal
    end
  end

  describe "State struct" do
    test "State module is defined" do
      assert Code.ensure_loaded?(EnvironmentController.State)
    end

    test "State has expected fields" do
      state = %EnvironmentController.State{}
      assert Map.has_key?(state, :avg_temp)
      assert Map.has_key?(state, :avg_humidity)
      assert Map.has_key?(state, :auto_fans_on)
      assert Map.has_key?(state, :target_pumps)
      assert Map.has_key?(state, :current_pumps_on)
      assert Map.has_key?(state, :current_step)
      assert Map.has_key?(state, :pending_step)
      assert Map.has_key?(state, :last_step_change_time)
      assert Map.has_key?(state, :last_switch_time)
      assert Map.has_key?(state, :humidity_override)
      assert Map.has_key?(state, :enabled)
      assert Map.has_key?(state, :delta_boost_active)
      assert Map.has_key?(state, :front_temp)
      assert Map.has_key?(state, :back_temp)
      assert Map.has_key?(state, :temp_delta)
    end

    test "State has correct default values" do
      state = %EnvironmentController.State{}
      assert state.avg_temp == nil
      assert state.avg_humidity == nil
      assert state.auto_fans_on == []
      assert state.target_pumps == []
      assert state.current_pumps_on == []
      assert state.current_step == nil
      assert state.pending_step == nil
      assert state.last_step_change_time == nil
      assert state.last_switch_time == nil
      assert state.humidity_override == :normal
      assert state.enabled == false
      assert state.delta_boost_active == false
    end
  end

  describe "get_extra_fans_for_temp/2" do
    setup do
      {:ok, _config} =
        Configs.update_config(%{
          step_1_temp: 25.0,
          step_1_extra_fans: 1,
          step_2_temp: 28.0,
          step_2_extra_fans: 2,
          step_3_temp: 30.0,
          step_3_extra_fans: 4
        })

      config = Configs.get_config()
      %{config: config}
    end

    test "returns 0 below all thresholds", %{config: config} do
      assert Configs.get_extra_fans_for_temp(config, 20.0) == 0
    end

    test "returns step 1 fans at step 1 temp", %{config: config} do
      assert Configs.get_extra_fans_for_temp(config, 25.0) == 1
    end

    test "returns step 1 fans between step 1 and step 2", %{config: config} do
      assert Configs.get_extra_fans_for_temp(config, 27.0) == 1
    end

    test "returns step 2 fans at step 2 temp", %{config: config} do
      assert Configs.get_extra_fans_for_temp(config, 28.0) == 2
    end

    test "returns step 3 fans above step 3 temp", %{config: config} do
      assert Configs.get_extra_fans_for_temp(config, 35.0) == 4
    end

    test "returns 0 for nil temp", %{config: config} do
      assert Configs.get_extra_fans_for_temp(config, nil) == 0
    end
  end

  describe "error resilience" do
    test "handles missing fan controllers gracefully" do
      stop_genserver(EnvironmentController)
      stop_genserver(FailsafeValidator)

      {:ok, _config} =
        Configs.update_config(%{
          enabled: true,
          step_1_temp: 25.0,
          step_1_extra_fans: 1
        })

      # Create equipment but don't start controllers
      create_equipment!("missing_fan", "fan")

      {:ok, _fs_pid} = FailsafeValidator.start_link()
      {:ok, pid} = EnvironmentController.start_link()
      wait_for_init(300)

      # Should not crash
      assert Process.alive?(pid)
    end

    test "continues after restart" do
      stop_genserver(EnvironmentController)
      stop_genserver(FailsafeValidator)

      {:ok, _fs_pid} = FailsafeValidator.start_link()
      {:ok, pid1} = EnvironmentController.start_link()
      wait_for_init()
      GenServer.stop(pid1)

      {:ok, pid2} = EnvironmentController.start_link()
      wait_for_init()
      assert Process.alive?(pid2)
    end
  end
end

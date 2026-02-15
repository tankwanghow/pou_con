defmodule PouCon.Automation.Environment.FailsafeValidatorTest do
  use PouCon.DataCase, async: false
  import Mox
  import PouCon.AutomationTestHelpers

  alias PouCon.Automation.Environment.FailsafeValidator

  setup :verify_on_exit!

  setup do
    setup_automation_test()

    on_exit(fn ->
      stop_genserver(FailsafeValidator)
      Ecto.Adapters.SQL.Sandbox.mode(PouCon.Repo, :manual)
    end)

    :ok
  end

  describe "start_link/1" do
    test "starts the validator successfully" do
      stop_genserver(FailsafeValidator)

      assert {:ok, pid} = FailsafeValidator.start_link()
      assert Process.alive?(pid)
    end

    test "registers with module name" do
      stop_genserver(FailsafeValidator)

      {:ok, pid} = FailsafeValidator.start_link()
      assert Process.whereis(FailsafeValidator) == pid
    end
  end

  describe "status/0" do
    test "returns default status when no fans exist" do
      stop_genserver(FailsafeValidator)

      {:ok, _pid} = FailsafeValidator.start_link()
      wait_for_init()

      status = FailsafeValidator.status()
      assert is_map(status)
      assert Map.has_key?(status, :valid)
      assert Map.has_key?(status, :expected)
      assert Map.has_key?(status, :actual)
      assert Map.has_key?(status, :fans)
      assert Map.has_key?(status, :auto_valid)
      assert Map.has_key?(status, :auto_required)
      assert Map.has_key?(status, :auto_available)
      assert Map.has_key?(status, :auto_fans)
      assert Map.has_key?(status, :config_valid)
      assert Map.has_key?(status, :total_fans)
      assert Map.has_key?(status, :max_possible_auto)
    end

    test "returns default status when process is not running" do
      stop_genserver(FailsafeValidator)

      status = FailsafeValidator.status()
      assert status.valid == true
      assert status.expected == 0
      assert status.actual == 0
    end
  end

  describe "failsafe fan detection" do
    test "counts fans in MANUAL mode that are running as failsafe" do
      stop_genserver(FailsafeValidator)

      create_equipment!("fs_fan_1", "fan")
      {_name, _pid, _devs} = start_fan!(name: "fs_fan_1")

      # Set fan to MANUAL mode (auto_manual = 0) and running (feedback = 1)
      stub_read_direct(fn
        "fs_fan_1_am" -> {:ok, %{state: 0}}
        "fs_fan_1_fb" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      wait_for_init()

      {:ok, _pid} = FailsafeValidator.start_link()
      wait_for_init(300)

      status = FailsafeValidator.status()
      assert "fs_fan_1" in status.fans
      assert status.actual >= 1
    end

    test "excludes fans in AUTO mode from failsafe count" do
      stop_genserver(FailsafeValidator)

      create_equipment!("fs_auto_fan", "fan")
      {_name, _pid, _devs} = start_fan!(name: "fs_auto_fan")

      # Set fan to AUTO mode (auto_manual = 1) and running
      stub_read_direct(fn
        "fs_auto_fan_am" -> {:ok, %{state: 1}}
        "fs_auto_fan_fb" -> {:ok, %{state: 1}}
        "fs_auto_fan_coil" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      wait_for_init()

      {:ok, _pid} = FailsafeValidator.start_link()
      wait_for_init(300)

      status = FailsafeValidator.status()
      assert "fs_auto_fan" not in status.fans
    end

    test "excludes fans in MANUAL mode that are NOT running" do
      stop_genserver(FailsafeValidator)

      create_equipment!("fs_off_fan", "fan")
      {_name, _pid, _devs} = start_fan!(name: "fs_off_fan")

      # Set fan to MANUAL mode but not running (feedback = 0)
      stub_read_direct(fn
        "fs_off_fan_am" -> {:ok, %{state: 0}}
        "fs_off_fan_fb" -> {:ok, %{state: 0}}
        _ -> {:ok, %{state: 0}}
      end)

      wait_for_init()

      {:ok, _pid} = FailsafeValidator.start_link()
      wait_for_init(300)

      status = FailsafeValidator.status()
      assert "fs_off_fan" not in status.fans
    end
  end

  describe "auto fan availability" do
    test "counts fans in AUTO mode as available" do
      stop_genserver(FailsafeValidator)

      create_equipment!("avail_fan_1", "fan")
      {_name, _pid, _devs} = start_fan!(name: "avail_fan_1")

      # Set fan to AUTO mode
      stub_read_direct(fn
        "avail_fan_1_am" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      wait_for_init()

      {:ok, _pid} = FailsafeValidator.start_link()
      wait_for_init(300)

      status = FailsafeValidator.status()
      assert "avail_fan_1" in status.auto_fans
      assert status.auto_available >= 1
    end
  end

  describe "validation logic" do
    test "valid when failsafe count meets requirement" do
      stop_genserver(FailsafeValidator)

      # Config requires 1 failsafe fan (default)
      create_equipment!("val_fan_1", "fan")
      {_name, _pid, _devs} = start_fan!(name: "val_fan_1")

      # Set fan to MANUAL + running
      stub_read_direct(fn
        "val_fan_1_am" -> {:ok, %{state: 0}}
        "val_fan_1_fb" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      wait_for_init()

      {:ok, _pid} = FailsafeValidator.start_link()
      wait_for_init(300)

      status = FailsafeValidator.status()
      assert status.actual >= status.expected
    end
  end

  describe "check_now/0" do
    test "forces an immediate check" do
      stop_genserver(FailsafeValidator)

      {:ok, pid} = FailsafeValidator.start_link()
      wait_for_init()

      FailsafeValidator.check_now()
      Process.sleep(100)

      assert Process.alive?(pid)
    end
  end

  describe "PubSub broadcasts" do
    test "broadcasts status on startup" do
      stop_genserver(FailsafeValidator)

      Phoenix.PubSub.subscribe(PouCon.PubSub, "failsafe_status")

      {:ok, _pid} = FailsafeValidator.start_link()

      assert_receive {:failsafe_status, status}, 1000
      assert is_map(status)
      assert Map.has_key?(status, :valid)
    end

    test "broadcasts on check_now" do
      stop_genserver(FailsafeValidator)

      {:ok, _pid} = FailsafeValidator.start_link()
      wait_for_init()

      Phoenix.PubSub.subscribe(PouCon.PubSub, "failsafe_status")

      FailsafeValidator.check_now()

      assert_receive {:failsafe_status, _status}, 1000
    end
  end

  describe "error resilience" do
    test "handles missing fan controllers gracefully" do
      stop_genserver(FailsafeValidator)

      # Create equipment but don't start controller
      create_equipment!("ghost_fan", "fan")

      {:ok, pid} = FailsafeValidator.start_link()
      wait_for_init(300)

      # Should not crash
      assert Process.alive?(pid)
      status = FailsafeValidator.status()
      assert is_map(status)
    end
  end
end

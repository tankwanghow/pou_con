defmodule PouCon.Automation.Environment.EnvironmentControllerTest do
  use ExUnit.Case, async: false

  alias PouCon.Automation.Environment.EnvironmentController

  describe "module structure" do
    test "module is defined and loaded" do
      assert Code.ensure_loaded?(EnvironmentController)
    end

    test "exports start_link/0" do
      Code.ensure_loaded!(EnvironmentController)
      assert function_exported?(EnvironmentController, :start_link, 0)
    end

    test "exports start_link/1" do
      Code.ensure_loaded!(EnvironmentController)
      assert function_exported?(EnvironmentController, :start_link, 1)
    end

    test "exports status/0" do
      Code.ensure_loaded!(EnvironmentController)
      assert function_exported?(EnvironmentController, :status, 0)
    end

    test "exports get_averages/0" do
      Code.ensure_loaded!(EnvironmentController)
      assert function_exported?(EnvironmentController, :get_averages, 0)
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
    end
  end
end

defmodule PouCon.Automation.Interlock.InterlockControllerTest do
  use PouCon.DataCase, async: false
  import Mox

  alias PouCon.Automation.Interlock.InterlockController

  setup :verify_on_exit!

  setup do
    # Set sandbox to shared mode so GenServer can access database
    Ecto.Adapters.SQL.Sandbox.mode(PouCon.Repo, {:shared, self()})

    # Set mock to global mode for GenServer
    Mox.set_mox_global(PouCon.DeviceManagerMock)

    # Default stub for DeviceManager
    stub(PouCon.DeviceManagerMock, :get_cached_data, fn _name ->
      {:ok, %{state: 0}}
    end)

    stub(PouCon.DeviceManagerMock, :command, fn _name, _cmd, _params ->
      {:ok, :success}
    end)

    on_exit(fn ->
      # Reset sandbox mode to default
      Ecto.Adapters.SQL.Sandbox.mode(PouCon.Repo, :manual)
    end)

    :ok
  end

  describe "start_link/1" do
    test "starts the controller successfully" do
      stop_existing_controller()

      assert {:ok, pid} = InterlockController.start_link()
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "registers with module name" do
      stop_existing_controller()

      {:ok, pid} = InterlockController.start_link()
      assert Process.whereis(PouCon.Automation.Interlock.InterlockController) == pid
      GenServer.stop(pid)
    end
  end

  describe "reload_rules/0" do
    test "reloads rules from database" do
      stop_existing_controller()

      {:ok, _pid} = InterlockController.start_link()
      assert :ok = InterlockController.reload_rules()
      GenServer.stop(InterlockController)
    end
  end

  describe "get_rules/0" do
    test "returns current rules map" do
      stop_existing_controller()

      {:ok, _pid} = InterlockController.start_link()
      rules = InterlockController.get_rules()
      assert is_map(rules)
      GenServer.stop(InterlockController)
    end
  end

  # Helper functions

  defp stop_existing_controller do
    case Process.whereis(PouCon.Automation.Interlock.InterlockController) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end
  end
end

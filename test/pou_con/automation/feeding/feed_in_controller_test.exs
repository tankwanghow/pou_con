defmodule PouCon.Automation.Feeding.FeedInControllerTest do
  use PouCon.DataCase, async: false
  import Mox

  alias PouCon.Automation.Feeding.FeedInController

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

      assert {:ok, pid} = FeedInController.start_link()
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "registers with module name" do
      stop_existing_controller()

      {:ok, pid} = FeedInController.start_link()
      assert Process.whereis(PouCon.Automation.Feeding.FeedInController) == pid
      GenServer.stop(pid)
    end
  end

  describe "reload_schedules/0" do
    test "sends reload message to controller" do
      stop_existing_controller()

      {:ok, _pid} = FeedInController.start_link()
      assert :ok = FeedInController.reload_schedules()
      GenServer.stop(FeedInController)
    end
  end

  describe "schedule_updated/0" do
    test "calls reload_schedules" do
      stop_existing_controller()

      {:ok, _pid} = FeedInController.start_link()
      assert :ok = FeedInController.schedule_updated()
      GenServer.stop(FeedInController)
    end
  end

  # Helper functions

  defp stop_existing_controller do
    case Process.whereis(PouCon.Automation.Feeding.FeedInController) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end
  end
end

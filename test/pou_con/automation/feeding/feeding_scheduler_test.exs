defmodule PouCon.Automation.Feeding.FeedingSchedulerTest do
  use PouCon.DataCase, async: false
  import Mox

  alias PouCon.Automation.Feeding.FeedingScheduler

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
    test "starts the scheduler successfully" do
      stop_existing_scheduler()

      assert {:ok, pid} = FeedingScheduler.start_link()
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "registers with module name" do
      stop_existing_scheduler()

      {:ok, pid} = FeedingScheduler.start_link()
      assert Process.whereis(PouCon.Automation.Feeding.FeedingScheduler) == pid
      GenServer.stop(pid)
    end
  end

  # Helper functions

  defp stop_existing_scheduler do
    case Process.whereis(PouCon.Automation.Feeding.FeedingScheduler) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end
  end
end

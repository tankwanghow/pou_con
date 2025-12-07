defmodule PouCon.Automation.EggCollection.EggCollectionSchedulerTest do
  use ExUnit.Case, async: false
  import Mox

  alias PouCon.Automation.EggCollection.EggCollectionScheduler

  setup :verify_on_exit!

  setup do
    # Set mock to global mode for GenServer
    Mox.set_mox_global(PouCon.DeviceManagerMock)

    # Default stub for DeviceManager
    stub(PouCon.DeviceManagerMock, :get_cached_data, fn _name ->
      {:ok, %{state: 0}}
    end)

    stub(PouCon.DeviceManagerMock, :command, fn _name, _cmd, _params ->
      {:ok, :success}
    end)

    :ok
  end

  describe "start_link/1" do
    test "starts the scheduler successfully" do
      stop_existing_scheduler()

      assert {:ok, pid} = EggCollectionScheduler.start_link()
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "registers with module name" do
      stop_existing_scheduler()

      {:ok, pid} = EggCollectionScheduler.start_link()
      assert Process.whereis(PouCon.Automation.EggCollection.EggCollectionScheduler) == pid
      GenServer.stop(pid)
    end
  end


  # Helper functions

  defp stop_existing_scheduler do
    case Process.whereis(PouCon.Automation.EggCollection.EggCollectionScheduler) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end
  end

  defp ensure_scheduler_running do
    case Process.whereis(PouCon.Automation.EggCollection.EggCollectionScheduler) do
      nil -> EggCollectionScheduler.start_link()
      _pid -> :ok
    end
  end
end
